import SwiftUI

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

    let battery: BatteryService
    let systemStats: SystemStatsService
    let clock: ClockService
    let camera: CameraService
    let shelf: ShelfService
    let projects: ProjectsService
    let storage: StorageService
    let nowPlaying: NowPlayingService

    /// Width of each "ear" next to the notch in the hover state.
    static let earWidth: CGFloat = 96
    /// Narrower ears for the idle now-playing row.
    static let idleEarWidth: CGFloat = 42
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
        nowPlaying: NowPlayingService
    ) {
        self.battery = battery
        self.systemStats = systemStats
        self.clock = clock
        self.camera = camera
        self.shelf = shelf
        self.projects = projects
        self.storage = storage
        self.nowPlaying = nowPlaying
    }

    /// What to show when nobody is hovering.
    var idleState: IslandState {
        if lyricLine != nil { return .lyric }
        return nowPlaying.info?.isPlaying == true ? .playing : .collapsed
    }

    /// Tabs switched on in Settings; Home is always there.
    var enabledTabs: [IslandTab] {
        IslandTab.allCases.filter { tab in
            switch tab {
            case .home: true
            case .camera: UserDefaults.standard.bool(forKey: SettingsKeys.featureCamera)
            case .shelf: UserDefaults.standard.bool(forKey: SettingsKeys.featureShelf)
            case .projects: UserDefaults.standard.bool(forKey: SettingsKeys.featureProjects)
            case .storage: UserDefaults.standard.bool(forKey: SettingsKeys.featureStorage)
            }
        }
    }

    func select(_ tab: IslandTab) {
        guard tab != selectedTab else { return }
        tabTransitionEdge = tab.rawValue > selectedTab.rawValue ? .trailing : .leading
        selectedTab = tab
    }

    /// Falls back to Home if the selected tab was switched off.
    func validateSelectedTab() {
        if !enabledTabs.contains(selectedTab) { select(.home) }
    }

    var notchSize: CGSize {
        geometry?.notchSize ?? CGSize(width: NotchGeometry.fallbackNotchWidth, height: 32)
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
        switch state {
        case .collapsed:
            return notch
        case .playing:
            return CGSize(width: notch.width + Self.idleEarWidth * 2, height: notch.height)
        case .lyric:
            let textWidth = lyricLine.map(LyricStripView.textWidth) ?? 0
            let width = min(maxLyricWidth, max(notch.width + Self.idleEarWidth * 2, textWidth))
            return CGSize(width: width, height: notch.height + lyricStripHeight)
        case .hover:
            return CGSize(width: notch.width + Self.earWidth * 2, height: notch.height)
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
