import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var kanban: KanbanService
    let shelfDirectory: URL

    @AppStorage(SettingsKeys.showInFullscreen) private var showInFullscreen = false
    @AppStorage(SettingsKeys.featureCamera) private var cameraEnabled = true
    @AppStorage(SettingsKeys.featureShelf) private var shelfEnabled = true
    @AppStorage(SettingsKeys.featureProjects) private var projectsEnabled = true
    @AppStorage(SettingsKeys.projectsFolder) private var projectsFolder = ""
    @AppStorage(SettingsKeys.featureStorage) private var storageEnabled = true
    @AppStorage(SettingsKeys.featureKanban) private var kanbanEnabled = true
    @AppStorage(SettingsKeys.projectsEditor) private var projectsEditor = ProjectEditor.antigravity.rawValue
    @AppStorage(SettingsKeys.featureLyrics) private var lyricsEnabled = true
    @AppStorage(SettingsKeys.lyricMoodStyle) private var lyricMoodStyle = false
    @AppStorage(SettingsKeys.featureBuddy) private var buddyEnabled = true
    @AppStorage(SettingsKeys.featureBuddyPeek) private var buddyPeekEnabled = true
    @AppStorage(SettingsKeys.featureMic) private var micEnabled = true
    @AppStorage(SettingsKeys.lyricStripHeight) private var lyricStripHeight = SettingsKeys.defaultLyricStripHeight
    @AppStorage(SettingsKeys.idleExtraWidth) private var idleExtraWidth = 0.0
    @AppStorage(SettingsKeys.idleExtraHeight) private var idleExtraHeight = 0.0
    @AppStorage(SettingsKeys.autoSkipAds) private var autoSkipAds = true
    @AppStorage(SettingsKeys.musicSpotify) private var spotifyEnabled = true
    @AppStorage(SettingsKeys.musicAppleMusic) private var appleMusicEnabled = true
    @AppStorage(SettingsKeys.musicBrowser) private var browserEnabled = true
    @AppStorage(SettingsKeys.shelfCopiesFiles) private var shelfCopiesFiles = false
    @AppStorage(SettingsKeys.featureDev) private var devEnabled = true
    @AppStorage(SettingsKeys.devAlerts) private var devAlerts = true
    @AppStorage(SettingsKeys.clipboardHistory) private var clipboardHistory = true

    @State private var launchAtLogin = LaunchAtLogin.isEnabled || LaunchAtLogin.needsApproval
    @State private var launchAtLoginNeedsApproval = LaunchAtLogin.needsApproval
    @State private var launchAtLoginError: String?
    @State private var showAddFolder = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        // Also fires when we sync the toggle to the real status.
                        let current = LaunchAtLogin.isEnabled || LaunchAtLogin.needsApproval
                        if enabled != current { setLaunchAtLogin(enabled) }
                    }
                if launchAtLoginNeedsApproval {
                    HStack {
                        Text("Allow NotchIsland in Login Items to finish.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { LaunchAtLogin.openLoginItemsSettings() }
                    }
                    .font(.callout)
                }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                Toggle("Show over fullscreen apps", isOn: $showInFullscreen)
            }

            Section {
                SizeSlider(title: "Extra width", value: $idleExtraWidth, range: 0...160, step: 2)
                SizeSlider(title: "Extra height", value: $idleExtraHeight, range: 0...20, step: 1)
                if idleExtraWidth > 0 || idleExtraHeight > 0 {
                    Button("Reset to Notch Size") {
                        idleExtraWidth = 0
                        idleExtraHeight = 0
                    }
                }
            } header: {
                Text("Idle Notch")
            } footer: {
                Text("How much bigger than the physical notch the island is when idle.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Features") {
                Toggle("Camera tab", isOn: $cameraEnabled)
                Toggle("File Shelf tab", isOn: $shelfEnabled)
                Toggle("Projects tab", isOn: $projectsEnabled)
                Toggle("Storage tab", isOn: $storageEnabled)
                Toggle("Dev tab", isOn: $devEnabled)
                Toggle("Tasks tab (Resam Kanban)", isOn: $kanbanEnabled)
                Toggle("Robot buddy (Home tab and beside the notch)", isOn: $buddyEnabled)
                Toggle(isOn: $buddyPeekEnabled) {
                    Text("Robot plays around the notch while idle")
                    Text("With nothing playing, it walks along the notch's edge doing random things. Click it to see how it reacts.")
                }
                .disabled(!buddyEnabled)
                Toggle("Mic mute button while a call or meeting uses the microphone", isOn: $micEnabled)
                Toggle("Lyrics under the notch", isOn: $lyricsEnabled)
                Toggle(isOn: $lyricMoodStyle) {
                    Text("Mood colors for lyrics and robot eyes")
                    Text("Blue for calm songs, red for hard ones, yellow for upbeat ones. Change it per song from the mood icon in the Home tab.")
                }
                .disabled(!lyricsEnabled && !buddyEnabled)
                LabeledContent("Lyric strip height") {
                    HStack {
                        Slider(value: $lyricStripHeight, in: 18...40, step: 1)
                            .frame(width: 160)
                        Text(verbatim: "\(Int(lyricStripHeight)) pt")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                .disabled(!lyricsEnabled)
            }

            Section {
                Toggle("Spotify", isOn: $spotifyEnabled)
                Toggle("Apple Music", isOn: $appleMusicEnabled)
                Toggle("YouTube in Chrome, Arc, Brave or Edge", isOn: $browserEnabled)
                Toggle("Skip YouTube ads automatically", isOn: $autoSkipAds)
                    .disabled(!browserEnabled)
                ForEach(issueMessages, id: \.self) { message in
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Music Sources")
            } footer: {
                Text("YouTube needs View › Developer › Allow JavaScript from Apple Events turned on in the browser. Auto-skip only presses YouTube's own Skip button once it appears.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("File Shelf") {
                Toggle("Keep copies of dropped files", isOn: $shelfCopiesFiles)
                Button("Show Shelf Folder in Finder") {
                    try? FileManager.default.createDirectory(at: shelfDirectory, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([shelfDirectory])
                }
            }

            ConversionSettingsSection()

            Section {
                Picker("Open With", selection: $projectsEditor) {
                    ForEach(ProjectEditor.allCases) { editor in
                        Text(editor.displayName).tag(editor.rawValue)
                    }
                }
                ForEach(projectFolders) { folder in
                    LabeledContent {
                        HStack {
                            Text(verbatim: folder.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                            if projectFolders.count > 1 {
                                Button { removeProjectsFolder(folder) } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    } label: {
                        Text(verbatim: folder.name)
                    }
                }
                Button("Add Folder…") { showAddFolder = true }
            } header: {
                Text("Projects")
            } footer: {
                Text("Add several folders to switch between them in the Projects tab. Folders and .code-workspace files open in the selected app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            DevToolsSettingsSection(
                devEnabled: devEnabled,
                devAlerts: $devAlerts,
                clipboardHistory: $clipboardHistory
            )
            KanbanSettingsSection(kanban: kanban)

            Section {
                Text("Lyrics come from LRCLIB; only the song title, artist, album and length are sent. With mood colors on, the title and artist are also sent to the iTunes Search API to look up the genre. The camera picture is never recorded or stored.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 12) {
                    if let icon = NSApp.applicationIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 32, height: 32)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NotchIsland")
                            .font(.headline)
                        Text("Version \(appVersion) (\(appBuild))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let url = URL(string: "https://github.com/RifkalFirdaus123/notch-island") {
                        Link("GitHub", destination: url)
                            .font(.callout)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
        // Fixed height; the grouped form scrolls when its content is taller.
        .frame(width: 480, height: 560)
        .sheet(isPresented: $showAddFolder) {
            AddProjectFolderSheet(existing: projectFolders) { folder in
                let current = ProjectFolder.decode(projectsFolder)
                // The implicit default folder is only kept if it was explicitly stored.
                let stored = projectsFolder.isEmpty ? [] : current
                projectsFolder = ProjectFolder.encode(stored + [folder])
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var issueMessages: [String] {
        nowPlaying.issues.sorted { $0.key < $1.key }.map { name, issue in
            switch issue {
            case .notAuthorized:
                String(localized: "NotchIsland isn't allowed to control \(name). Turn it on in System Settings › Privacy & Security › Automation.")
            case .javascriptDisabled:
                String(localized: "In \(name), turn on View › Developer › Allow JavaScript from Apple Events.")
            }
        }
    }

    private var projectFolders: [ProjectFolder] { ProjectFolder.decode(projectsFolder) }

    private func removeProjectsFolder(_ folder: ProjectFolder) {
        projectsFolder = ProjectFolder.encode(projectFolders.filter { $0 != folder })
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLogin = LaunchAtLogin.isEnabled || LaunchAtLogin.needsApproval
        launchAtLoginNeedsApproval = LaunchAtLogin.needsApproval
    }
}

/// Dev tab options and the terminal / AI agent hook setup.
private struct DevToolsSettingsSection: View {
    let devEnabled: Bool
    @Binding var devAlerts: Bool
    @Binding var clipboardHistory: Bool

    @State private var isInstalled = DevHooks.isInstalled
    @State private var installError: String?
    @State private var copiedSnippet: String?

    var body: some View {
        Section {
            Toggle("Show terminal and agent alerts on the island", isOn: $devAlerts)
            Toggle(isOn: $clipboardHistory) {
                Text("Clipboard history")
                Text("The last 25 copied texts, kept in memory only. Passwords from password managers are skipped.")
            }
            LabeledContent("Command-line helper") {
                HStack {
                    if isInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Button(isInstalled ? "Reinstall" : "Install") { install() }
                    if isInstalled {
                        Button("Test") { sendTest() }
                    }
                }
            }
            if let installError {
                Text(installError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            SnippetRow(title: "Terminal (~/.zshrc)", snippet: DevHooks.zshSnippet, copied: $copiedSnippet)
            SnippetRow(title: "Claude Code (~/.claude/settings.json)", snippet: DevHooks.claudeSnippet, copied: $copiedSnippet)
            SnippetRow(title: "Codex (~/.codex/config.toml)", snippet: DevHooks.codexSnippet, copied: $copiedSnippet)
        } header: {
            Text("Dev Tools")
        } footer: {
            Text("Install the helper, then paste each line into the file named. Terminal commands that run 10 seconds or longer show up when they finish; Claude Code and Codex show up when they finish a turn or need you.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .disabled(!devEnabled)
    }

    private func install() {
        do {
            try DevHooks.install()
            installError = nil
        } catch {
            installError = String(localized: "Couldn't install the helper: \(error.localizedDescription)")
        }
        isInstalled = DevHooks.isInstalled
    }

    private func sendTest() {
        let process = Process()
        process.executableURL = DevHooks.notifyScript
        process.arguments = ["-s", "ok", "-t", "terminal", "notchisland-notify", String(localized: "It works")]
        try? process.run()
    }
}

private struct SnippetRow: View {
    let title: LocalizedStringKey
    let snippet: String
    @Binding var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Button(copied == snippet ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(snippet, forType: .string)
                    copied = snippet
                }
            }
            Text(verbatim: snippet)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(6)
        }
    }
}

/// A labeled slider with its value in points.
private struct SizeSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: step)
                    .frame(width: 160)
                Text(verbatim: "+\(Int(value)) pt")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }
}

/// Plain AppKit window: SwiftUI's Settings scene can't be opened reliably
/// from a menu bar app.
final class SettingsWindowController {
    private var window: NSWindow?
    private let makeView: () -> SettingsView

    init(makeView: @escaping () -> SettingsView) {
        self.makeView = makeView
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: makeView())
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "NotchIsland Settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // The app is an accessory with no windows, so the cooperative
        // `activate()` can lose to the frontmost app and leave the window
        // behind it until a second try. Force it forward.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

/// Asks for a folder and a required name before adding it to the Projects tab.
private struct AddProjectFolderSheet: View {
    let existing: [ProjectFolder]
    let onAdd: (ProjectFolder) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var path: String?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var duplicateMessage: String? {
        if existing.contains(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
            return String(localized: "A folder with this name already exists.")
        }
        if let path, existing.contains(where: { $0.path == path }) {
            return String(localized: "This folder is already added.")
        }
        return nil
    }

    private var canAdd: Bool {
        !trimmedName.isEmpty && path != nil && duplicateMessage == nil
    }

    var body: some View {
        Form {
            Section("Add Folder") {
                TextField("Name", text: $name, prompt: Text("Required"))
                LabeledContent("Folder") {
                    HStack {
                        Text(verbatim: path ?? String(localized: "None chosen"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…") { choose() }
                    }
                }
                if let message = duplicateMessage, !trimmedName.isEmpty {
                    Text(message).font(.callout).foregroundStyle(.red)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    guard let path else { return }
                    onAdd(ProjectFolder(name: trimmedName, path: path))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdd)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: existing.last?.path ?? ProjectsService.defaultFolder)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        path = url.path
        // Suggest the folder's own name, still editable.
        if trimmedName.isEmpty { name = url.lastPathComponent }
    }
}

/// Sign in to Resam Kanban for the Tasks tab. Only the token is kept, in the keychain.
private struct KanbanSettingsSection: View {
    @ObservedObject var kanban: KanbanService

    @State private var institutions: [KanbanInstitution] = []
    @State private var institutionID: Int?
    @State private var username = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        Section {
            if kanban.isSignedIn {
                LabeledContent("Signed in as") {
                    HStack {
                        Text(verbatim: kanban.userName).foregroundStyle(.secondary)
                        Button("Sign Out") { kanban.signOut() }
                    }
                }
            } else {
                Picker("Institution", selection: $institutionID) {
                    Text("Choose…").tag(Int?.none)
                    ForEach(institutions) { institution in
                        Text(verbatim: institution.name).tag(Int?.some(institution.id))
                    }
                }
                TextField("Username", text: $username)
                    .textContentType(.username)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .onSubmit(signIn)
                HStack {
                    if let error {
                        Text(error).font(.callout).foregroundStyle(.red)
                    }
                    Spacer()
                    if isWorking { ProgressView().controlSize(.small) }
                    Button("Sign In", action: signIn)
                        .disabled(!canSignIn)
                }
            }
        } header: {
            Text("Resam Kanban")
        } footer: {
            Text("The Tasks tab lists your unfinished cards from kanban.resam.id. Your password isn't stored; the sign-in token is kept in the keychain.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .task(id: kanban.isSignedIn) { await loadInstitutions() }
    }

    private var canSignIn: Bool {
        !isWorking && institutionID != nil
            && !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    private func loadInstitutions() async {
        guard !kanban.isSignedIn, institutions.isEmpty else { return }
        do {
            institutions = try await kanban.institutions().sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            let saved = UserDefaults.standard.integer(forKey: SettingsKeys.kanbanInstitutionID)
            if institutionID == nil, institutions.contains(where: { $0.id == saved }) { institutionID = saved }
        } catch {
            self.error = String(localized: "Can't load institutions: \(error.localizedDescription)")
        }
    }

    private func signIn() {
        guard canSignIn, let institutionID else { return }
        isWorking = true
        error = nil
        Task {
            do {
                try await kanban.signIn(
                    username: username.trimmingCharacters(in: .whitespaces),
                    password: password,
                    institutionID: institutionID
                )
                password = ""
            } catch {
                self.error = error.localizedDescription
            }
            isWorking = false
        }
    }
}

/// Status of the outside engines used for file conversion, and the
/// optional PDF engine's install button.
private struct ConversionSettingsSection: View {
    @State private var isWordInstalled = ConversionEngines.isWordInstalled
    @State private var isEngineInstalled = ConversionEngines.isPDFEngineInstalled
    @State private var isInstalling = false
    @State private var installError: String?

    var body: some View {
        Section {
            LabeledContent("Microsoft Word") {
                Text(isWordInstalled ? "Installed" : "Not installed")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("PDF engine") {
                HStack {
                    if isInstalling {
                        ProgressView().controlSize(.small)
                        Text("Installing…").foregroundStyle(.secondary)
                    } else if isEngineInstalled {
                        Text("Installed").foregroundStyle(.secondary)
                        Button("Remove", role: .destructive) {
                            ConversionEngines.removePDFEngine()
                            isEngineInstalled = ConversionEngines.isPDFEngineInstalled
                        }
                    } else {
                        Button("Install (about 450 MB)") { install() }
                    }
                }
            }
            if let installError {
                Label(installError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("File Conversion")
        } footer: {
            Text("Word documents are turned into PDF by Microsoft Word when it's installed, so the layout matches. The PDF engine (pdf2docx and pdfplumber, downloaded from PyPI into NotchIsland's folder) keeps the layout when converting PDF to Word and finds tables when converting PDF to Excel or CSV. It needs Python 3.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            isWordInstalled = ConversionEngines.isWordInstalled
            isEngineInstalled = ConversionEngines.isPDFEngineInstalled
        }
    }

    private func install() {
        isInstalling = true
        installError = nil
        Task {
            let error = await Task.detached(priority: .userInitiated) { () -> String? in
                do {
                    try ConversionEngines.installPDFEngine()
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            installError = error
            isEngineInstalled = ConversionEngines.isPDFEngineInstalled
            isInstalling = false
        }
    }
}
