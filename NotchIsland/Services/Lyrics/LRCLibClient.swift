import Foundation

/// Fetches synced lyrics; swapped for a fake in tests.
protocol LyricsProviding: Sendable {
    /// LRC text, or nil when the song has no synced lyrics.
    /// Throws on network errors so they aren't cached as "not found".
    func syncedLyrics(for query: LyricQuery) async throws -> String?
}

/// https://lrclib.net — free, no API key. Only title, artist, album and
/// duration are sent.
nonisolated struct LRCLibClient: LyricsProviding {
    private static let baseURL = URL(string: "https://lrclib.net/api")!
    private static let userAgent = "NotchIsland/0.1 (personal macOS app)"

    var session: URLSession = .shared

    func syncedLyrics(for query: LyricQuery) async throws -> String? {
        // The exact lookup needs an artist and duration; it's the most precise.
        if !query.artist.isEmpty, let duration = query.duration {
            var items = [
                URLQueryItem(name: "track_name", value: query.title),
                URLQueryItem(name: "artist_name", value: query.artist),
                URLQueryItem(name: "duration", value: String(Int(duration.rounded()))),
            ]
            if !query.album.isEmpty { items.append(URLQueryItem(name: "album_name", value: query.album)) }
            if let exact: LyricCandidate = try await request("get", items),
               let synced = exact.syncedLyrics, !synced.isEmpty {
                return synced
            }
        }

        var items = [URLQueryItem(name: "track_name", value: query.title)]
        if !query.artist.isEmpty { items.append(URLQueryItem(name: "artist_name", value: query.artist)) }
        let results: [LyricCandidate] = try await request("search", items) ?? []
        return LyricMatcher.bestMatch(for: query, in: results)?.syncedLyrics
    }

    /// Decoded body, or nil on 404.
    private func request<T: Decodable>(_ path: String, _ items: [URLQueryItem]) async throws -> T? {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = items
        var request = URLRequest(url: components.url!, timeoutInterval: 10)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
