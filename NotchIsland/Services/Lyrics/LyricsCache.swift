import CryptoKit
import Foundation

/// Lyrics stored locally per song, including "not found" so we don't ask
/// again for songs without synced lyrics (retried after a week).
nonisolated struct LyricsCache: Sendable {
    private struct Entry: Codable {
        var syncedLyrics: String?
        var fetchedAt: Date
    }

    static let notFoundRetryInterval: TimeInterval = 7 * 24 * 60 * 60

    let directory: URL

    static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("NotchIsland/Lyrics", isDirectory: true)
    }

    /// `.some(nil)` means cached as not found; `nil` means not cached.
    func lookup(_ key: String) -> String?? {
        guard let data = try? Data(contentsOf: fileURL(for: key)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data)
        else { return nil }
        if entry.syncedLyrics == nil, Date().timeIntervalSince(entry.fetchedAt) > Self.notFoundRetryInterval {
            return nil
        }
        return .some(entry.syncedLyrics)
    }

    func store(_ lyrics: String?, for key: String) {
        let entry = Entry(syncedLyrics: lyrics, fetchedAt: Date())
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    private func fileURL(for key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(hash).json")
    }
}
