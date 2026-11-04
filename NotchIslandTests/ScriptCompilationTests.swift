import AppKit
import Testing
@testable import NotchIsland

/// Compiling only reads the target app's scripting dictionary; it sends no
/// Apple Events, so it needs no Automation permission and launches nothing.
/// Each test is skipped when the app isn't installed.
struct ScriptCompilationTests {
    private static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    private func compileError(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return "could not create script" }
        var error: NSDictionary?
        return script.compileAndReturnError(&error) ? nil : "\(error ?? [:])"
    }

    @Test(.enabled(if: isInstalled("com.spotify.client")))
    func spotifyScriptsCompile() {
        #expect(compileError(ScriptedPlayer.spotify.stateScript) == nil)
        #expect(compileError(ScriptedPlayer.spotify.commandScript("playpause")) == nil)
        #expect(compileError(ScriptedPlayer.spotify.commandScript("next track")) == nil)
        #expect(compileError(ScriptedPlayer.spotify.commandScript("previous track")) == nil)
        #expect(compileError(ScriptedPlayer.spotify.commandScript(ScriptedPlayer.spotify.seekCommand(to: 83.5))) == nil)
    }

    @Test(.enabled(if: isInstalled("com.apple.Music")))
    func musicScriptsCompile() {
        #expect(compileError(ScriptedPlayer.appleMusic.stateScript) == nil)
        #expect(compileError(ScriptedPlayer.appleMusicArtworkScript) == nil)
        #expect(compileError(ScriptedPlayer.appleMusic.commandScript("playpause")) == nil)
        #expect(compileError(ScriptedPlayer.appleMusic.commandScript("next track")) == nil)
        #expect(compileError(ScriptedPlayer.appleMusic.commandScript("previous track")) == nil)
        #expect(compileError(ScriptedPlayer.appleMusic.commandScript(ScriptedPlayer.appleMusic.seekCommand(to: 83.5))) == nil)
    }

    @Test(arguments: BrowserSource.supported.map(\.bundleID).filter(isInstalled))
    func browserScriptsCompile(bundleID: String) {
        #expect(compileError(BrowserScripts.pollScript(bundleID: bundleID)) == nil)
        #expect(compileError(BrowserScripts.pollScript(bundleID: bundleID, skipping: ["12", "\"AB-CD\""])) == nil)

        let info = NowPlayingInfo(
            trackID: "x", title: "t", artist: "", album: "", duration: nil,
            elapsed: 0, timestamp: Date(), isPlaying: true, artworkURL: nil
        )
        for tab in [
            BrowserTab(windowIDLiteral: "12", tabIDLiteral: "34", info: info),
            BrowserTab(windowIDLiteral: "12", tabIDLiteral: "\"34\"", info: info),
        ] {
            for js in [BrowserScripts.playPauseJS, BrowserScripts.nextJS, BrowserScripts.previousJS, BrowserScripts.skipAdJS, BrowserScripts.seekJS(to: 83.5)] {
                #expect(compileError(BrowserScripts.executeScript(bundleID: bundleID, tab: tab, javaScript: js)) == nil)
            }
        }
    }

    @Test func parsesYouTubePageState() throws {
        let json = #"{"ti":"Yellow","ar":"Coldplay","al":"","art":"","t":12.5,"d":269,"p":false}"#
        let info = try #require(BrowserScripts.parseInfo(json: json, url: "https://www.youtube.com/watch?v=yKNxeF4KMsY&t=3"))
        #expect(info.trackID == "yKNxeF4KMsY")
        #expect(info.title == "Yellow")
        #expect(info.isPlaying)
        #expect(info.duration == 269)
        #expect(info.artworkURL?.absoluteString == "https://i.ytimg.com/vi/yKNxeF4KMsY/hqdefault.jpg")
    }

    @Test func parsesAdState() throws {
        let json = #"{"ti":"Yellow","ar":"","al":"","art":"","t":3,"d":15,"p":false,"ad":true,"sk":true}"#
        let info = try #require(BrowserScripts.parseInfo(json: json, url: "https://www.youtube.com/watch?v=yKNxeF4KMsY"))
        #expect(info.isAd)
        #expect(info.canSkipAd)
    }

    /// Arc hands back the result JSON-encoded.
    @Test func parsesJSONEncodedResultFromArc() throws {
        let json = #""{\"ti\":\"kids\",\"ar\":\"Hindia - Topic\",\"al\":\"\",\"art\":\"\",\"t\":34.1,\"d\":182.4,\"p\":true}""#
        let info = try #require(BrowserScripts.parseInfo(json: json, url: "https://www.youtube.com/watch?v=cJaD7nqU7zU"))
        #expect(info.title == "kids")
        #expect(info.artist == "Hindia - Topic")
        #expect(!info.isPlaying)
    }

    @Test func ignoresPagesWithoutVideo() {
        #expect(BrowserScripts.parseInfo(json: "", url: "https://www.youtube.com/watch?v=x") == nil)
    }
}
