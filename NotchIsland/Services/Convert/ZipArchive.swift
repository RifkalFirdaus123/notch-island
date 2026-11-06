import Compression
import Foundation

/// Just enough ZIP support for Office files (.xlsx): write a set of entries,
/// read them back. Entries are deflated with the Compression framework,
/// whose `COMPRESSION_ZLIB` is raw DEFLATE as ZIP expects.
nonisolated enum ZipArchive {
    enum ZipError: Error {
        case notAZip
        case corrupt
        case unsupportedMethod(UInt16)
    }

    // MARK: - Writing

    static func make(_ entries: [(path: String, data: Data)]) -> Data {
        var archive = Data()
        var central = Data()

        for entry in entries {
            let name = Data(entry.path.utf8)
            let crc = crc32(entry.data)
            let deflated = deflate(entry.data)
            let (method, payload): (UInt16, Data) = deflated.map { (8, $0) } ?? (0, entry.data)
            let offset = UInt32(archive.count)

            // Bit 11: file names are UTF-8.
            let flags: UInt16 = 0x0800
            let (time, date) = dosTimestamp(Date())

            archive.append(le32: 0x0403_4B50)
            archive.append(le16: 20)
            archive.append(le16: flags)
            archive.append(le16: method)
            archive.append(le16: time)
            archive.append(le16: date)
            archive.append(le32: crc)
            archive.append(le32: UInt32(payload.count))
            archive.append(le32: UInt32(entry.data.count))
            archive.append(le16: UInt16(name.count))
            archive.append(le16: 0)
            archive.append(name)
            archive.append(payload)

            central.append(le32: 0x0201_4B50)
            central.append(le16: 20)
            central.append(le16: 20)
            central.append(le16: flags)
            central.append(le16: method)
            central.append(le16: time)
            central.append(le16: date)
            central.append(le32: crc)
            central.append(le32: UInt32(payload.count))
            central.append(le32: UInt32(entry.data.count))
            central.append(le16: UInt16(name.count))
            central.append(le16: 0) // extra
            central.append(le16: 0) // comment
            central.append(le16: 0) // disk
            central.append(le16: 0) // internal attributes
            central.append(le32: 0) // external attributes
            central.append(le32: offset)
            central.append(name)
        }

        let centralOffset = UInt32(archive.count)
        archive.append(central)
        archive.append(le32: 0x0605_4B50)
        archive.append(le16: 0)
        archive.append(le16: 0)
        archive.append(le16: UInt16(entries.count))
        archive.append(le16: UInt16(entries.count))
        archive.append(le32: UInt32(central.count))
        archive.append(le32: centralOffset)
        archive.append(le16: 0)
        return archive
    }

    // MARK: - Reading

    /// Every file in the archive, keyed by path.
    static func entries(of data: Data) throws -> [String: Data] {
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw ZipError.notAZip }

        // The end-of-central-directory record sits in the last 64 KB + 22 bytes.
        var eocd: Int?
        var index = bytes.count - 22
        let floor = max(0, bytes.count - 22 - 65_535)
        while index >= floor {
            if bytes.le32(at: index) == 0x0605_4B50 { eocd = index; break }
            index -= 1
        }
        guard let eocd else { throw ZipError.notAZip }

        let count = Int(bytes.le16(at: eocd + 10))
        var cursor = Int(bytes.le32(at: eocd + 16))
        var result: [String: Data] = [:]

        for _ in 0..<count {
            guard cursor + 46 <= bytes.count, bytes.le32(at: cursor) == 0x0201_4B50 else {
                throw ZipError.corrupt
            }
            let method = bytes.le16(at: cursor + 10)
            let compressedSize = Int(bytes.le32(at: cursor + 20))
            let size = Int(bytes.le32(at: cursor + 24))
            let nameLength = Int(bytes.le16(at: cursor + 28))
            let extraLength = Int(bytes.le16(at: cursor + 30))
            let commentLength = Int(bytes.le16(at: cursor + 32))
            let localOffset = Int(bytes.le32(at: cursor + 42))
            guard cursor + 46 + nameLength <= bytes.count else { throw ZipError.corrupt }
            let name = String(decoding: bytes[(cursor + 46)..<(cursor + 46 + nameLength)], as: UTF8.self)
            cursor += 46 + nameLength + extraLength + commentLength

            guard localOffset + 30 <= bytes.count, bytes.le32(at: localOffset) == 0x0403_4B50 else {
                throw ZipError.corrupt
            }
            let start = localOffset + 30
                + Int(bytes.le16(at: localOffset + 26))
                + Int(bytes.le16(at: localOffset + 28))
            guard start + compressedSize <= bytes.count else { throw ZipError.corrupt }
            let payload = Data(bytes[start..<(start + compressedSize)])

            switch method {
            case 0: result[name] = payload
            case 8: result[name] = try inflate(payload, size: size)
            default: throw ZipError.unsupportedMethod(method)
            }
        }
        return result
    }

    // MARK: - Helpers

    /// Raw DEFLATE, or nil when it doesn't make the data smaller.
    private static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let capacity = data.count + 1024
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { input in
                compression_encode_buffer(
                    out.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    input.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0, written < data.count else { return nil }
        return output.prefix(written)
    }

    private static func inflate(_ data: Data, size: Int) throws -> Data {
        guard size > 0 else { return Data() }
        guard !data.isEmpty else { throw ZipError.corrupt }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { input in
                compression_decode_buffer(
                    out.bindMemory(to: UInt8.self).baseAddress!, size,
                    input.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == size else { throw ZipError.corrupt }
        return output
    }

    private static let crcTable: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func dosTimestamp(_ date: Date) -> (time: UInt16, date: UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date
        )
        let time = UInt16((c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | (c.second ?? 0) / 2)
        let day = UInt16(max(0, (c.year ?? 1980) - 1980) << 9 | (c.month ?? 1) << 5 | (c.day ?? 1))
        return (time, day)
    }
}

nonisolated private extension Data {
    mutating func append(le16 value: UInt16) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    mutating func append(le32 value: UInt32) {
        append(contentsOf: (0..<4).map { UInt8((value >> ($0 * 8)) & 0xFF) })
    }
}

nonisolated private extension [UInt8] {
    func le16(at i: Int) -> UInt16 {
        UInt16(self[i]) | UInt16(self[i + 1]) << 8
    }

    func le32(at i: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(self[i + $1]) << ($1 * 8) }
    }
}
