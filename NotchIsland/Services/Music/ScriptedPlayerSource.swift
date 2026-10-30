import AppKit
import Combine

/// How to talk to one scriptable desktop player.
nonisolated struct ScriptedPlayer: Sendable {
    let kind: MusicSourceKind
    let displayName: String
    let bundleID: String
    /// Distributed notification the app posts on play/pause/track change.
    let notificationName: String
    /// Returns `{"stopped"}` or a list that `parse` understands.
    let stateScript: String
    let parse: @Sendable (NSAppleEventDescriptor) -> NowPlayingInfo?

    func commandScript(_ command: String) -> String {
        "tell application id \"\(bundleID)\" to \(command)"
    }

    /// Spotify and Music both take the position in seconds.
    func seekCommand(to position: TimeInterval) -> String {
        "set player position to " + String(format: "%.2f", max(0, position))
    }
}

/// Spotify or Music. Refreshes when the app posts its change notification,
/// and re-reads the position every few seconds while playing to catch seeks.
final class ScriptedPlayerSource: MusicSource {
    private static let resyncInterval: Duration = .seconds(5)

    let player: ScriptedPlayer
    var kind: MusicSourceKind { player.kind }
    var displayName: String { player.displayName }
    private(set) var info: NowPlayingInfo?
    private(set) var issue: MusicSourceIssue?
    var onUpdate: (() -> Void)?

    private let runner: AppleScriptRunner
    private var cancellables = Set<AnyCancellable>()
    private var resyncTask: Task<Void, Never>?
    /// Ignores results from refreshes that a newer one has superseded.
    private var generation = 0

    init(player: ScriptedPlayer, runner: AppleScriptRunner = .shared) {
        self.player = player
        self.runner = runner
    }

    private var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty
    }

    func start() {
        guard cancellables.isEmpty else { return }

        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name(player.notificationName))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .merge(with: workspace.publisher(for: NSWorkspace.didTerminateApplicationNotification))
            .filter { [bundleID = player.bundleID] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                return app?.bundleIdentifier == bundleID
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        resyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.resyncInterval)
                guard let self, self.info?.isPlaying == true else { continue }
                self.refresh()
            }
        }

        refresh()
    }

    func stop() {
        cancellables.removeAll()
        resyncTask?.cancel()
        resyncTask = nil
        generation += 1
        update(info: nil, issue: nil)
    }

    func refresh() {
        generation += 1
        let current = generation
        // Never script an app that isn't running: that would launch it.
        guard isRunning else {
            update(info: nil, issue: nil)
            return
        }
        Task {
            let result = await runner.run(player.stateScript, parse: player.parse)
            guard current == generation else { return }
            switch result {
            case .success(let info):
                update(info: info, issue: nil)
            case .failure(.notAuthorized):
                update(info: nil, issue: .notAuthorized)
            case .failure:
                update(info: nil, issue: nil)
            }
        }
    }

    func playPause() { command("playpause") }
    func nextTrack() { command("next track") }
    func previousTrack() { command("previous track") }

    func seek(to position: TimeInterval) {
        guard var newInfo = info else { return }
        // Show the new position right away, and drop any refresh already in
        // flight so it can't snap the bar back.
        generation += 1
        newInfo.elapsed = position
        newInfo.timestamp = Date()
        update(info: newInfo, issue: issue)
        command(player.seekCommand(to: position))
    }

    private func command(_ command: String) {
        guard isRunning else { return }
        Task {
            await runner.send(player.commandScript(command))
            refresh()
        }
    }

    private func update(info newInfo: NowPlayingInfo?, issue newIssue: MusicSourceIssue?) {
        guard newInfo != info || newIssue != issue else { return }
        info = newInfo
        issue = newIssue
        onUpdate?()
    }
}

// MARK: - Players

nonisolated extension ScriptedPlayer {
    static let spotify = ScriptedPlayer(
        kind: .spotify,
        displayName: "Spotify",
        bundleID: "com.spotify.client",
        notificationName: "com.spotify.client.PlaybackStateChanged",
        stateScript: """
        tell application id "com.spotify.client"
            if player state is stopped then return {"stopped"}
            set t to current track
            return {player state as string, id of t, name of t, artist of t, album of t, duration of t, player position, artwork url of t}
        end tell
        """,
        parse: { result in
            guard result.numberOfItems >= 8 else { return nil }
            let artwork = result.string(at: 8)
            return NowPlayingInfo(
                trackID: result.string(at: 2),
                title: result.string(at: 3),
                artist: result.string(at: 4),
                album: result.string(at: 5),
                // Spotify reports duration in milliseconds.
                duration: result.double(at: 6) / 1000,
                elapsed: result.double(at: 7),
                timestamp: Date(),
                isPlaying: result.string(at: 1) == "playing",
                artworkURL: artwork.isEmpty ? nil : URL(string: artwork)
            )
        }
    )

    /// Music doesn't expose an artwork URL; `NowPlayingService` asks for the
    /// image data separately via `appleMusicArtworkScript`.
    static let appleMusic = ScriptedPlayer(
        kind: .appleMusic,
        displayName: "Music",
        bundleID: "com.apple.Music",
        notificationName: "com.apple.Music.playerInfo",
        stateScript: """
        tell application id "com.apple.Music"
            if player state is stopped then return {"stopped"}
            try
                set t to current track
                return {player state as string, persistent ID of t, name of t, artist of t, album of t, duration of t, player position}
            on error
                return {"stopped"}
            end try
        end tell
        """,
        parse: { result in
            guard result.numberOfItems >= 7 else { return nil }
            return NowPlayingInfo(
                trackID: result.string(at: 2),
                title: result.string(at: 3),
                artist: result.string(at: 4),
                album: result.string(at: 5),
                duration: result.double(at: 6),
                elapsed: result.double(at: 7),
                timestamp: Date(),
                isPlaying: result.string(at: 1) == "playing",
                artworkURL: nil
            )
        }
    )

    static let appleMusicArtworkScript = """
    tell application id "com.apple.Music"
        try
            return raw data of artwork 1 of current track
        end try
    end tell
    """
}
