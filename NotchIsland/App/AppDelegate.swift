import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NotchWindowController?
    private var settingsController: SettingsWindowController?
    private var statusItem: NSStatusItem?
    private var lyrics: LyricsService?
    private var cancellables = Set<AnyCancellable>()

    /// Unit tests load the app as their host; don't put up the island then.
    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement already keeps us out of the Dock; this makes it explicit
        // when running from Xcode too.
        NSApp.setActivationPolicy(.accessory)
        SettingsKeys.registerDefaults()
        guard !isRunningTests else { return }

        let battery = BatteryService()
        let clock = ClockService()
        let nowPlaying = NowPlayingService()
        let lyrics = LyricsService(nowPlaying: nowPlaying)
        let shelf = ShelfService()
        battery.start()
        clock.start()
        nowPlaying.start()
        lyrics.start()
        self.lyrics = lyrics

        let viewModel = IslandViewModel(
            battery: battery,
            clock: clock,
            camera: CameraService(),
            shelf: shelf,
            projects: ProjectsService(),
            nowPlaying: nowPlaying
        )
        lyrics.$currentLine
            .receive(on: RunLoop.main)
            .sink { [weak viewModel] line in viewModel?.lyricLine = line }
            .store(in: &cancellables)

        let controller = NotchWindowController(viewModel: viewModel)
        controller.start()
        windowController = controller

        settingsController = SettingsWindowController {
            SettingsView(nowPlaying: nowPlaying, shelfDirectory: shelf.filesDirectory)
        }
        installStatusItem()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "NotchIsland")

        let menu = NSMenu()
        let settings = NSMenuItem(
            title: String(localized: "Settings…"),
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: String(localized: "Quit NotchIsland"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        item.menu = menu
        statusItem = item
    }

    @objc private func showSettings() {
        settingsController?.show()
    }
}
