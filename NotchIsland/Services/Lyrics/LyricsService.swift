import Combine
import Foundation

/// Publishes the lyric line for the current playback position. Instead of a
/// fast timer it sleeps until the next line is due, and reschedules whenever
/// the player reports a change (pause, seek, new track).
final class LyricsService: ObservableObject {
    /// Nil when paused, between songs, or without synced lyrics.
    @Published private(set) var currentLine: String?

    /// Show each line slightly early so it doesn't feel late.
    private static let lead: TimeInterval = 0.25

    private let nowPlaying: NowPlayingService
    private let provider: LyricsProviding
    private let cache: LyricsCache

    private var lines: [LyricLine] = []
    private var loadedKey: String?
    private var loadTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(
        nowPlaying: NowPlayingService,
        provider: LyricsProviding = LRCLibClient(),
        cache: LyricsCache = LyricsCache(directory: LyricsCache.defaultDirectory)
    ) {
        self.nowPlaying = nowPlaying
        self.provider = provider
        self.cache = cache
    }

    private var isEnabled: Bool { UserDefaults.standard.bool(forKey: SettingsKeys.featureLyrics) }

    func start() {
        nowPlaying.$info
            .combineLatest(nowPlaying.$sourceName)
            .receive(on: RunLoop.main)
            .sink { [weak self] info, source in self?.handle(info, source: source) }
            .store(in: &cancellables)

        // Hop to main before any closure runs: this is posted on whatever
        // thread wrote the defaults (e.g. CoreML when the camera starts).
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .map { _ in UserDefaults.standard.bool(forKey: SettingsKeys.featureLyrics) }
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                self.handle(self.nowPlaying.info, source: self.nowPlaying.sourceName)
            }
            .store(in: &cancellables)
    }

    private func handle(_ info: NowPlayingInfo?, source: String?) {
        guard isEnabled, let info else {
            loadTask?.cancel()
            tickTask?.cancel()
            loadedKey = nil
            lines = []
            setLine(nil)
            return
        }

        let isVideo = BrowserSource.supported.contains { $0.name == source }
        let query = LyricMatcher.query(
            title: info.title, artist: info.artist, album: info.album,
            duration: info.duration, fromVideo: isVideo
        )
        if query.cacheKey != loadedKey {
            loadedKey = query.cacheKey
            lines = []
            setLine(nil)
            tickTask?.cancel()
            load(query)
        } else {
            reschedule()
        }
    }

    private func load(_ query: LyricQuery) {
        loadTask?.cancel()
        loadTask = Task { [weak self, provider, cache] in
            let lrc: String?
            if let cached = cache.lookup(query.cacheKey) {
                lrc = cached
            } else {
                do {
                    lrc = try await provider.syncedLyrics(for: query)
                    cache.store(lrc, for: query.cacheKey)
                } catch {
                    // Network trouble: try again next time this song comes up.
                    lrc = nil
                }
            }
            guard !Task.isCancelled, let self, self.loadedKey == query.cacheKey else { return }
            self.lines = lrc.map(LRCParser.parse) ?? []
            self.reschedule()
        }
    }

    private func reschedule() {
        tickTask?.cancel()
        guard let info = nowPlaying.info, info.isPlaying, !lines.isEmpty else {
            setLine(nil)
            return
        }
        tickTask = Task { [weak self] in
            while !Task.isCancelled, let self {
                let position = info.position() + Self.lead
                let index = LRCParser.lineIndex(at: position, in: self.lines)
                let text = index.map { self.lines[$0].text } ?? ""
                self.setLine(text.isEmpty ? nil : text)

                let nextIndex = (index ?? -1) + 1
                guard nextIndex < self.lines.count else { return }
                let wait = self.lines[nextIndex].time - position
                try? await Task.sleep(for: .seconds(max(0.05, wait)))
            }
        }
    }

    private func setLine(_ line: String?) {
        if line != currentLine { currentLine = line }
    }
}
