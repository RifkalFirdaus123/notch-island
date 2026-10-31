import SwiftUI

@MainActor
final class IslandViewModel: ObservableObject {
    @Published var state: IslandState = .collapsed
    @Published private(set) var selectedTab: IslandTab = .home
    /// Edge the new tab slides in from, based on tab order.
    @Published private(set) var tabTransitionEdge: Edge = .trailing
    @Published var geometry: NotchGeometry?
    /// True while a fullscreen app is frontmost and the island should hide.
    @Published var isSuppressed = false
    /// Mirrors `LyricsService.currentLine`; drives the `.lyric` idle state.
    @Published var lyricLine: String?
    /// Mirrors `LyricMoodService.mood`; styles the lyric strip.
    @Published var lyricMood: LyricMood = .neutral

    let battery: BatteryService
    let systemStats: SystemStatsService
    let clock: ClockService
    let camera: CameraService
    let shelf: ShelfService
    let projects: ProjectsService
    let storage: StorageService
    let nowPlaying: NowPlayingService
    let lyricMoods: LyricMoodService
    let pomodoro: PomodoroService

    /// Width of each "ear" next to the notch in the hover state.
    static let earWidth: CGFloat = 96
    /// Narrower ears for the idle now-playing or pomodoro row.
    static let idleEarWidth: CGFloat = 46
    static let expandedBaseSize = CGSize(width: 460, height: 180)
    /// The lyric strip may grow to this fraction of the screen width.
    static let maxLyricWidthFraction: CGFloat = 0.6

    init(
        battery: BatteryService,
        systemStats: SystemStatsService,
        clock: ClockService,
        camera: CameraService,
        shelf: ShelfService,
        projects: ProjectsService,
        storage: StorageService,
        nowPlaying: NowPlayingService,
        pomodoro: PomodoroService,
        lyricMoods: LyricMoodService
    ) {
        self.battery = battery
        self.systemStats = systemStats
        self.clock = clock
        self.camera = camera
        self.shelf = shelf
        self.projects = projects
        self.storage = storage
        self.nowPlaying = nowPlaying
        self.pomodoro = pomodoro
        self.lyricMoods = lyricMoods
    }

    /// What to show when nobody is hovering.
    var idleState: IslandState {
        if lyricLine != nil { return .lyric }
        if nowPlaying.info?.isPlaying == true { return .playing }
        if pomodoro.isActive { return .pomodoro }
        return .collapsed
    }

    /// Tabs switched on in Settings; Home is always there.
    var enabledTabs: [IslandTab] {
        IslandTab.allCases.filter { tab in
            switch tab {
            case .home: true
            case .pomodoro: UserDefaults.standard.bool(forKey: SettingsKeys.featurePomodoro)
            case .camera: UserDefaults.standard.bool(forKey: SettingsKeys.featureCamera)
            case .shelf: UserDefaults.standard.bool(forKey: SettingsKeys.featureShelf)
            case .projects: UserDefaults.standard.bool(forKey: SettingsKeys.featureProjects)
            case .storage: UserDefaults.standard.bool(forKey: SettingsKeys.featureStorage)
            }
        }
    }

    /// Up to three tabs fit in the left ear; remaining tabs flow into the right ear beside the title.
    var leftEarTabs: [IslandTab] {
        Array(enabledTabs.prefix(3))
    }

    var rightEarTabs: [IslandTab] {
        Array(enabledTabs.dropFirst(3))
    }

    func select(_ tab: IslandTab) {
        guard tab != selectedTab else { return }
        let currentIndex = enabledTabs.firstIndex(of: selectedTab) ?? 0
        let targetIndex = enabledTabs.firstIndex(of: tab) ?? 0
        tabTransitionEdge = targetIndex > currentIndex ? .trailing : .leading
        selectedTab = tab
    }

    /// Falls back to Home if the selected tab was switched off.
    func validateSelectedTab() {
        if !enabledTabs.contains(selectedTab) { select(.home) }
    }

    var notchSize: CGSize {
        geometry?.notchSize ?? CGSize(width: NotchGeometry.fallbackNotchWidth, height: 32)
    }

    /// The notch as drawn while idle: the physical notch plus the extra
    /// width and height set in Settings. It can't be smaller than the notch.
    var idleNotchSize: CGSize {
        let defaults = UserDefaults.standard
        return CGSize(
            width: notchSize.width + max(0, defaults.double(forKey: SettingsKeys.idleExtraWidth)),
            height: notchSize.height + max(0, defaults.double(forKey: SettingsKeys.idleExtraHeight))
        )
    }

    var lyricStripHeight: CGFloat {
        let stored = UserDefaults.standard.double(forKey: SettingsKeys.lyricStripHeight)
        return stored > 0 ? stored : SettingsKeys.defaultLyricStripHeight
    }

    var maxLyricWidth: CGFloat {
        (geometry?.screenFrame.width ?? 1440) * Self.maxLyricWidthFraction
    }

    /// Size of the black shape (excluding the small top flares) for a state.
    func size(for state: IslandState) -> CGSize {
        let notch = notchSize
        let idle = idleNotchSize
        switch state {
        case .collapsed:
            return idle
        case .playing, .pomodoro:
            return CGSize(width: idle.width + Self.idleEarWidth * 2, height: idle.height)
        case .lyric:
            let textWidth = lyricLine.map { LyricStripView.textWidth($0, mood: lyricMood) } ?? 0
            let width = min(maxLyricWidth, max(idle.width + Self.idleEarWidth * 2, textWidth))
            return CGSize(width: width, height: idle.height + lyricStripHeight)
        case .hover:
            // Never smaller than the idle shape it grows out of.
            return CGSize(width: max(notch.width + Self.earWidth * 2, idle.width), height: idle.height)
        case .expanded:
            return CGSize(
                width: max(Self.expandedBaseSize.width, notch.width + Self.earWidth * 2),
                height: max(Self.expandedBaseSize.height, notch.height + 100)
            )
        }
    }

    /// Screen rect of the visible shape for a state, used for hover hit-testing.
    func screenRect(for state: IslandState) -> CGRect {
        geometry?.topCenteredRect(size: size(for: state)) ?? .zero
    }
}
