import Testing
@testable import NotchIsland

struct LyricMatchingTests {
    // MARK: - Normalizing

    @Test func normalizeFoldsCaseAccentsAndPunctuation() {
        #expect(LyricMatcher.normalize("Beyoncé – Halo!") == "beyonce halo")
        #expect(LyricMatcher.normalize("Song (Remastered 2011)") == "song")
    }

    @Test func similarityScores() {
        #expect(LyricMatcher.similarity("Halo", "halo") == 1)
        #expect(LyricMatcher.similarity("Halo", "Halo Live") == 0.8)
        #expect(LyricMatcher.similarity("Yellow", "Clocks") == 0)
        #expect(LyricMatcher.similarity("", "Clocks") == 0)
    }

    // MARK: - Cleaning YouTube metadata

    @Test func stripsVideoDecorations() {
        #expect(LyricMatcher.stripNoise("Yellow (Official Video)") == "Yellow")
        #expect(LyricMatcher.stripNoise("Dynamite [MV]") == "Dynamite")
        #expect(LyricMatcher.stripNoise("Song (Lyrics) | Best Hits 2024") == "Song")
        // Not noise: part of the real title.
        #expect(LyricMatcher.stripNoise("Love (Part 2)") == "Love (Part 2)")
    }

    @Test func stripsFeaturing() {
        #expect(LyricMatcher.stripFeaturing("Stay (feat. Justin Bieber)") == "Stay")
        #expect(LyricMatcher.stripFeaturing("Stay ft. Justin Bieber") == "Stay")
        #expect(LyricMatcher.stripFeaturing("Feather") == "Feather")
        #expect(LyricMatcher.stripFeaturing("Left Behind") == "Left Behind")
    }

    @Test func cleansChannelNames() {
        #expect(LyricMatcher.cleanChannelName("ColdplayVEVO") == "Coldplay")
        #expect(LyricMatcher.cleanChannelName("Tulus - Topic") == "Tulus")
        #expect(LyricMatcher.cleanChannelName("Raisa") == "Raisa")
    }

    @Test func splitsArtistFromVideoTitle() {
        let query = LyricMatcher.query(
            title: "Coldplay - Yellow (Official Video)", artist: "ColdplayVEVO", album: "",
            duration: 269, fromVideo: true
        )
        #expect(query.artist == "Coldplay")
        #expect(query.title == "Yellow")
        #expect(query.durationTolerance > 3)
    }

    @Test func keepsMusicAppMetadataAsIs() {
        let query = LyricMatcher.query(
            title: "Yellow", artist: "Coldplay", album: "Parachutes", duration: 266, fromVideo: false
        )
        #expect(query == LyricQuery(title: "Yellow", artist: "Coldplay", album: "Parachutes", duration: 266, durationTolerance: 3))
    }

    @Test func cacheKeyIgnoresCaseAndAccents() {
        let a = LyricQuery(title: "Halo", artist: "Beyoncé", album: "", duration: 261.4, durationTolerance: 3)
        let b = LyricQuery(title: "HALO", artist: "beyonce", album: "Other", duration: 260.6, durationTolerance: 8)
        #expect(a.cacheKey == b.cacheKey)
    }

    // MARK: - Picking a candidate

    private func candidate(_ title: String, _ artist: String, _ duration: Double?, synced: Bool = true) -> LyricCandidate {
        LyricCandidate(
            trackName: title, artistName: artist, albumName: nil, duration: duration,
            syncedLyrics: synced ? "[00:01.00]\(title)" : nil
        )
    }

    @Test func prefersClosestDuration() {
        let query = LyricQuery(title: "Yellow", artist: "Coldplay", album: "", duration: 266, durationTolerance: 3)
        let match = LyricMatcher.bestMatch(for: query, in: [
            candidate("Yellow", "Coldplay", 268.5),
            candidate("Yellow", "Coldplay", 266.2),
        ])
        #expect(match?.duration == 266.2)
    }

    @Test func rejectsDurationOutsideTolerance() {
        let query = LyricQuery(title: "Yellow", artist: "Coldplay", album: "", duration: 266, durationTolerance: 3)
        #expect(LyricMatcher.bestMatch(for: query, in: [candidate("Yellow", "Coldplay", 300)]) == nil)
    }

    @Test func skipsCandidatesWithoutSyncedLyrics() {
        let query = LyricQuery(title: "Yellow", artist: "Coldplay", album: "", duration: 266, durationTolerance: 3)
        #expect(LyricMatcher.bestMatch(for: query, in: [candidate("Yellow", "Coldplay", 266, synced: false)]) == nil)
    }

    @Test func rejectsDifferentSong() {
        let query = LyricQuery(title: "Yellow", artist: "Coldplay", album: "", duration: 266, durationTolerance: 3)
        #expect(LyricMatcher.bestMatch(for: query, in: [candidate("Clocks", "Coldplay", 266)]) == nil)
    }

    @Test func prefersMatchingArtist() {
        let query = LyricQuery(title: "Halo", artist: "Beyoncé", album: "", duration: 261, durationTolerance: 3)
        let match = LyricMatcher.bestMatch(for: query, in: [
            candidate("Halo", "Some Cover Band", 261),
            candidate("Halo", "Beyonce", 262),
        ])
        #expect(match?.artistName == "Beyonce")
    }

    @Test func acceptsMissingDurations() {
        let query = LyricQuery(title: "Halo", artist: "Beyoncé", album: "", duration: nil, durationTolerance: 3)
        #expect(LyricMatcher.bestMatch(for: query, in: [candidate("Halo", "Beyoncé", 261)]) != nil)
    }
}
