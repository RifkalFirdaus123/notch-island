import AppKit
import SwiftUI

/// Startup disk usage and the folders taking the most space. Click a folder
/// to see what's inside, largest first, and remove what isn't needed.
struct StorageTabView: View {
    @ObservedObject var storage: StorageService

    var body: some View {
        Group {
            if let root = storage.browseRoot {
                StorageBrowserView(storage: storage, root: root)
            } else {
                StorageOverviewView(storage: storage)
            }
        }
        .onAppear { storage.refreshVolume() }
    }
}

// MARK: - Overview

private struct StorageOverviewView: View {
    @ObservedObject var storage: StorageService

    private let columns = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                if let volume = storage.volume {
                    VolumeSummary(volume: volume)
                } else {
                    Text("Can't read the startup disk.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                }
                ScanButton(storage: storage)
                Menu {
                    Button("Open Storage Settings") { storage.openStorageSettings() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(storage.locations) { location in
                        LocationRow(
                            location: location,
                            size: storage.sizes[location.id] ?? .unknown,
                            action: { storage.browse(location) }
                        )
                        .contextMenu {
                            Button("Show in Finder") { storage.reveal(location.url) }
                        }
                    }
                }
            }
        }
    }
}

private struct VolumeSummary: View {
    let volume: StorageVolume

    private var tint: Color {
        if volume.usedFraction >= 0.95 { return .red }
        if volume.usedFraction >= 0.85 { return .orange }
        return .white
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("\(volume.used.formatted(.byteCount(style: .file))) of \(volume.total.formatted(.byteCount(style: .file))) used")
                    .foregroundStyle(tint)
                Spacer(minLength: 4)
                Text("\(volume.available.formatted(.byteCount(style: .file))) available")
                    .foregroundStyle(tint == .white ? .white.opacity(0.5) : tint)
            }
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)

            UsageBar(volume: volume, tint: tint)
                .frame(height: 6)
                .help(Text("\(volume.purgeable.formatted(.byteCount(style: .file))) purgeable"))
        }
    }
}

/// Used space, then purgeable space in a lighter shade, then free.
private struct UsageBar: View {
    let volume: StorageVolume
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let total = Double(max(volume.total, 1))
            let usedWidth = proxy.size.width * Double(volume.used) / total
            let purgeableWidth = proxy.size.width * Double(volume.purgeable) / total
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                HStack(spacing: 0) {
                    Rectangle().fill(tint.opacity(0.9)).frame(width: usedWidth)
                    Rectangle().fill(.white.opacity(0.3)).frame(width: purgeableWidth)
                }
                .clipShape(Capsule())
            }
        }
        .animation(.default, value: volume)
    }
}

private struct ScanButton: View {
    @ObservedObject var storage: StorageService

    var body: some View {
        Button { storage.scan() } label: {
            HStack(spacing: 4) {
                if storage.isScanning {
                    ProgressView().controlSize(.mini)
                    Text("Scanning…")
                } else {
                    Image(systemName: "arrow.clockwise")
                    Text("Scan")
                }
            }
            .pillStyle()
        }
        .buttonStyle(.plain)
        .disabled(storage.isScanning)
        .help(storage.lastScan.map {
            Text("Scanned \($0.formatted(.relative(presentation: .named)))")
        } ?? Text("Measure the folders below"))
    }
}

private struct LocationRow: View {
    let location: StorageLocation
    let size: FolderSize
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: location.symbol)
                    .font(.system(size: 10))
                    .foregroundStyle(location.kind == .clearable ? Color.accentColor : .white.opacity(0.7))
                    .frame(width: 14)
                Text(verbatim: location.name)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Spacer(minLength: 4)
                SizeLabel(size: size)
            }
            .rowStyle(isHovering: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(helpText)
    }

    private var helpText: Text {
        let path = Text(verbatim: location.url.path)
        if size == .noAccess {
            return path + Text(verbatim: "\n") + Text("No access. Allow it in Privacy & Security › Full Disk Access.")
        }
        if location.kind == .clearable {
            return path + Text(verbatim: "\n") + Text("Safe to clear: rebuilt automatically when needed.")
        }
        return path
    }
}

// MARK: - Browser

private struct StorageBrowserView: View {
    @ObservedObject var storage: StorageService
    let root: StorageLocation

