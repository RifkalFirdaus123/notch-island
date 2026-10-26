import AppKit

/// YouTube and YouTube Music playing in a Chromium browser (Chrome, Arc,
/// Brave, Edge). Reads the page's <video> element and Media Session metadata by
/// running a little JavaScript through the browser's AppleScript support.
///
/// Requires the browser's View › Developer › Allow JavaScript from Apple
/// Events option. Browsers post no change notifications, so this polls, but
/// only while the browser is running and at a slow rate.
final class BrowserSource: MusicSource {
    private static let pollWhilePlaying: Duration = .seconds(2)
    private static let pollIdle: Duration = .seconds(5)
    /// How long to leave a tab alone after it didn't answer (e.g. a tab the
    /// browser put to sleep), so it doesn't stall every poll.
    private static let unresponsiveBackoff: TimeInterval = 60

    let kind = MusicSourceKind.browser
    let displayName: String
    let bundleID: String
    private(set) var info: NowPlayingInfo?
    private(set) var issue: MusicSourceIssue?
    var onUpdate: (() -> Void)?

    private let runner: AppleScriptRunner
    private var pollTask: Task<Void, Never>?
    /// The tab we last read, so controls go to the same one.
    private var tab: BrowserTab?
    /// Tab id literals that timed out, and when.
    private var unresponsiveTabs: [String: Date] = [:]

    init(displayName: String, bundleID: String, runner: AppleScriptRunner = .shared) {
        self.displayName = displayName
        self.bundleID = bundleID
        self.runner = runner
    }

    nonisolated static let supported: [(name: String, bundleID: String)] = [
        ("Chrome", "com.google.Chrome"),
        ("Arc", "company.thebrowser.Browser"),
        ("Brave", "com.brave.Browser"),
        ("Edge", "com.microsoft.edgemac"),
    ]

    private var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                let delay = self?.info?.isPlaying == true ? Self.pollWhilePlaying : Self.pollIdle
                try? await Task.sleep(for: delay)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        tab = nil
        update(info: nil, issue: nil)
    }

    private func poll() async {
        guard isRunning else {
            tab = nil
            update(info: nil, issue: nil)
            return
        }
        let now = Date()
        unresponsiveTabs = unresponsiveTabs.filter { now.timeIntervalSince($0.value) < Self.unresponsiveBackoff }
        let skipping = unresponsiveTabs.keys.sorted()
        let script = BrowserScripts.pollScript(bundleID: bundleID, skipping: skipping)
        // Only cache the usual variant; skip lists come and go.
        let result = await runner.run(script, cache: skipping.isEmpty, parse: BrowserScripts.parseTabs)
        switch result {
        case .success(let poll):
            for id in poll.timedOut { unresponsiveTabs[id] = now }
            let tabs = poll.tabs
            // Prefer a tab that is actually playing.
            let chosen = tabs.first { $0.isPlaying } ?? tabs.first
            tab = chosen
            update(info: chosen?.info, issue: nil)
        case .failure(.notAuthorized):
            update(info: nil, issue: .notAuthorized)
        case .failure(.javascriptDisabled):
            update(info: nil, issue: .javascriptDisabled)
        case .failure:
            update(info: nil, issue: nil)
        }
    }

    func playPause() { run(BrowserScripts.playPauseJS) }
    func nextTrack() { run(BrowserScripts.nextJS) }
    func previousTrack() { run(BrowserScripts.previousJS) }

    private func run(_ javaScript: String) {
        guard let tab, isRunning else { return }
        let script = BrowserScripts.executeScript(bundleID: bundleID, tab: tab, javaScript: javaScript)
        Task {
            await runner.send(script)
            // Give the page a moment to react before reading it again.
            try? await Task.sleep(for: .milliseconds(300))
            await poll()
        }
    }

    private func update(info newInfo: NowPlayingInfo?, issue newIssue: MusicSourceIssue?) {
        guard newInfo != info || newIssue != issue else { return }
        info = newInfo
        issue = newIssue
        onUpdate?()
    }
}

/// A YouTube tab found while polling.
nonisolated struct BrowserTab: Sendable {
    /// Ready-to-use AppleScript literals (ids can be numbers or text).
    var windowIDLiteral: String
    var tabIDLiteral: String
    var info: NowPlayingInfo
    var isPlaying: Bool { info.isPlaying }
}

