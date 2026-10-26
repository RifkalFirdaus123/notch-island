import AppKit
import Combine

struct ProjectItem: Identifiable, Equatable {
    let url: URL
    /// A `.code-workspace` file rather than a plain folder.
    let isWorkspace: Bool

    var id: String { url.path }
    var name: String { isWorkspace ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent }
}

/// Lists the folders and workspaces in the projects folder and opens them in
/// Antigravity.
final class ProjectsService: ObservableObject {
    @Published private(set) var items: [ProjectItem] = []
    @Published private(set) var errorMessage: String?

    static let editorBundleIdentifier = "com.google.antigravity-ide"

    static var defaultFolder: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/hotama", isDirectory: true).path
    }

    var folder: URL {
        let stored = UserDefaults.standard.string(forKey: SettingsKeys.projectsFolder) ?? ""
        let path = stored.isEmpty ? Self.defaultFolder : (stored as NSString).expandingTildeInPath
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Re-reads the folder; cheap enough to run every time the tab appears.
    func refresh() {
        let folder = folder
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            )
        } catch {
            items = []
            errorMessage = String(localized: "Can't read \(folder.path)")
            return
        }
        errorMessage = nil
        items = contents.compactMap { url -> ProjectItem? in
            if url.pathExtension == "code-workspace" { return ProjectItem(url: url, isWorkspace: true) }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isDirectory ? ProjectItem(url: url, isWorkspace: false) : nil
        }
        // Workspaces first, then folders, each alphabetically.
        .sorted { lhs, rhs in
            if lhs.isWorkspace != rhs.isWorkspace { return lhs.isWorkspace }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var editorURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.editorBundleIdentifier)
    }

    func open(_ item: ProjectItem) {
        guard let editorURL else {
            errorMessage = String(localized: "Antigravity is not installed.")
            return
        }
        NSWorkspace.shared.open(
            [item.url], withApplicationAt: editorURL, configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if let error { NSLog("NotchIsland: failed to open \(item.url.path): \(error)") }
        }
    }

    func revealInFinder(_ item: ProjectItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func openFolderInFinder() {
        NSWorkspace.shared.open(folder)
    }
}
