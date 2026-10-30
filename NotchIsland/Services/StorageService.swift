import AppKit
import Combine

/// Startup volume capacity, in bytes.
struct StorageVolume: Equatable {
    var total: Int64
    /// Free space counting purgeable data, as Finder reports it.
    var available: Int64
    /// Free space right now, without purging anything.
    var free: Int64

    var used: Int64 { max(0, total - available) }
    /// Caches and the like that macOS deletes on its own when space runs low.
    var purgeable: Int64 { max(0, available - free) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

/// A folder the Storage tab measures.
struct StorageLocation: Identifiable, Equatable {
    enum Kind {
        /// The user's own files: removing moves them to the Trash.
        case personal
        /// Rebuildable data (caches, build output): removing deletes for good.
        case clearable
        /// The Trash itself: removing deletes for good.
        case trash
    }

    let name: String
    let symbol: String
    let url: URL
    var kind: Kind = .personal

    var id: String { url.path }
    /// Whether removing an item skips the Trash.
    var deletesPermanently: Bool { kind != .personal }
}

nonisolated enum FolderSize: Equatable, Sendable {
    case unknown
    case measuring
    case measured(Int64)
    /// macOS refused to list the folder (privacy protection).
    case noAccess

    var bytes: Int64? {
        if case .measured(let bytes) = self { return bytes }
        return nil
    }
}

/// A file or folder inside the folder being browsed.
nonisolated struct StorageItem: Identifiable, Equatable, Sendable {
    let url: URL
    let name: String
    /// A folder that can be opened in the tab (packages such as apps can't).
    let isFolder: Bool
    var size: FolderSize = .measuring

    var id: String { url.path }
}

/// Startup disk usage, the size of the folders that usually fill it, and a
/// browser for finding and removing what's taking the space.
///
/// Folder sizes are measured only when asked: walking them is slow, and the
/// first walk of Desktop, Documents and Downloads triggers privacy prompts.
final class StorageService: ObservableObject {
    @Published private(set) var volume: StorageVolume?
    @Published private(set) var locations: [StorageLocation]
    @Published private(set) var sizes: [String: FolderSize] = [:]
    @Published private(set) var isScanning = false
    @Published private(set) var lastScan: Date?

    /// The location being browsed; nil shows the overview.
    @Published private(set) var browseRoot: StorageLocation?
    /// Folders opened from `browseRoot` down; the last one is listed in `items`.
    @Published private(set) var browsePath: [URL] = []
    @Published private(set) var items: [StorageItem] = []
    @Published private(set) var isListing = false
    /// Outcome of the last removal, shown briefly under the browser header.
    @Published private(set) var message: String?

    static let storageSettingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.Storage")!
    /// Folders measured at once; more just makes the disk thrash.
    private static let maxConcurrentMeasurements = 4

    private var scanTask: Task<Void, Never>?
    private var listTask: Task<Void, Never>?

    init(locations: [StorageLocation] = StorageService.defaultLocations()) {
        self.locations = locations
    }

    /// Common space hogs that exist on this Mac.
    static func defaultLocations() -> [StorageLocation] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        func inHome(_ path: String) -> URL { home.appendingPathComponent(path, isDirectory: true) }

        let candidates = [
            StorageLocation(name: String(localized: "Downloads"), symbol: "arrow.down.circle.fill", url: inHome("Downloads")),
            StorageLocation(name: String(localized: "Desktop"), symbol: "menubar.dock.rectangle", url: inHome("Desktop")),
            StorageLocation(name: String(localized: "Documents"), symbol: "doc.fill", url: inHome("Documents")),
            StorageLocation(name: String(localized: "Movies"), symbol: "film.fill", url: inHome("Movies")),
            StorageLocation(name: String(localized: "Pictures"), symbol: "photo.fill", url: inHome("Pictures")),
            StorageLocation(name: String(localized: "Music"), symbol: "music.note", url: inHome("Music")),
            StorageLocation(name: String(localized: "Applications"), symbol: "square.grid.2x2.fill",
                            url: URL(fileURLWithPath: "/Applications", isDirectory: true)),
            StorageLocation(name: String(localized: "Trash"), symbol: "trash.fill", url: inHome(".Trash"), kind: .trash),
            StorageLocation(name: String(localized: "Caches"), symbol: "shippingbox.fill",
                            url: inHome("Library/Caches"), kind: .clearable),
            StorageLocation(name: "Xcode DerivedData", symbol: "hammer.fill",
                            url: inHome("Library/Developer/Xcode/DerivedData"), kind: .clearable),
        ]
        return candidates.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    // MARK: Overview

    /// Cheap; run whenever the tab appears.
    func refreshVolume() {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage,
              total > 0
        else {
            volume = nil
            return
        }
        let free = values.volumeAvailableCapacity.map(Int64.init) ?? available
        volume = StorageVolume(total: Int64(total), available: available, free: free)
    }

    /// Measures every location off the main thread, then sorts the list
    /// largest first.
    func scan() {
        guard !isScanning else { return }
        refreshVolume()
        isScanning = true
        for location in locations { sizes[location.id] = .measuring }

        let targets = locations.map { ($0.id, $0.url) }
        scanTask = Task { [weak self] in
            await Self.measure(targets) { id, size in
                self?.sizes[id] = size.map(FolderSize.measured) ?? .noAccess
            }
            guard let self else { return }
            locations.sort { (sizes[$0.id]?.bytes ?? -1) > (sizes[$1.id]?.bytes ?? -1) }
            lastScan = Date()
            isScanning = false
            scanTask = nil
        }
    }

    func openStorageSettings() {
        NSWorkspace.shared.open(Self.storageSettingsURL)
    }

    // MARK: Browsing

    func browse(_ location: StorageLocation) {
        browseRoot = location
        browsePath = [location.url]
        message = nil
        listCurrentFolder()
    }

    func open(_ item: StorageItem) {
        guard item.isFolder else {
            reveal(item.url)
            return
        }
        browsePath.append(item.url)
        listCurrentFolder()
    }

    /// Up one folder, or back to the overview from the location itself.
    func goBack() {
        browsePath.removeLast()
        message = nil
        if browsePath.isEmpty {
            listTask?.cancel()
            browseRoot = nil
            items = []
            isListing = false
        } else {
            listCurrentFolder()
        }
    }

    var currentFolder: URL? { browsePath.last }

    /// Total of the measured items in the current folder.
    var currentFolderSize: Int64 {
        items.reduce(0) { $0 + ($1.size.bytes ?? 0) }
    }

    func reveal(_ url: URL) {
        if url == currentFolder || browsePath.isEmpty {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func dismissMessage() {
        message = nil
    }

    private func listCurrentFolder() {
        guard let folder = currentFolder else { return }
        listTask?.cancel()
        items = []
        isListing = true

        listTask = Task { [weak self] in
            let listed = await Task.detached(priority: .userInitiated) {
                FolderSizer.children(of: folder)
            }.value
            guard let self, !Task.isCancelled else { return }
            guard let listed else {
                isListing = false
                message = String(localized: "No access. Allow it in Privacy & Security › Full Disk Access.")
                return
            }
            items = listed

            await Self.measure(listed.map { ($0.id, $0.url) }) { [weak self] id, size in
                guard let self, let index = items.firstIndex(where: { $0.id == id }) else { return }
                items[index].size = size.map(FolderSize.measured) ?? .noAccess
            }
            guard !Task.isCancelled else { return }
            items.sort { ($0.size.bytes ?? -1) > ($1.size.bytes ?? -1) }
            isListing = false
        }
    }

    // MARK: Removing

    /// Moves a personal item to the Trash, or deletes a cache or Trash item
    /// for good. Only items below the browsed location are ever touched.
    func remove(_ item: StorageItem) {
        guard let root = browseRoot, Self.isInside(item.url, root.url) else { return }
        let url = item.url
        let permanently = root.deletesPermanently

        Task { [weak self] in
            let error = await Task.detached(priority: .userInitiated) {
                Self.removeItem(at: url, permanently: permanently)
            }.value
            guard let self else { return }
            if let error {
                message = String(localized: "Couldn't remove \(item.name): \(error)")
                return
            }
            items.removeAll { $0.id == item.id }
            didFree(item.size.bytes ?? 0, from: root, permanently: permanently)
            message = permanently
                ? String(localized: "Deleted \(item.name)")
                : String(localized: "Moved \(item.name) to the Trash. Empty the Trash to free the space.")
        }
    }

    /// Deletes everything in a cache location for good. Items still in use
    /// by a running app may be skipped.
    func clearAll() {
        guard let root = browseRoot, root.kind == .clearable, browsePath.count == 1 else { return }
        let targets = items.map(\.url).filter { Self.isInside($0, root.url) }
        let bytes = currentFolderSize

        Task { [weak self] in
            let failures = await Task.detached(priority: .userInitiated) {
                targets.filter { Self.removeItem(at: $0, permanently: true) != nil }.count
            }.value
            guard let self else { return }
            didFree(bytes, from: root, permanently: true)
            message = failures == 0
                ? String(localized: "Cleared \(bytes.formatted(.byteCount(style: .file)))")
                : String(localized: "Cleared, but \(failures) items are in use and were skipped.")
            listCurrentFolder()
        }
    }

    /// Empties the Trash through Finder, which can do it without Full Disk Access.
    func emptyTrash() {
        Task { [weak self] in
            let result = await AppleScriptRunner.shared.run(
                #"tell application "Finder" to empty trash"#, cache: false
            ) { _ in () }
            guard let self else { return }
            switch result {
            case .success:
                if let trash = locations.first(where: { $0.kind == .trash }) {
                    sizes[trash.id] = .measured(0)
                }
                if browseRoot?.kind == .trash { items = [] }
                refreshVolume()
                message = String(localized: "Trash emptied")
            case .failure(.notAuthorized):
                message = String(localized: "Allow NotchIsland to control Finder in Privacy & Security › Automation.")
            case .failure:
                message = String(localized: "Couldn't empty the Trash.")
            }
        }
    }

    private func didFree(_ bytes: Int64, from root: StorageLocation, permanently: Bool) {
        if let size = sizes[root.id]?.bytes {
            sizes[root.id] = .measured(max(0, size - bytes))
        }
        // Moving to the Trash frees nothing yet; the Trash just grows.
        if !permanently, let trash = locations.first(where: { $0.kind == .trash }),
           let size = sizes[trash.id]?.bytes {
            sizes[trash.id] = .measured(size + bytes)
        }
        refreshVolume()
    }

    /// Strictly below `folder`: never the folder itself, never a sibling
    /// that merely shares its name as a prefix.
    nonisolated static func isInside(_ url: URL, _ folder: URL) -> Bool {
        let folderPath = folder.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path.hasPrefix(folderPath + "/") && path != folderPath
    }

    /// Nil on success, otherwise the reason it failed.
    nonisolated private static func removeItem(at url: URL, permanently: Bool) -> String? {
        do {
            if permanently {
                try FileManager.default.removeItem(at: url)
            } else {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Measures `targets` a few at a time off the main thread, reporting each
    /// result on the main actor as it arrives.
    private static func measure(
        _ targets: [(id: String, url: URL)],
        onResult: @escaping (String, Int64?) -> Void
    ) async {
        await withTaskGroup(of: (String, Int64?).self) { group in
            var pending = targets[...]
            func addNext() {
                guard let (id, url) = pending.popFirst() else { return }
                group.addTask {
                    let size = await Task.detached(priority: .utility) {
                        FolderSizer.allocatedSize(of: url)
                    }.value
                    return (id, size)
                }
            }
            for _ in 0..<maxConcurrentMeasurements { addNext() }
            for await (id, size) in group {
                if Task.isCancelled { group.cancelAll(); return }
                onResult(id, size)
                addNext()
            }
        }
    }
}

/// Walks a folder and adds up the disk space its files take.
nonisolated enum FolderSizer {
    private static let keys: [URLResourceKey] = [
        .isRegularFileKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
    ]

    /// Size of a file, or of everything inside a folder. Nil when the folder
    /// itself can't be listed; unreadable subfolders are skipped, so the total
    /// can be a little low.
    static func allocatedSize(of url: URL) -> Int64? {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        if !isDirectory.boolValue {
            let values = try? url.resourceValues(forKeys: Set(keys))
            return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }

        guard (try? manager.contentsOfDirectory(atPath: url.path)) != nil,
              let enumerator = manager.enumerator(
                  at: url,
                  includingPropertiesForKeys: keys,
                  options: [],
                  errorHandler: { _, _ in true }
              )
        else { return nil }

        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true
            else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// The visible items directly inside a folder, unsized. Nil when the
    /// folder can't be listed.
    static func children(of folder: URL) -> [StorageItem]? {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .localizedNameKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return nil }

        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isFolder = values?.isDirectory == true && values?.isPackage != true
            return StorageItem(url: url, name: values?.localizedName ?? url.lastPathComponent, isFolder: isFolder)
        }
    }
}
