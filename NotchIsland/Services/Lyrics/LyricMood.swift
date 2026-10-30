import AppKit
import SwiftUI

/// The feel of a song, used to color and style the lyric strip.
enum LyricMood: String, CaseIterable, Identifiable, Sendable {
    /// Plain white, as when mood styling is off.
    case neutral
    /// Slow, soft songs: blue gradient, light rounded font.
    case calm
    /// Rock, metal and other hard songs: red gradient, rough font.
    case intense
    /// Upbeat, cheerful songs: yellow gradient, heavy rounded font.
    case upbeat

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .neutral: "Neutral"
        case .calm: "Calm"
        case .intense: "Hard"
        case .upbeat: "Upbeat"
        }
    }

    var symbol: String {
        switch self {
        case .neutral: "circle"
        case .calm: "moon.fill"
        case .intense: "flame.fill"
        case .upbeat: "sun.max.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .neutral: [.white, .white]
        case .calm: [Color(red: 0.45, green: 0.75, blue: 1), Color(red: 0.7, green: 0.6, blue: 1)]
        case .intense: [Color(red: 1, green: 0.25, blue: 0.2), Color(red: 1, green: 0.6, blue: 0.15)]
        case .upbeat: [Color(red: 1, green: 0.9, blue: 0.25), Color(red: 1, green: 0.62, blue: 0.2)]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    /// AppKit font, so the strip width can be measured with the same font.
    var font: NSFont {
        let size: CGFloat = 12
        switch self {
        case .neutral:
            return .systemFont(ofSize: size, weight: .semibold)
        case .calm:
            return Self.rounded(.systemFont(ofSize: size, weight: .regular))
        case .intense:
            // Chalky, rough letters; ships with macOS.
            return NSFont(name: "Chalkduster", size: size - 1) ?? .systemFont(ofSize: size, weight: .black)
        case .upbeat:
            return Self.rounded(.systemFont(ofSize: size, weight: .heavy))
        }
    }

    private static func rounded(_ font: NSFont) -> NSFont {
        font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: font.pointSize) } ?? font
    }
}

/// Guesses a mood from the store genre and words in the title.
nonisolated enum LyricMoodClassifier {
    /// Upload titles often say how the version sounds; they win over genre.
    private static let titleHints: [(words: [String], mood: LyricMood)] = [
        (["acoustic", "akustik", "unplugged", "slow version", "ballad", "piano version", "lullaby", "lofi", "lo-fi", "slowed"], .calm),
        (["remix", "sped up", "nightcore", "edm", "party", "dance version", "koplo"], .upbeat),
        (["metal version", "rock version", "screamo"], .intense),
    ]

    /// Checked in order, so "Pop Punk" is hard and "Pop R&B" is calm.
    /// Plain "Alternative" and "Indie" lean mellow; their loud side is
    /// usually tagged Rock or Punk, which matches first.
    private static let genreHints: [(words: [String], mood: LyricMood)] = [
        (["metal", "rock", "punk", "hardcore", "grunge", "emo", "industrial"], .intense),
        (["jazz", "blues", "soul", "r&b", "acoustic", "singer/songwriter", "classical", "ambient",
          "new age", "folk", "alternative", "indie", "lounge", "easy listening", "chill", "lo-fi", "country", "soundtrack"], .calm),
        (["pop", "dance", "electronic", "edm", "house", "techno", "trance", "hip-hop", "hip hop", "rap",
          "reggae", "latin", "disco", "funk", "dangdut", "ska", "k-pop", "j-pop"], .upbeat),
    ]

    static func mood(genre: String?, title: String) -> LyricMood {
        let lowerTitle = title.lowercased()
        for hint in titleHints where hint.words.contains(where: lowerTitle.contains) {
            return hint.mood
        }
        guard let genre = genre?.lowercased(), !genre.isEmpty else { return .neutral }
        for hint in genreHints where hint.words.contains(where: genre.contains) {
            return hint.mood
        }
        return .neutral
    }
}

/// Looks up a song's genre; swapped for a fake in tests.
protocol GenreProviding: Sendable {
    /// The store's primary genre, or nil when the song isn't found.
    func genre(title: String, artist: String) async throws -> String?
}

/// iTunes Search API — free, no API key. Only the title and artist are sent.
nonisolated struct ITunesGenreClient: GenreProviding {
    private struct Response: Decodable {
        var results: [Result]
    }

    struct Result: Decodable, Equatable {
        var trackName: String
        var artistName: String
        var primaryGenreName: String?
    }

    var session: URLSession = .shared

    func genre(title: String, artist: String) async throws -> String? {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: [artist, title].filter { !$0.isEmpty }.joined(separator: " ")),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "10"),
        ]
        guard let url = components.url else { return nil }
        let (data, response) = try await session.data(for: URLRequest(url: url, timeoutInterval: 10))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
        let results = try JSONDecoder().decode(Response.self, from: data).results
        return Self.bestMatch(title: title, artist: artist, in: results)?.primaryGenreName
    }

    /// The closest result by title and artist, or nil if none is close enough.
    static func bestMatch(title: String, artist: String, in results: [Result]) -> Result? {
        var best: (result: Result, score: Double)?
        for result in results {
            let titleScore = LyricMatcher.similarity(title, result.trackName)
            guard titleScore >= 0.5 else { continue }
            let artistScore = artist.isEmpty ? 0.5 : LyricMatcher.similarity(artist, result.artistName)
            let score = titleScore * 0.6 + artistScore * 0.4
            if score > (best?.score ?? 0.6) { best = (result, score) }
        }
        return best?.result
    }
}