nonisolated enum BrowserScripts {
    /// Reads the main <video> and Media Session metadata as JSON.
    /// Uses single quotes only, so it can sit inside an AppleScript string.
    static let readJS = """
    (function(){var v=document.querySelector('video.html5-main-video')||document.querySelector('video');\
    if(!v)return '';var m=navigator.mediaSession&&navigator.mediaSession.metadata;var a='';\
    if(m&&m.artwork&&m.artwork.length){a=m.artwork[m.artwork.length-1].src;}\
    return JSON.stringify({ti:(m&&m.title)?m.title:document.title.replace(/ - YouTube( Music)?$/,''),\
    ar:(m&&m.artist)?m.artist:'',al:(m&&m.album)?m.album:'',art:a,t:v.currentTime||0,\
    d:isFinite(v.duration)?v.duration:0,p:v.paused});})()
    """

    static let playPauseJS = """
    (function(){var v=document.querySelector('video.html5-main-video')||document.querySelector('video');\
    if(v){if(v.paused){v.play();}else{v.pause();}}return '';})()
    """

    static let nextJS = """
    (function(){var b=document.querySelector('ytmusic-player-bar .next-button')||document.querySelector('.ytp-next-button');\
    if(b)b.click();return '';})()
    """

    /// YouTube has no "previous" button for normal videos: restart the video,
    /// or go back in history when already near the start.
    static let previousJS = """
    (function(){var b=document.querySelector('ytmusic-player-bar .previous-button');if(b){b.click();return '';}\
    var v=document.querySelector('video.html5-main-video')||document.querySelector('video');\
    if(v&&v.currentTime>3){v.currentTime=0;}else{history.back();}return '';})()
    """

    /// Returns {{windowID, tabID, url, json}, …} for every YouTube tab. A tab
    /// that doesn't answer in time reports `timeoutMarker` as its json.
    /// `skipping` holds tab id literals to leave out.
    static func pollScript(bundleID: String, skipping: [String] = []) -> String {
        """
        tell application id "\(bundleID)"
            set skipIDs to {\(skipping.joined(separator: ", "))}
            set out to {}
            repeat with w in windows
                set tabURLs to URL of every tab of w
                set tabIDs to id of every tab of w
                repeat with i from 1 to count of tabURLs
                    set u to item i of tabURLs
                    set tid to item i of tabIDs
                    if (u contains "youtube.com/watch" or u starts with "https://music.youtube.com") and skipIDs does not contain tid then
                        try
                            -- Sleeping tabs (e.g. pinned tabs in Arc) never answer.
                            with timeout of 2 seconds
                                set j to execute (tab id tid of w) javascript "\(readJS.appleScriptEscaped)"
                            end timeout
                        on error errMsg number errNum
                            -- Report a disabled JavaScript option; skip tabs that just failed.
                            if errMsg contains "JavaScript" or errNum is -1743 then error errMsg number errNum
                            if errNum is -1712 then
                                set j to "\(timeoutMarker)"
                            else
                                set j to ""
                            end if
                        end try
                        set end of out to {id of w, tid, u, j}
                    end if
                end repeat
            end repeat
            return out
        end tell
        """
    }

    static func executeScript(bundleID: String, tab: BrowserTab, javaScript: String) -> String {
        """
        tell application id "\(bundleID)"
            execute (tab id \(tab.tabIDLiteral) of window id \(tab.windowIDLiteral)) javascript "\(javaScript.appleScriptEscaped)"
        end tell
        """
    }

    static let timeoutMarker = "__notchisland_timeout__"

    struct PollResult: Sendable {
        var tabs: [BrowserTab] = []
        /// Tab id literals that didn't answer in time.
        var timedOut: [String] = []
    }

    @Sendable static func parseTabs(_ result: NSAppleEventDescriptor) -> PollResult {
        var poll = PollResult()
        guard result.numberOfItems > 0 else { return poll }
        for index in 1...result.numberOfItems {
            guard let entry = result.item(index), entry.numberOfItems >= 4,
                  let windowID = entry.item(1), let tabID = entry.item(2)
            else { continue }
            let json = entry.string(at: 4)
            if json == timeoutMarker {
                poll.timedOut.append(literal(tabID))
            } else if let info = parseInfo(json: json, url: entry.string(at: 3)) {
                poll.tabs.append(BrowserTab(windowIDLiteral: literal(windowID), tabIDLiteral: literal(tabID), info: info))
            }
        }
        return poll
    }

    private struct PageState: Decodable {
        var ti: String
        var ar: String
        var al: String
        var art: String
        var t: Double
        var d: Double
        var p: Bool
    }

    static func parseInfo(json: String, url: String) -> NowPlayingInfo? {
        guard let data = unwrapped(json).data(using: .utf8),
              let state = try? JSONDecoder().decode(PageState.self, from: data),
              !state.ti.isEmpty
        else { return nil }

        let videoID = URLComponents(string: url)?.queryItems?.first { $0.name == "v" }?.value
        var artwork = URL(string: state.art)
        if artwork == nil || state.art.isEmpty, let videoID {
            artwork = URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
        }
        return NowPlayingInfo(
            trackID: videoID ?? state.ti,
            title: state.ti,
            artist: state.ar,
            album: state.al,
            duration: state.d > 0 ? state.d : nil,
            elapsed: state.t,
            timestamp: Date(),
            isPlaying: !state.p,
            artworkURL: artwork
        )
    }

    /// Arc returns the script's result JSON-encoded, so our JSON arrives
    /// wrapped in a JSON string literal; Chrome returns it as is.
    private static func unwrapped(_ json: String) -> String {
        guard json.hasPrefix("\""), let data = json.data(using: .utf8),
              let inner = try? JSONDecoder().decode(String.self, from: data)
        else { return json }
        return inner
    }

    /// Chromium tab/window ids have been integers or text depending on the
    /// version; reuse whichever type the browser gave us.
    private static func literal(_ descriptor: NSAppleEventDescriptor) -> String {
        let isText = descriptor.descriptorType == typeUnicodeText
            || descriptor.descriptorType == typeUTF8Text
            || descriptor.descriptorType == typeChar
        let value = descriptor.stringValue ?? "0"
        return isText ? "\"\(value.appleScriptEscaped)\"" : value
    }
}
