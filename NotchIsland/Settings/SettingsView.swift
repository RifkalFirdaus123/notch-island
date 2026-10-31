import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var nowPlaying: NowPlayingService
    let shelfDirectory: URL

    @AppStorage(SettingsKeys.showInFullscreen) private var showInFullscreen = false
    @AppStorage(SettingsKeys.featurePomodoro) private var pomodoroEnabled = true
    @AppStorage(SettingsKeys.featureCamera) private var cameraEnabled = true
    @AppStorage(SettingsKeys.featureShelf) private var shelfEnabled = true
    @AppStorage(SettingsKeys.featureProjects) private var projectsEnabled = true
    @AppStorage(SettingsKeys.pomodoroWorkMinutes) private var pomodoroWorkMinutes = 25
    @AppStorage(SettingsKeys.pomodoroShortBreakMinutes) private var pomodoroShortBreakMinutes = 5
    @AppStorage(SettingsKeys.pomodoroLongBreakMinutes) private var pomodoroLongBreakMinutes = 15
    @AppStorage(SettingsKeys.pomodoroLongBreakInterval) private var pomodoroLongBreakInterval = 4
    @AppStorage(SettingsKeys.projectsFolder) private var projectsFolder = ""
    @AppStorage(SettingsKeys.featureStorage) private var storageEnabled = true
    @AppStorage(SettingsKeys.projectsEditor) private var projectsEditor = ProjectEditor.antigravity.rawValue
    @AppStorage(SettingsKeys.featureLyrics) private var lyricsEnabled = true
    @AppStorage(SettingsKeys.lyricMoodStyle) private var lyricMoodStyle = false
    @AppStorage(SettingsKeys.lyricStripHeight) private var lyricStripHeight = SettingsKeys.defaultLyricStripHeight
    @AppStorage(SettingsKeys.idleExtraWidth) private var idleExtraWidth = 0.0
    @AppStorage(SettingsKeys.idleExtraHeight) private var idleExtraHeight = 0.0
    @AppStorage(SettingsKeys.autoSkipAds) private var autoSkipAds = true
    @AppStorage(SettingsKeys.musicSpotify) private var spotifyEnabled = true
    @AppStorage(SettingsKeys.musicAppleMusic) private var appleMusicEnabled = true
    @AppStorage(SettingsKeys.musicBrowser) private var browserEnabled = true
    @AppStorage(SettingsKeys.shelfCopiesFiles) private var shelfCopiesFiles = false

    @State private var launchAtLogin = LaunchAtLogin.isEnabled || LaunchAtLogin.needsApproval
    @State private var launchAtLoginNeedsApproval = LaunchAtLogin.needsApproval
    @State private var launchAtLoginError: String?

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
                Toggle("Pomodoro tab", isOn: $pomodoroEnabled)
                Toggle("Camera tab", isOn: $cameraEnabled)
                Toggle("File Shelf tab", isOn: $shelfEnabled)
                Toggle("Projects tab", isOn: $projectsEnabled)
                Toggle("Storage tab", isOn: $storageEnabled)
                Toggle("Lyrics under the notch", isOn: $lyricsEnabled)
                Toggle(isOn: $lyricMoodStyle) {
                    Text("Mood colors for lyrics")
                    Text("Blue for calm songs, red for hard ones, yellow for upbeat ones. Change it per song from the mood icon in the Home tab.")
                }
                .disabled(!lyricsEnabled)
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

            Section {
                Stepper(value: $pomodoroWorkMinutes, in: 1...90, step: 1) {
                    HStack {
                        Text("Focus duration")
                        Spacer()
                        Text("\(pomodoroWorkMinutes) min")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Stepper(value: $pomodoroShortBreakMinutes, in: 1...30, step: 1) {
                    HStack {
                        Text("Short break")
                        Spacer()
                        Text("\(pomodoroShortBreakMinutes) min")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Stepper(value: $pomodoroLongBreakMinutes, in: 1...60, step: 1) {
                    HStack {
                        Text("Long break")
                        Spacer()
                        Text("\(pomodoroLongBreakMinutes) min")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Stepper(value: $pomodoroLongBreakInterval, in: 1...10, step: 1) {
                    HStack {
                        Text("Long break interval")
                        Spacer()
                        Text("Every \(pomodoroLongBreakInterval) sessions")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Pomodoro Timer")
            } footer: {
                Text("Customize interval durations and how often long breaks occur.")
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

            Section {
                Picker("Open With", selection: $projectsEditor) {
                    ForEach(ProjectEditor.allCases) { editor in
                        Text(editor.displayName).tag(editor.rawValue)
                    }
                }
                LabeledContent("Folder") {
                    HStack {
                        Text(verbatim: projectsFolder.isEmpty ? ProjectsService.defaultFolder : projectsFolder)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…") { chooseProjectsFolder() }
                    }
                }
            } header: {
                Text("Projects")
            } footer: {
                Text("Folders and .code-workspace files open in the selected app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

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

    private func chooseProjectsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: projectsFolder.isEmpty ? ProjectsService.defaultFolder : projectsFolder)
        if panel.runModal() == .OK, let url = panel.url {
            projectsFolder = url.path
        }
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
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