    private var isAtRoot: Bool { storage.browsePath.count == 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button(action: storage.goBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.white.opacity(0.12)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(Text("Back"))

                Text(verbatim: title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if storage.isListing {
                    ProgressView().controlSize(.mini)
                } else {
                    Text(verbatim: storage.currentFolderSize.formatted(.byteCount(style: .file)))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 4)

                if root.kind == .trash, !storage.items.isEmpty {
                    ConfirmButton(title: "Empty Trash", confirmTitle: "Empty?", action: storage.emptyTrash)
                } else if root.kind == .clearable, isAtRoot, !storage.items.isEmpty, !storage.isListing {
                    ConfirmButton(title: "Clear All", confirmTitle: "Delete all?", action: storage.clearAll)
                        .help(Text("Safe to clear: rebuilt automatically when needed."))
                }
                if let folder = storage.currentFolder {
                    Button { storage.reveal(folder) } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(Text("Show in Finder"))
                }
            }
            .foregroundStyle(.white)

            if let message = storage.message {
                Text(verbatim: message)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(5))
                        if storage.message == message { storage.dismissMessage() }
                    }
            }

            if storage.items.isEmpty && !storage.isListing {
                Text("This folder is empty.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 3) {
                        ForEach(storage.items) { item in
                            ItemRow(item: item, deletesPermanently: root.deletesPermanently, storage: storage)
                        }
                    }
                }
            }
        }
    }

    private var title: String {
        isAtRoot ? root.name : (storage.currentFolder?.lastPathComponent ?? root.name)
    }
}

private struct ItemRow: View {
    let item: StorageItem
    let deletesPermanently: Bool
    @ObservedObject var storage: StorageService
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button { storage.open(item) } label: {
                HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(verbatim: item.name)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if item.isFolder {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    Spacer(minLength: 4)
                    SizeLabel(size: item.size)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text(verbatim: item.url.path))

            ConfirmButton(
                symbol: deletesPermanently ? "xmark.bin" : "trash",
                confirmTitle: deletesPermanently ? "Delete?" : "To Trash?",
                action: { storage.remove(item) }
            )
            .help(deletesPermanently ? Text("Delete permanently") : Text("Move to Trash"))
            .opacity(isHovering ? 1 : 0.35)
        }
        .rowStyle(isHovering: isHovering)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Show in Finder") { storage.reveal(item.url) }
            Button(deletesPermanently ? "Delete permanently" : "Move to Trash", role: .destructive) {
                storage.remove(item)
            }
        }
    }
}

/// A destructive button that needs a second click within a few seconds.
private struct ConfirmButton: View {
    var title: LocalizedStringKey?
    var symbol: String?
    let confirmTitle: LocalizedStringKey
    let action: () -> Void
    @State private var isArmed = false

    var body: some View {
        Button {
            if isArmed {
                isArmed = false
                action()
            } else {
                isArmed = true
            }
        } label: {
            Group {
                if isArmed {
                    Text(confirmTitle)
                } else if let symbol {
                    Image(systemName: symbol)
                } else if let title {
                    Text(title)
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isArmed ? .white : .white.opacity(0.85))
            .padding(.horizontal, isArmed || title != nil ? 8 : 4)
            .frame(height: 20)
            .background(Capsule().fill(isArmed ? Color.red : .white.opacity(title != nil ? 0.12 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isArmed)
        .task(id: isArmed) {
            guard isArmed else { return }
            try? await Task.sleep(for: .seconds(3))
            isArmed = false
        }
    }
}

// MARK: - Shared pieces

private struct SizeLabel: View {
    let size: FolderSize

    var body: some View {
        switch size {
        case .unknown:
            Text(verbatim: "–").foregroundStyle(.white.opacity(0.4))
        case .measuring:
            ProgressView().controlSize(.mini)
        case .measured(let bytes):
            Text(verbatim: bytes.formatted(.byteCount(style: .file)))
                .monospacedDigit()
                .foregroundStyle(bytes >= 10_000_000_000 ? .orange : .white.opacity(0.75))
        case .noAccess:
            Image(systemName: "lock.fill")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

private extension View {
    func rowStyle(isHovering: Bool) -> some View {
        font(.system(size: 11))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.white.opacity(isHovering ? 0.16 : 0.06))
            )
            .contentShape(Rectangle())
    }

    func pillStyle() -> some View {
        font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(.white.opacity(0.12)))
            .contentShape(Capsule())
    }
}
