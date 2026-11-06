import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NotchWindowController?
    private var settingsController: SettingsWindowController?
    private var statusItem: NSStatusItem?
    private var lyrics: LyricsService?
    private var lyricMoods: LyricMoodService?
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
        let lyricMoods = LyricMoodService(nowPlaying: nowPlaying)
        lyricMoods.start()
        self.lyricMoods = lyricMoods
        let devActivity = DevActivityService()
        devActivity.start()
        let clipboard = ClipboardService()
        clipboard.start()

        let kanban = KanbanService()
        kanban.onRequestSignIn = { [weak self] in self?.showSettings() }
        let mic = MicService()
        mic.start()
        let viewModel = IslandViewModel(
            battery: battery,
            systemStats: SystemStatsService(),
            clock: clock,
            camera: CameraService(),
            shelf: shelf,
            projects: ProjectsService(),
            storage: StorageService(),
            kanban: kanban,
            nowPlaying: nowPlaying,
            lyricMoods: lyricMoods,
<<<<<<< HEAD
            ports: PortsService(),
            devActivity: devActivity,
            clipboard: clipboard
=======
            mic: mic
>>>>>>> upstream/main
        )
        lyrics.$currentLine
            .receive(on: RunLoop.main)
            .sink { [weak viewModel] line in viewModel?.lyricLine = line }
            .store(in: &cancellables)
        devActivity.$alert
            .receive(on: RunLoop.main)
            .sink { [weak viewModel] event in viewModel?.devAlert = event }
            .store(in: &cancellables)
        lyricMoods.$mood
            .receive(on: RunLoop.main)
            .sink { [weak viewModel] mood in viewModel?.lyricMood = mood }
            .store(in: &cancellables)

        let controller = NotchWindowController(viewModel: viewModel)
        controller.start()
        windowController = controller

        settingsController = SettingsWindowController {
            SettingsView(nowPlaying: nowPlaying, kanban: kanban, shelfDirectory: shelf.filesDirectory)
        }
        installStatusItem()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.robotEyesIcon()

        let menu = NSMenu()
        let about = NSMenuItem(
            title: String(localized: "About NotchIsland"),
            action: #selector(showSettings),
            keyEquivalent: ""
        )
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())

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

    /// The robot's two rounded eyes, each with a little shine cut out, as a
    /// template image so the menu bar tints it for light and dark.
    private static func robotEyesIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let eye = NSSize(width: 6, height: 8.5), gap: CGFloat = 3
            let path = NSBezierPath()
            path.windingRule = .evenOdd
            for x in [(18 - gap) / 2 - eye.width, (18 + gap) / 2] {
                let rect = NSRect(x: x, y: (18 - eye.height) / 2, width: eye.width, height: eye.height)
                path.append(NSBezierPath(roundedRect: rect, xRadius: 2.2, yRadius: 2.2))
                path.append(NSBezierPath(ovalIn: NSRect(x: rect.midX + 0.2, y: rect.minY + 1.4, width: 1.9, height: 1.9)))
            }
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "NotchIsland"
        return image
    }

    @objc private func showSettings() {
        settingsController?.show()
    }
}
