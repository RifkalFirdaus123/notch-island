import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// Temporary holding area: drop files, images or text in, drag them out later.
struct ShelfTabView: View {
    @ObservedObject var shelf: ShelfService
    @AppStorage(SettingsKeys.shelfCopiesFiles) private var copiesFiles = false
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("^[\(shelf.items.count) item](inflect: true)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                ConversionStatus(shelf: shelf)
                Spacer()
                Menu {
                    Toggle("Keep Copies of Dropped Files", isOn: $copiesFiles)
                    Divider()
                    Button("Clear Shelf", role: .destructive) { shelf.removeAll() }
                        .disabled(shelf.items.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : .white.opacity(0.18),
                        style: StrokeStyle(lineWidth: 1.5, dash: shelf.items.isEmpty ? [5, 4] : [])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.white.opacity(isTargeted ? 0.1 : 0.04))
                    )

                if shelf.items.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 20, weight: .medium))
                        Text("Drop files here")
                            .font(.system(size: 12))
                        Text("Right-click a file to convert it")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .foregroundStyle(.white.opacity(0.55))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 4) {
                            ForEach(shelf.items) { item in
                                ShelfItemView(item: item, shelf: shelf)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
            }
            .onDrop(of: ShelfService.acceptedTypes, isTargeted: $isTargeted) { providers in
                shelf.add(providers)
                return true
            }
            .animation(.easeOut(duration: 0.15), value: isTargeted)
        }
    }
}

private struct ShelfItemView: View {
    let item: ShelfItem
    @ObservedObject var shelf: ShelfService
    @State private var isHovering = false

    private var exists: Bool { item.kind == .text || shelf.fileExists(item) }
    private var isConverting: Bool { shelf.converting.contains(item.id) }

    var body: some View {
        VStack(spacing: 4) {
            icon
                .frame(width: 40, height: 40)
                .opacity(isConverting ? 0.35 : 1)
                .overlay {
                    if isConverting {
                        ProgressView().controlSize(.small)
                    }
                }
            Text(item.name)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: 64)
        }
        .frame(width: 70, height: 84)
        .opacity(exists ? 1 : 0.4)
        .contentShape(Rectangle())
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button { shelf.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .gray)
                }
                .buttonStyle(.plain)
                .help(Text("Remove"))
            }
        }
        .overlay(alignment: .topLeading) {
            if isHovering, exists, !isConverting {
                ConvertMenu(item: item, shelf: shelf) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                }
                .help(Text("Convert"))
            }
        }
        .onHover { isHovering = $0 }
        .onDrag { shelf.itemProvider(for: item) }
        .onTapGesture(count: 2) { shelf.open(item) }
        .contextMenu {
            Button("Open") { shelf.open(item) }
                .disabled(!exists)
            if item.kind == .file {
                Button("Show in Finder") { shelf.revealInFinder(item) }
                    .disabled(!exists)
            }
            Button("Copy") { shelf.copyToPasteboard(item) }
            if exists, !isConverting, !shelf.conversionTargets(for: item).isEmpty {
                ConvertMenu(item: item, shelf: shelf) { Text("Convert To") }
            }
            Divider()
            Button("Remove from Shelf", role: .destructive) { shelf.remove(item) }
        }
        .help(exists ? (item.text ?? item.path ?? item.name) : String(localized: "File not found"))
    }

    @ViewBuilder
    private var icon: some View {
        switch item.kind {
        case .file:
            if let path = item.path, exists {
                FileThumbnailView(path: path)
            } else {
                Image(systemName: "questionmark.folder")
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.6))
            }
        case .text:
            let isLink = item.text.flatMap(URL.init(string:))?.scheme?.hasPrefix("http") == true
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.12))
                .overlay(
                    Image(systemName: isLink ? "link" : "text.alignleft")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                )
        }
    }
}

/// "Convert To" submenu listing the formats an item can become. Renders
/// nothing for items that can't be converted.
private struct ConvertMenu<Label: View>: View {
    let item: ShelfItem
    @ObservedObject var shelf: ShelfService
    @ViewBuilder let label: () -> Label

    var body: some View {
        let targets = shelf.conversionTargets(for: item)
        if !targets.isEmpty {
            Menu {
                ForEach(targets) { format in
                    Button(FileConverter.title(of: format, from: item.url)) { shelf.convert(item, to: format) }
                }
            } label: {
                label()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

/// "Converting…" while a conversion runs, then any error for a few seconds.
private struct ConversionStatus: View {
    @ObservedObject var shelf: ShelfService

    var body: some View {
        Group {
            if let error = shelf.conversionError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(error)
            } else if !shelf.converting.isEmpty {
                Text("Converting…")
                    .foregroundStyle(.white.opacity(0.5))
            } else if let notice = shelf.conversionNotice {
                Label(notice, systemImage: "info.circle.fill")
                    .foregroundStyle(.yellow.opacity(0.9))
                    .help(notice)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
        .truncationMode(.tail)
        .task(id: shelf.conversionError) {
            guard shelf.conversionError != nil else { return }
            try? await Task.sleep(for: .seconds(6))
            shelf.conversionError = nil
        }
        .task(id: shelf.conversionNotice) {
            guard shelf.conversionNotice != nil else { return }
            try? await Task.sleep(for: .seconds(8))
            shelf.conversionNotice = nil
        }
    }
}

/// Quick Look preview of a file's contents (images, PDFs, videos...), with
/// the Finder icon while it loads or when there is no preview.
private struct FileThumbnailView: View {
    let path: String
    @Environment(\.displayScale) private var displayScale
    @State private var thumbnail: NSImage?

    nonisolated private static let size = CGSize(width: 40, height: 40)

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .task(id: path) {
            thumbnail = await Self.loadThumbnail(path: path, scale: displayScale)
        }
    }

    nonisolated private static func loadThumbnail(path: String, scale: CGFloat) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: URL(fileURLWithPath: path),
            size: size,
            scale: scale,
            // Content previews only; the icon fallback is drawn above.
            representationTypes: .thumbnail
        )
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }
}
