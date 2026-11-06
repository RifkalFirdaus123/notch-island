import CryptoKit
import Foundation

/// What a piece of copied text looks like, so the clipboard can offer the
/// right one-click action.
nonisolated enum ClipKind: String, Equatable, Codable, Sendable {
    case url
    case json
    case jwt
    case uuid
    case color
    case timestamp
    case base64
    case number
    case text

    var symbol: String {
        switch self {
        case .url: "link"
        case .json: "curlybraces"
        case .jwt: "key.horizontal"
        case .uuid: "number"
        case .color: "paintpalette"
        case .timestamp: "clock"
        case .base64: "doc.text.magnifyingglass"
        case .number: "textformat.123"
        case .text: "text.alignleft"
        }
    }

    var label: String {
        switch self {
        case .url: "URL"
        case .json: "JSON"
        case .jwt: "JWT"
        case .uuid: "UUID"
        case .color: "HEX"
        case .timestamp: "TIME"
        case .base64: "B64"
        case .number: "NUM"
        case .text: "TXT"
        }
    }
}

nonisolated enum HashAlgorithm: String, CaseIterable, Identifiable, Sendable {
    case md5 = "MD5"
    case sha1 = "SHA-1"
    case sha256 = "SHA-256"
    case sha512 = "SHA-512"

    var id: String { rawValue }
}

/// Small text transforms for the Dev tab. Pure functions, so they're easy to test.
nonisolated enum DevToolkit {
    // MARK: Detection

    static func kind(of raw: String) -> ClipKind {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .text }

        if !text.contains(where: \.isWhitespace) {
            if let url = URL(string: text), let scheme = url.scheme?.lowercased(),
               ["http", "https", "ftp", "ws", "wss", "file"].contains(scheme), url.host != nil || scheme == "file" {
                return .url
            }
            if UUID(uuidString: text) != nil { return .uuid }
            if isHexColor(text) { return .color }
            if decodeJWT(text) != nil { return .jwt }
            if timestampDate(text) != nil { return .timestamp }
            if Double(text) != nil { return .number }
        }
        if (text.hasPrefix("{") || text.hasPrefix("[")), formatJSON(text) != nil { return .json }
        if looksLikeBase64(text) { return .base64 }
        return .text
    }

    static func isHexColor(_ text: String) -> Bool {
        guard text.hasPrefix("#") else { return false }
        let hex = text.dropFirst()
        return [3, 4, 6, 8].contains(hex.count) && hex.allSatisfy(\.isHexDigit)
    }

    /// RGBA components (0–1) of a #RGB, #RGBA, #RRGGBB or #RRGGBBAA color.
    static func rgba(fromHex text: String) -> (r: Double, g: Double, b: Double, a: Double)? {
        guard isHexColor(text) else { return nil }
        var hex = String(text.dropFirst())
        if hex.count <= 4 { hex = hex.map { "\($0)\($0)" }.joined() }
        if hex.count == 6 { hex += "FF" }
        guard let value = UInt64(hex, radix: 16) else { return nil }
        return (
            Double((value >> 24) & 0xFF) / 255,
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }

    /// A Unix timestamp in seconds (10 digits) or milliseconds (13 digits)
    /// between 2001 and 2100. Shorter numbers are just numbers.
    static func timestampDate(_ text: String) -> Date? {
        guard text.count == 10 || text.count == 13, text.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Double(text)
        else { return nil }
        let seconds = text.count == 13 ? value / 1000 : value
        guard seconds > 978_307_200, seconds < 4_102_444_800 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func looksLikeBase64(_ text: String) -> Bool {
        guard text.count >= 16, !text.contains(where: \.isWhitespace) else { return false }
        guard let decoded = base64Decode(text) else { return false }
        // Only call it base64 if it decodes to readable text.
        return !decoded.isEmpty && decoded.unicodeScalars.allSatisfy {
            $0.properties.isWhitespace || $0.properties.generalCategory != .control
        }
    }

    // MARK: Transforms

    static func base64Encode(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    /// Accepts standard and URL-safe base64, with or without padding.
    static func base64Decode(_ text: String) -> String? {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder == 1 { return nil }
        if remainder > 0 { normalized += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: normalized) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func urlEncode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    static func urlDecode(_ text: String) -> String? {
        text.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
    }

    static func formatJSON(_ text: String) -> String? {
        reserializeJSON(text, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    static func minifyJSON(_ text: String) -> String? {
        reserializeJSON(text, options: [.withoutEscapingSlashes])
    }

    private static func reserializeJSON(_ text: String, options: JSONSerialization.WritingOptions) -> String? {
        guard let data = text.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              object is [Any] || object is [String: Any],
              let output = try? JSONSerialization.data(withJSONObject: object, options: options)
        else { return nil }
        return String(data: output, encoding: .utf8)
    }

    /// Header and payload of a JWT as pretty JSON. The signature isn't checked.
    static func decodeJWT(_ text: String) -> String? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].hasPrefix("eyJ"),
              let header = base64Decode(String(parts[0])).flatMap(formatJSON),
              let payload = base64Decode(String(parts[1])).flatMap(formatJSON)
        else { return nil }
        return header + "\n" + payload
    }

    static func timestampDescription(_ date: Date) -> String {
        let iso = date.formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false).timeSeparator(.colon))
        let local = date.formatted(date: .abbreviated, time: .standard)
        return "\(local)  ·  \(iso)Z"
    }

    // MARK: Hashing

    static func hash(_ text: String, with algorithm: HashAlgorithm) -> String {
        hash(Data(text.utf8), with: algorithm)
    }

    static func hash(_ data: Data, with algorithm: HashAlgorithm) -> String {
        switch algorithm {
        case .md5: Insecure.MD5.hash(data: data).hexString
        case .sha1: Insecure.SHA1.hash(data: data).hexString
        case .sha256: SHA256.hash(data: data).hexString
        case .sha512: SHA512.hash(data: data).hexString
        }
    }
}

nonisolated private extension Digest {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
