import Foundation

/// A snapshot of what a player is playing. `elapsed` is the position at
/// `timestamp`; the current position is extrapolated while playing so we
/// don't have to poll players for it.
nonisolated struct NowPlayingInfo: Equatable, Sendable {
    /// Changes when the track changes (Spotify/Music track id, YouTube video id).
    var trackID: String
    var title: String
    var artist: String
    var album: String
    /// Seconds; nil when unknown (e.g. live streams).
    var duration: TimeInterval?
    var elapsed: TimeInterval
    var timestamp: Date
    var isPlaying: Bool
    var artworkURL: URL?

    func position(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return elapsed }
        let position = elapsed + max(0, date.timeIntervalSince(timestamp))
        if let duration, duration > 0 { return min(position, duration) }
        return position
    }

    /// Same track and play state, and positions agree within `tolerance`.
    /// Used to skip updates that would only add jitter.
    func isEquivalent(to other: NowPlayingInfo, tolerance: TimeInterval = 1) -> Bool {
        let now = Date()
        return trackID == other.trackID
            && title == other.title
            && artist == other.artist
            && isPlaying == other.isPlaying
            && artworkURL == other.artworkURL
            && abs(position(at: now) - other.position(at: now)) < tolerance
    }
}

enum MusicSourceKind: String, CaseIterable, Identifiable {
    case spotify
    case appleMusic
    case browser

    var id: String { rawValue }

    /// UserDefaults key that enables this kind of source.
    var settingsKey: String {
        switch self {
        case .spotify: SettingsKeys.musicSpotify
        case .appleMusic: SettingsKeys.musicAppleMusic
        case .browser: SettingsKeys.musicBrowser
        }
    }
}

/// Why a source can't report anything, shown in Settings and the Home tab.
enum MusicSourceIssue: Equatable {
    /// Automation permission for this app was denied.
    case notAuthorized
    /// The browser's "Allow JavaScript from Apple Events" option is off.
    case javascriptDisabled
}

/// A player we can read and control. Implementations call `onUpdate` on the
/// main actor whenever `info` or `issue` changes.
protocol MusicSource: AnyObject {
    var kind: MusicSourceKind { get }
    /// "Spotify", "Music", "Chrome"…
    var displayName: String { get }
    var info: NowPlayingInfo? { get }
    var issue: MusicSourceIssue? { get }
    var onUpdate: (() -> Void)? { get set }

    func start()
    func stop()
    func playPause()
    func nextTrack()
    func previousTrack()
}
