import Combine
import Foundation

/// Publishes the mood of the current song for the lyric strip. The mood
/// comes from a manual choice if the user made one, otherwise from the
/// song's genre and title. Always neutral while mood styling is off.
final class LyricMoodService: ObservableObject {
    @Published private(set) var mood: LyricMood = .neutral
    /// True when `mood` was picked by hand for this song.
    @Published private(set) var isOverridden = false

    private let nowPlaying: NowPlayingService
    private let provider: GenreProviding
    private let featuresProvider: AudioFeaturesProviding
    /// Genres looked up this session, by song key; nil means not found.
    private var genres: [String: String?] = [:]
    /// Audio analyses by song key; found ones are kept between launches.
    private var features: [String: AudioFeatures?] = [:]
    private static let featuresCacheKey = "moodFeaturesCache"
    private static let featuresCacheLimit = 300
    private var songKey: String?
    /// The current song's raw title, and the cleaned title and artist to search for.
    private var songTitle = ""
    private var searchTitle = ""
    private var searchArtist = ""
    /// Song key the last genre lookup was started for.
    private var lookedUpKey: String?
    private var lookupTask: Task<Void, Never>?
    private var featuresLookedUpKey: String?
    private var featuresTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(
        nowPlaying: NowPlayingService,
        provider: GenreProviding = ITunesGenreClient(),
        featuresProvider: AudioFeaturesProviding = ReccoBeatsClient()
    ) {
        self.nowPlaying = nowPlaying
        self.provider = provider
        self.featuresProvider = featuresProvider
        for (key, data) in Self.storedFeatures {
            features[key] = .some(AudioFeatures(valence: data.valence, energy: data.energy, tempo: data.tempo))
        }
    }

    private static var storedFeatures: [String: AudioFeatures] {
        guard let data = UserDefaults.standard.data(forKey: featuresCacheKey) else { return [:] }
        return (try? JSONDecoder().decode([String: AudioFeatures].self, from: data)) ?? [:]
    }

    private func remember(_ found: AudioFeatures, for key: String) {
        var stored = Self.storedFeatures
        if stored.count >= Self.featuresCacheLimit { stored.removeAll() }
        stored[key] = found
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.featuresCacheKey)
        }
    }

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: SettingsKeys.lyricMoodStyle) }

    func start() {
        nowPlaying.$info
            .combineLatest(nowPlaying.$sourceName)
            .receive(on: RunLoop.main)
            .sink { [weak self] info, source in self?.handle(info, source: source) }
            .store(in: &cancellables)

        // The on/off switch and manual choices live in UserDefaults.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    /// Picks a mood by hand for the current song; nil goes back to automatic.
    func setOverride(_ mood: LyricMood?) {
        guard let songKey else { return }
        var overrides = Self.overrides
        overrides[songKey] = mood?.rawValue
        UserDefaults.standard.set(overrides, forKey: SettingsKeys.lyricMoodOverrides)
        refresh()
    }

    private static var overrides: [String: String] {
        UserDefaults.standard.dictionary(forKey: SettingsKeys.lyricMoodOverrides) as? [String: String] ?? [:]
    }

    private func handle(_ info: NowPlayingInfo?, source: String?) {
        guard let info, !info.isAd else {
            songKey = nil
            lookupTask?.cancel()
            featuresTask?.cancel()
            refresh()
            return
        }
        // Same cleanup as the lyrics lookup, so YouTube titles work too.
        let isVideo = BrowserSource.supported.contains { $0.name == source }
        let query = LyricMatcher.query(
            title: info.title, artist: info.artist, album: info.album,
            duration: info.duration, fromVideo: isVideo
        )
        let key = [LyricMatcher.normalize(query.artist), LyricMatcher.normalize(query.title)].joined(separator: "|")
        guard key != songKey else { return }
        songKey = key
        songTitle = info.title
        searchTitle = query.title
        searchArtist = query.artist
        lookupTask?.cancel()
        featuresTask?.cancel()
        refresh()
    }

    private func lookUpGenre(for key: String) {
        lookedUpKey = key
        lookupTask?.cancel()
        lookupTask = Task { [weak self, provider, title = searchTitle, artist = searchArtist] in
            // Network trouble isn't remembered, so a later play tries again.
            guard let genre = try? await provider.genre(title: title, artist: artist),
                  !Task.isCancelled, let self
            else { return }
            self.genres[key] = .some(genre)
            self.refresh()
        }
    }

    private func lookUpFeatures(for key: String) {
        featuresLookedUpKey = key
        featuresTask?.cancel()
        featuresTask = Task { [weak self, featuresProvider, title = searchTitle, artist = searchArtist] in
            // Network trouble isn't remembered, so a later play tries again.
            guard let found = try? await featuresProvider.features(title: title, artist: artist),
                  !Task.isCancelled, let self
            else { return }
            self.features[key] = .some(found)
            self.remember(found, for: key)
            self.refresh()
        }
    }

    private func refresh() {
        guard isEnabled, let songKey else {
            set(.neutral, overridden: false)
            return
        }
        if let raw = Self.overrides[songKey], let manual = LyricMood(rawValue: raw) {
            set(manual, overridden: true)
            return
        }
        // Once per song, also when switched on while a song was already playing.
        if genres[songKey] == nil, lookedUpKey != songKey { lookUpGenre(for: songKey) }
        if features[songKey] == nil, featuresLookedUpKey != songKey { lookUpFeatures(for: songKey) }
        let genre = genres[songKey] ?? nil
        let analysed = features[songKey] ?? nil
        set(LyricMoodClassifier.mood(genre: genre, title: songTitle, features: analysed), overridden: false)
    }

    private func set(_ newMood: LyricMood, overridden: Bool) {
        if newMood != mood { mood = newMood }
        if overridden != isOverridden { isOverridden = overridden }
    }
}
