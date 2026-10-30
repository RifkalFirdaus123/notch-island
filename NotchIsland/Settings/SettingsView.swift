import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var nowPlaying: NowPlayingService
    let shelfDirectory: URL

    @AppStorage(SettingsKeys.showInFullscreen) private var showInFullscreen = false
    @AppStorage(SettingsKeys.featureCamera) private var cameraEnabled = true
    @AppStorage(SettingsKeys.featureShelf) private var shelfEnabled = true
    @AppStorage(SettingsKeys.featureProjects) private var projectsEnabled = true
    @AppStorage(SettingsKeys.projectsFolder) private var projectsFolder = ""
    @AppStorage(SettingsKeys.featureStorage) private var storageEnabled = true
    @AppStorage(SettingsKeys.featureLyrics) private var lyricsEnabled = true
    @AppStorage(SettingsKeys.lyricStripHeight) private var lyricStripHeight = SettingsKeys.defaultLyricStripHeight
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

            Section("Features") {
                Toggle("Camera tab", isOn: $cameraEnabled)
                Toggle("File Shelf tab", isOn: $shelfEnabled)
                Toggle("Projects tab", isOn: $projectsEnabled)
                Toggle("Storage tab", isOn: $storageEnabled)
                Toggle("Lyrics under the notch", isOn: $lyricsEnabled)
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
                ForEach(issueMessages, id: \.self) { message in
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Music Sources")
            } footer: {
                Text("YouTube needs View › Developer › Allow JavaScript from Apple Events turned on in the browser.")
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
                Text("Folders and .code-workspace files here open in Antigravity.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Lyrics come from LRCLIB; only the song title, artist, album and length are sent. The camera picture is never recorded or stored.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
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
