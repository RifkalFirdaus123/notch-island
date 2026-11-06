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
    /// Folders listed in the Projects tab, newline-separated; empty means ~/Documents/hotama.
    static let projectsFolder = "projectsFolder"
    /// Default application used to open projects ("vscode", "antigravity", "finder").
    static let projectsEditor = "projectsEditor"
    static let featureStorage = "featureStorage"
    /// Tasks tab: unfinished cards from Resam Kanban (kanban.resam.id).
    static let featureKanban = "featureKanban"
    /// Which cards the Tasks tab lists ("assigned" or "requested").
    static let kanbanScope = "kanbanScope"
    /// Name and institution of the signed-in Resam Kanban user; the token is in the keychain.
    static let kanbanUserName = "kanbanUserName"
    static let kanbanInstitutionID = "kanbanInstitutionID"
    static let featureLyrics = "featureLyrics"
    /// Dev tab: ports, terminal and agent activity, clipboard and tools.
    static let featureDev = "featureDev"
    /// Pop terminal and agent events up on the island.
    static let devAlerts = "devAlerts"
    /// Keep recently copied text (in memory only) in the Dev tab.
    static let clipboardHistory = "clipboardHistory"
    /// Color and style lyrics by the song's mood (calm, hard, upbeat).
    static let lyricMoodStyle = "lyricMoodStyle"
    /// Moods picked by hand, keyed by song ("artist|title").
    static let lyricMoodOverrides = "lyricMoodOverrides"
    /// Robot on the Home tab; also replaces the equalizer beside the notch while music plays.
    static let featureBuddy = "featureBuddy"
    /// With nothing playing, the robot wanders just outside the notch and can be clicked.
    static let featureBuddyPeek = "featureBuddyPeek"
    /// Mute button beside the notch while an app is using the microphone.
    static let featureMic = "featureMic"
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
            projectsFolder: "",
            projectsEditor: "antigravity",
            featureStorage: true,
            featureKanban: true,
            featureLyrics: true,
            featureDev: true,
            devAlerts: true,
            clipboardHistory: true,
            lyricMoodStyle: false,
            featureBuddy: true,
            featureBuddyPeek: true,
            featureMic: true,
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
