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

/// A named projects folder. Stored one per line in `SettingsKeys.projectsFolder`
/// as "name<TAB>path"; a bare path (saved by an older version) is also accepted.
struct ProjectFolder: Identifiable, Equatable {
    let name: String
    let path: String

    var id: String { path }
    var url: URL { URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true) }

    static func decode(_ stored: String) -> [ProjectFolder] {
        let folders = stored.split(whereSeparator: \.isNewline).compactMap { line -> ProjectFolder? in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard let path = parts.last, !path.isEmpty else { return nil }
            let name = parts.count == 2 ? parts[0] : (path as NSString).lastPathComponent
            return ProjectFolder(name: name, path: path)
        }
        return folders.isEmpty ? [defaultFolder] : folders
    }

    static func encode(_ folders: [ProjectFolder]) -> String {
        folders.map { "\($0.name)\t\($0.path)" }.joined(separator: "\n")
    }

    static var defaultFolder: ProjectFolder {
        ProjectFolder(name: (ProjectsService.defaultFolder as NSString).lastPathComponent, path: ProjectsService.defaultFolder)
    }
}

struct ProjectItem: Identifiable, Equatable {
    let url: URL
    /// A `.code-workspace` file rather than a plain folder.
    let isWorkspace: Bool

    var id: String { url.path }
    var name: String { isWorkspace ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent }
}

/// Lists the folders and workspaces in the chosen projects folder (one of several) and opens them in
/// the selected editor (VS Code, Antigravity, or Finder).
final class ProjectsService: ObservableObject {
    @Published private(set) var items: [ProjectItem] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var folders: [ProjectFolder] = []
    @Published private(set) var selectedFolder: ProjectFolder?

    var selectedEditor: ProjectEditor {
        let stored = UserDefaults.standard.string(forKey: SettingsKeys.projectsEditor) ?? ""
        return ProjectEditor(rawValue: stored) ?? .antigravity
    }

    static var defaultFolder: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/hotama", isDirectory: true).path
    }

    private static func configuredFolders() -> [ProjectFolder] {
        let stored = UserDefaults.standard.string(forKey: SettingsKeys.projectsFolder) ?? ""
        return ProjectFolder.decode(stored)
    }

    /// The folder whose contents are listed.
    var folder: URL { selectedFolder?.url ?? Self.configuredFolders()[0].url }

    func select(_ folder: ProjectFolder) {
        selectedFolder = folder
        refresh()
    }

    /// Re-reads the folders; cheap enough to run every time the tab appears.
    func refresh() {
        folders = Self.configuredFolders()
        if selectedFolder.map({ !folders.contains($0) }) ?? true { selectedFolder = folders[0] }
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

    /// Asks for a required name, then creates that folder inside the selected
    /// projects folder. Uses a modal alert since the island panel can't take text input.
    func promptNewProject() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = String(localized: "Project name")
        let alert = NSAlert()
        alert.messageText = String(localized: "New Project Folder")
        alert.informativeText = String(localized: "Created in \(folder.path)")
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Create"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let create = alert.buttons[0]
        create.isEnabled = false
        let observer = NotificationCenter.default.addObserver(
            forName: NSControl.textDidChangeNotification, object: field, queue: .main
        ) { _ in
            create.isEnabled = !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), !name.contains(":"), !name.hasPrefix(".") else {
            errorMessage = String(localized: "Invalid project name.")
            return
        }
        let url = folder.appendingPathComponent(name, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            refresh()
            open(ProjectItem(url: url, isWorkspace: false))
        } catch {
            errorMessage = String(localized: "Can't create \(name): \(error.localizedDescription)")
        }
    }

    func revealInFinder(_ item: ProjectItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func openFolderInFinder() {
        NSWorkspace.shared.open(folder)
    }
}
