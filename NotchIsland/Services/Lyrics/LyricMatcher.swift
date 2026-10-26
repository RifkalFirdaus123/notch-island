import Foundation

/// What we ask LRCLIB for, cleaned up from the player's metadata.
nonisolated struct LyricQuery: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval?
    /// YouTube durations include intros/outros, so allow more slack.
    var durationTolerance: TimeInterval

    var cacheKey: String {
        let seconds = duration.map { String(Int($0.rounded())) } ?? "?"
        return [LyricMatcher.normalize(artist), LyricMatcher.normalize(title), seconds].joined(separator: "|")
    }
}

/// One LRCLIB search result.
nonisolated struct LyricCandidate: Equatable, Sendable, Decodable {
    var trackName: String
    var artistName: String
    var albumName: String?
    var duration: Double?
    var syncedLyrics: String?
}

nonisolated enum LyricMatcher {
    /// Words in brackets that only describe the upload, not the song.
    private static let noiseWords = [
        "official", "video", "audio", "lyric", "lyrics", "mv", "m/v", "hd", "4k", "visualizer",
        "remaster", "remastered", "live", "color coded", "explicit", "clip", "music video",
    ]

    // MARK: - Building queries

    static func query(title: String, artist: String, album: String, duration: TimeInterval?, fromVideo: Bool) -> LyricQuery {
        guard fromVideo else {
            return LyricQuery(title: title, artist: artist, album: album, duration: duration, durationTolerance: 3)
        }
        var cleanTitle = stripNoise(title)
        var cleanArtist = cleanChannelName(artist)

        // Most music uploads are titled "Artist - Song".
        if let dash = cleanTitle.range(of: " - ") ?? cleanTitle.range(of: " – ") ?? cleanTitle.range(of: " — ") {
            let left = cleanTitle[..<dash.lowerBound].trimmingCharacters(in: .whitespaces)
            let right = cleanTitle[dash.upperBound...].trimmingCharacters(in: .whitespaces)
            if !left.isEmpty && !right.isEmpty {
                cleanArtist = left
                cleanTitle = right
            }
        }
        return LyricQuery(
            title: stripFeaturing(cleanTitle), artist: cleanArtist, album: album,
            duration: duration, durationTolerance: 8
        )
    }

    /// Removes "(Official Video)", "[MV]", "| Lyrics" style decorations.
    static func stripNoise(_ title: String) -> String {
        var result = title
        let pattern = #"[\(\[【]([^\)\]】]*)[\)\]】]"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed()
            for match in matches {
                guard let whole = Range(match.range, in: result), let inner = Range(match.range(at: 1), in: result)
                else { continue }
                let content = result[inner].lowercased()
                if noiseWords.contains(where: { content.contains($0) }) {
                    result.removeSubrange(whole)
                }
            }
        }
        // Anything after a pipe is usually channel/promo text.
        if let pipe = result.firstIndex(of: "|") { result = String(result[..<pipe]) }
        return result.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }

    static func stripFeaturing(_ title: String) -> String {
        let pattern = #"\s*[\(\[]?\s*\b(feat\.?|ft\.?|featuring)\s.*$"#
        return title.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
    }

    /// "ArtistVEVO" → "Artist", "Artist - Topic" → "Artist".
    static func cleanChannelName(_ channel: String) -> String {
        var name = channel.trimmingCharacters(in: .whitespaces)
        for suffix in [" - Topic", "VEVO", " Official", "Official"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        return name.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Matching

    /// Lowercased, accents removed, brackets and punctuation dropped.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        let withoutBrackets = folded.replacingOccurrences(of: #"[\(\[].*?[\)\]]"#, with: " ", options: .regularExpression)
        let words = withoutBrackets
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return words.joined(separator: " ")
    }

    /// 1 for equal, 0.8 when one contains the other, else word overlap.
    static func similarity(_ a: String, _ b: String) -> Double {
        let left = normalize(a)
        let right = normalize(b)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        if left == right { return 1 }
        if left.contains(right) || right.contains(left) { return 0.8 }
        let leftWords = Set(left.split(separator: " "))
        let rightWords = Set(right.split(separator: " "))
        return Double(leftWords.intersection(rightWords).count) / Double(leftWords.union(rightWords).count)
    }

    /// Best candidate with synced lyrics, or nil if none is close enough.
    static func bestMatch(for query: LyricQuery, in candidates: [LyricCandidate]) -> LyricCandidate? {
        var best: (candidate: LyricCandidate, score: Double)?
        for candidate in candidates {
            guard let synced = candidate.syncedLyrics, !synced.isEmpty else { continue }

            var durationPenalty = 0.0
            if let wanted = query.duration, let actual = candidate.duration {
                let difference = abs(wanted - actual)
                if difference > query.durationTolerance { continue }
                durationPenalty = difference / query.durationTolerance * 0.2
            }
            let titleScore = similarity(query.title, candidate.trackName)
            guard titleScore >= 0.5 else { continue }
            // Unknown artist (e.g. untitled upload): rely on title and duration.
            let artistScore = query.artist.isEmpty ? 0.5 : similarity(query.artist, candidate.artistName)
            let score = titleScore * 0.6 + artistScore * 0.4 - durationPenalty

            if score > (best?.score ?? 0.45) { best = (candidate, score) }
        }
        return best?.candidate
    }
}
