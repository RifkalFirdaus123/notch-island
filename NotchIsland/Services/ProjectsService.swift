import AppKit
import Combine

enum ProjectEditor: String, CaseIterable, Identifiable {
    case vscode = "vscode"
    case antigravity = "antigravity"
    case finder = "finder"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vscode: return "Visual Studio Code"
        case .antigravity: return "Antigravity"
        case .finder: return String(localized: "Finder (Folder)")
        }
    }

    var bundleIdentifier: String? {
        switch self {
        case .vscode: return "com.microsoft.VSCode"
        case .antigravity: return "com.google.antigravity-ide"
        case .finder: return nil
        }
    }
}

struct ProjectItem: Identifiable, Equatable {
    let url: URL
    /// A `.code-workspace` file rather than a plain folder.
    let isWorkspace: Bool

    var id: String { url.path }
    var name: String { isWorkspace ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent }
}

/// Lists the folders and workspaces in the projects folder and opens them in
/// the selected editor (VS Code, Antigravity, or Finder).
final class ProjectsService: ObservableObject {
    @Published private(set) var items: [ProjectItem] = []
    @Published private(set) var errorMessage: String?

    var selectedEditor: ProjectEditor {
        let stored = UserDefaults.standard.string(forKey: SettingsKeys.projectsEditor) ?? ""
        return ProjectEditor(rawValue: stored) ?? .vscode
    }

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

    func editorURL(for editor: ProjectEditor) -> URL? {
        guard let bundleID = editor.bundleIdentifier else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    func open(_ item: ProjectItem, with editor: ProjectEditor? = nil) {
        let target = editor ?? selectedEditor
        switch target {
        case .finder:
            errorMessage = nil
            NSWorkspace.shared.open(item.url)
        case .vscode, .antigravity:
            guard let appURL = editorURL(for: target) else {
                errorMessage = String(localized: "\(target.displayName) is not installed; opened in Finder.")
                NSWorkspace.shared.open(item.url)
                return
            }
            errorMessage = nil
            NSWorkspace.shared.open(
                [item.url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration()
            ) { _, error in
                if let error { NSLog("NotchIsland: failed to open \(item.url.path): \(error)") }
            }
        }
    }

    func revealInFinder(_ item: ProjectItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func openFolderInFinder() {
        NSWorkspace.shared.open(folder)
    }
}
