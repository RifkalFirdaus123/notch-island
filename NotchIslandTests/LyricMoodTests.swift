import Testing
@testable import NotchIsland

struct LyricMoodTests {
    @Test(arguments: [
        ("Metal", LyricMood.intense),
        ("Hard Rock", .intense),
        ("Pop Punk", .intense),
        ("Jazz", .calm),
        ("Singer/Songwriter", .calm),
        ("R&B/Soul", .calm),
        ("Alternative", .calm),
        ("Indie Rock", .intense),
        ("Pop", .upbeat),
        ("Indonesian Pop", .upbeat),
        ("Dance", .upbeat),
        ("Spoken Word", .neutral),
    ])
    func moodFromGenre(genre: String, expected: LyricMood) {
        #expect(LyricMoodClassifier.mood(genre: genre, title: "Song") == expected)
    }

    @Test func titleBeatsGenre() {
        #expect(LyricMoodClassifier.mood(genre: "Rock", title: "Song (Acoustic Version)") == .calm)
        #expect(LyricMoodClassifier.mood(genre: "Jazz", title: "Song - Remix") == .upbeat)
        #expect(LyricMoodClassifier.mood(genre: nil, title: "Lagu Akustik") == .calm)
    }

    @Test func unknownGenreIsNeutral() {
        #expect(LyricMoodClassifier.mood(genre: nil, title: "Lampu Merah") == .neutral)
        #expect(LyricMoodClassifier.mood(genre: "", title: "Lampu Merah") == .neutral)
    }

    @Test func picksMatchingITunesResult() {
        let results = [
            ITunesGenreClient.Result(trackName: "Lampu Merah", artistName: "Someone Else", primaryGenreName: "Dangdut"),
            ITunesGenreClient.Result(trackName: "Lampu Merah", artistName: "The Lantis", primaryGenreName: "Pop"),
            ITunesGenreClient.Result(trackName: "Other Song", artistName: "The Lantis", primaryGenreName: "Rock"),
        ]
        let best = ITunesGenreClient.bestMatch(title: "Lampu Merah", artist: "The Lantis", in: results)
        #expect(best?.primaryGenreName == "Pop")
    }

    @Test func rejectsUnrelatedITunesResults() {
        let results = [ITunesGenreClient.Result(trackName: "Enter Sandman", artistName: "Metallica", primaryGenreName: "Metal")]
        #expect(ITunesGenreClient.bestMatch(title: "Lampu Merah", artist: "The Lantis", in: results) == nil)
    }
}
