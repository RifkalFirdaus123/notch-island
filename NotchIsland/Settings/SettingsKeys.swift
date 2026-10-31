import Foundation

/// UserDefaults keys, edited in `SettingsView`.
enum SettingsKeys {
    /// Keep the island active over fullscreen apps.
    static let showInFullscreen = "showInFullscreen"
    /// Copy dropped files into the app's shelf folder instead of keeping a
    /// reference to the original.
    static let shelfCopiesFiles = "shelfCopiesFiles"

    static let featureCamera = "featureCamera"
    static let featureShelf = "featureShelf"
    static let featureProjects = "featureProjects"
    static let featurePomodoro = "featurePomodoro"
    static let pomodoroWorkMinutes = "pomodoroWorkMinutes"
    static let pomodoroShortBreakMinutes = "pomodoroShortBreakMinutes"
    static let pomodoroLongBreakMinutes = "pomodoroLongBreakMinutes"
    static let pomodoroLongBreakInterval = "pomodoroLongBreakInterval"
    /// Folder listed in the Projects tab; empty means ~/Documents/hotama.
    static let projectsFolder = "projectsFolder"
    /// Default application used to open projects ("vscode", "antigravity", "finder").
    static let projectsEditor = "projectsEditor"
    static let featureStorage = "featureStorage"
    static let featureLyrics = "featureLyrics"
    /// Color and style lyrics by the song's mood (calm, hard, upbeat).
    static let lyricMoodStyle = "lyricMoodStyle"
    /// Moods picked by hand, keyed by song ("artist|title").
    static let lyricMoodOverrides = "lyricMoodOverrides"
    /// Height of the lyric strip under the notch, in points.
    static let lyricStripHeight = "lyricStripHeight"

    /// Points added to the idle island's width and height, beyond the notch.
    static let idleExtraWidth = "idleExtraWidth"
    static let idleExtraHeight = "idleExtraHeight"
    /// Press YouTube's "Skip ad" button as soon as it appears.
    static let autoSkipAds = "autoSkipAds"

    static let musicSpotify = "musicSpotify"
    static let musicAppleMusic = "musicAppleMusic"
    static let musicBrowser = "musicBrowser"

    static let defaultLyricStripHeight: Double = 24

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showInFullscreen: false,
            shelfCopiesFiles: false,
            featureCamera: true,
            featureShelf: true,
            featureProjects: true,
            featurePomodoro: true,
            pomodoroWorkMinutes: 25,
            pomodoroShortBreakMinutes: 5,
            pomodoroLongBreakMinutes: 15,
            pomodoroLongBreakInterval: 4,
            projectsFolder: "",
            projectsEditor: "antigravity",
            featureStorage: true,
            featureLyrics: true,
            lyricMoodStyle: false,
            lyricStripHeight: defaultLyricStripHeight,
            idleExtraWidth: 0.0,
            idleExtraHeight: 0.0,
            autoSkipAds: true,
            musicSpotify: true,
            musicAppleMusic: true,
            musicBrowser: true,
        ])
    }
}
