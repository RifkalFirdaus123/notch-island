import Foundation

/// What a song sounds like, from audio analysis. Each value is 0...1
/// except `tempo`, in beats per minute.
nonisolated struct AudioFeatures: Equatable, Sendable, Codable {
    /// Musical positiveness: high is cheerful, low is sad or angry.
    var valence: Double
    /// Intensity and activity: high is fast and loud.
    var energy: Double
    var tempo: Double
}

/// Looks up audio features for a song; swapped for a fake in tests.
protocol AudioFeaturesProviding: Sendable {
    /// Nil when the song can't be found or analysed.
    func features(title: String, artist: String) async throws -> AudioFeatures?
}

/// Analyses the song's 30 second iTunes preview with ReccoBeats, which
/// replaces Spotify's closed audio features endpoint. No account or key is
/// needed. Only the preview audio is uploaded, never anything about the user.
nonisolated struct ReccoBeatsClient: AudioFeaturesProviding {
    private static let endpoint = URL(string: "https://api.reccobeats.com/v1/analysis/audio-features")!
    /// ReccoBeats rejects uploads larger than this.
    private static let maxUploadBytes = 5 * 1024 * 1024

    private struct Response: Decodable {
        var valence: Double
        var energy: Double
        var tempo: Double
    }

    var session: URLSession = .shared

    func features(title: String, artist: String) async throws -> AudioFeatures? {
        let search = ITunesGenreClient(session: session)
        guard let preview = try await search.bestResult(title: title, artist: artist)?.previewUrl else { return nil }

        let (audio, audioResponse) = try await session.data(for: URLRequest(url: preview, timeoutInterval: 15))
        guard (audioResponse as? HTTPURLResponse)?.statusCode == 200, audio.count <= Self.maxUploadBytes else {
            return nil
        }

        let boundary = "notchisland-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"audioFile\"; filename=\"preview.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n".utf8))
        body.append(audio)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: Self.endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return AudioFeatures(valence: decoded.valence, energy: decoded.energy, tempo: decoded.tempo)
    }
}
