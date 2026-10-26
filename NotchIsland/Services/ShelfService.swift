import AppKit
import Combine
import UniformTypeIdentifiers

struct ShelfItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case file
        case text
    }

    let id: UUID
    var kind: Kind
    var name: String
    /// Last known location, for `.file` items.
    var path: String?
    /// Follows the original file if it is moved or renamed.
    var bookmark: Data?
    /// The file lives in the app's own shelf folder and is deleted with the item.
    var isCopy: Bool
    /// Contents of `.text` items (plain text or a web link).
    var text: String?
    var addedAt: Date

    var url: URL? { path.map { URL(fileURLWithPath: $0) } }
}

/// Persists shelf items; swapped for an in-memory store in tests.
protocol ShelfStore {
    func load() -> [ShelfItem]
    func save(_ items: [ShelfItem])
}

/// Items as JSON in ~/Library/Application Support/NotchIsland/shelf.json.
struct JSONShelfStore: ShelfStore {
    let fileURL: URL

    func load() -> [ShelfItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([ShelfItem].self, from: data)) ?? []
    }

    func save(_ items: [ShelfItem]) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try JSONEncoder().encode(items).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("NotchIsland: failed to save shelf: \(error)")
        }
    }
}

final class ShelfService: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    /// Types accepted by the drop target, most specific first.
    static let acceptedTypes: [UTType] = [.fileURL, .image, .url, .plainText]

    private let store: ShelfStore
    /// Where copied files and dropped image data are kept.
    let filesDirectory: URL

    init(store: ShelfStore? = nil, directory: URL = ShelfService.defaultDirectory) {
        self.store = store ?? JSONShelfStore(fileURL: directory.appendingPathComponent("shelf.json"))
        filesDirectory = directory.appendingPathComponent("Files", isDirectory: true)
        let loaded = self.store.load()
        items = loaded.map(Self.refreshingLocation)
        if items != loaded { self.store.save(items) }
    }

    static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("NotchIsland", isDirectory: true)
    }

    /// Keep copies of dropped files instead of references (off by default).
    private var copiesFiles: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.shelfCopiesFiles)
    }

    // MARK: - Adding

    /// Handles a drop. Item providers load asynchronously; each result is
    /// added on the main actor as it arrives.
    func add(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor [weak self] in self?.addFile(at: url) }
                }
            } else if let imageType = provider.registeredTypeIdentifiers
                .compactMap(UTType.init)
                .first(where: { $0.conforms(to: .image) }) {
                provider.loadDataRepresentation(forTypeIdentifier: imageType.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor [weak self] in self?.addImageData(data, type: imageType) }
                }
            } else if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor [weak self] in self?.addText(url.absoluteString) }
                }
            } else if provider.canLoadObject(ofClass: String.self) {
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    guard let text else { return }
                    Task { @MainActor [weak self] in self?.addText(text) }
                }
            }
        }
    }

    func addFile(at url: URL) {
        let standardized = url.standardizedFileURL
        guard !items.contains(where: { $0.path == standardized.path }) else { return }

        guard copiesFiles else {
            append(fileItem(for: standardized, isCopy: false))
            return
        }
        // Copying a large folder can take a while; keep it off the main thread.
        let destination = uniqueDestination(for: standardized.lastPathComponent)
        Task.detached {
            do {
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try FileManager.default.copyItem(at: standardized, to: destination)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.append(self.fileItem(for: destination, isCopy: true))
                }
            } catch {
                NSLog("NotchIsland: failed to copy \(standardized.path): \(error)")
            }
        }
    }

    func addText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let firstLine = trimmed.prefix { !$0.isNewline }
        append(ShelfItem(
            id: UUID(), kind: .text, name: String(firstLine.prefix(60)),
            path: nil, bookmark: nil, isCopy: false, text: trimmed, addedAt: Date()
        ))
    }

    /// Images dragged from apps like browsers arrive as data, not files, so
    /// they are always saved into the shelf folder.
    func addImageData(_ data: Data, type: UTType) {
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: ".")
        let name = "Image \(stamp).\(type.preferredFilenameExtension ?? "png")"
        let destination = uniqueDestination(for: name)
        do {
            try FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
            try data.write(to: destination)
            append(fileItem(for: destination, isCopy: true))
        } catch {
            NSLog("NotchIsland: failed to save dropped image: \(error)")
        }
    }

    // MARK: - Removing

    func remove(_ item: ShelfItem) {
        deleteCopy(of: item)
        items.removeAll { $0.id == item.id }
        store.save(items)
    }

    func removeAll() {
        items.forEach(deleteCopy)
        items.removeAll()
        store.save(items)
    }

    // MARK: - Using items

    func fileExists(_ item: ShelfItem) -> Bool {
        guard let path = item.path else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    /// What gets handed to the destination when an item is dragged out.
    func itemProvider(for item: ShelfItem) -> NSItemProvider {
        switch item.kind {
        case .file:
            guard let url = item.url else { return NSItemProvider() }
            let provider = NSItemProvider(object: url as NSURL)
            provider.suggestedName = url.lastPathComponent
            return provider
        case .text:
            return NSItemProvider(object: (item.text ?? "") as NSString)
        }
    }

    func open(_ item: ShelfItem) {
        switch item.kind {
        case .file:
            if let url = item.url { NSWorkspace.shared.open(url) }
        case .text:
            if let text = item.text, let url = URL(string: text), url.scheme?.hasPrefix("http") == true {
                NSWorkspace.shared.open(url)
            } else {
                copyToPasteboard(item)
            }
        }
    }

    func revealInFinder(_ item: ShelfItem) {
        guard let url = item.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyToPasteboard(_ item: ShelfItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.kind {
        case .file:
            if let url = item.url { pasteboard.writeObjects([url as NSURL]) }
        case .text:
            pasteboard.setString(item.text ?? "", forType: .string)
        }
    }

    // MARK: - Helpers

    private func append(_ item: ShelfItem) {
        items.append(item)
        store.save(items)
    }

    private func fileItem(for url: URL, isCopy: Bool) -> ShelfItem {
        ShelfItem(
            id: UUID(), kind: .file, name: url.lastPathComponent, path: url.path,
            bookmark: try? url.bookmarkData(), isCopy: isCopy, text: nil, addedAt: Date()
        )
    }

    private func deleteCopy(of item: ShelfItem) {
        guard item.isCopy, let url = item.url, url.path.hasPrefix(filesDirectory.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// "Name.ext", or "Name 2.ext", "Name 3.ext"… if taken.
    private func uniqueDestination(for fileName: String) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = filesDirectory.appendingPathComponent(fileName)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = filesDirectory.appendingPathComponent(name)
            counter += 1
        }
        return candidate
    }

    /// Follows the bookmark so items survive the original being moved or renamed.
    private static func refreshingLocation(_ item: ShelfItem) -> ShelfItem {
        guard item.kind == .file, let bookmark = item.bookmark else { return item }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark, options: .withoutUI, bookmarkDataIsStale: &isStale
        ) else { return item }

        var updated = item
        updated.path = url.path
        updated.name = url.lastPathComponent
        if isStale, let fresh = try? url.bookmarkData() { updated.bookmark = fresh }
        return updated
    }
}
