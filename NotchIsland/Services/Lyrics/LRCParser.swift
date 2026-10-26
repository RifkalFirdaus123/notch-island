import Foundation

nonisolated struct LyricLine: Equatable, Sendable {
    /// Seconds from the start of the track.
    let time: TimeInterval
    /// Empty for instrumental gaps.
    let text: String
}

/// Parses LRC: `[mm:ss.xx]text` lines, several timestamps per line,
/// `[offset:±ms]`, and ignores metadata tags like `[ar:…]`.
nonisolated enum LRCParser {
    static func parse(_ lrc: String) -> [LyricLine] {
        var offset: TimeInterval = 0
        var entries: [(time: TimeInterval, order: Int, text: String)] = []

        for rawLine in lrc.components(separatedBy: .newlines) {
            var rest = Substring(rawLine.trimmingCharacters(in: .whitespaces))
            var times: [TimeInterval] = []

            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let time = parseTimestamp(tag) {
                    times.append(time)
                } else if tag.lowercased().hasPrefix("offset:") {
                    let value = tag.dropFirst("offset:".count).trimmingCharacters(in: .whitespaces)
                    offset = (Double(value) ?? 0) / 1000
                }
                rest = rest[rest.index(after: close)...]
            }

            let text = rest.trimmingCharacters(in: .whitespaces)
            for time in times {
                entries.append((time, entries.count, text))
            }
        }

        // A positive offset shows lyrics earlier. Sort by time, keeping file
        // order for equal times.
        return entries
            .sorted { ($0.time, $0.order) < ($1.time, $1.order) }
            .map { LyricLine(time: max(0, $0.time - offset), text: $0.text) }
    }

    /// `mm:ss`, `mm:ss.xx`, `mm:ss.xxx` or `mm:ss:xx`.
    static func parseTimestamp(_ tag: Substring) -> TimeInterval? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              parts[0].allSatisfy(\.isNumber), !parts[0].isEmpty,
              let minutes = Double(parts[0])
        else { return nil }

        var secondsText = String(parts[1])
        if parts.count == 3 {
            guard parts[2].allSatisfy(\.isNumber) else { return nil }
            secondsText += "." + parts[2]
        }
        guard secondsText.first?.isNumber == true, let seconds = Double(secondsText) else { return nil }
        return minutes * 60 + seconds
    }

    /// Index of the line showing at `time`, or nil before the first line.
    static func lineIndex(at time: TimeInterval, in lines: [LyricLine]) -> Int? {
        var low = 0
        var high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].time <= time { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? nil : low - 1
    }
}
