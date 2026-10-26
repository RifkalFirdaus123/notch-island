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

    var body: some View {
        VStack(spacing: 4) {
            icon
                .frame(width: 40, height: 40)
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
