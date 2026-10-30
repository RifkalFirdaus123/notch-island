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
    /// Folder listed in the Projects tab; empty means ~/Documents/hotama.
    static let projectsFolder = "projectsFolder"
    static let featureStorage = "featureStorage"
    static let featureLyrics = "featureLyrics"
    /// Height of the lyric strip under the notch, in points.
    static let lyricStripHeight = "lyricStripHeight"

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
            featureStorage: true,
            featureLyrics: true,
            lyricStripHeight: defaultLyricStripHeight,
            musicSpotify: true,
            musicAppleMusic: true,
            musicBrowser: true,
        ])
    }
}
