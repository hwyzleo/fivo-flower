import Foundation

/// 最小 ZIP 读写实现（仅 Store 方式），用于 `.fivoflower` 备份。
/// 只读取本 App 生成的归档，遇到压缩或加密条目会明确拒绝。
enum SimpleZip {
    struct Entry {
        var path: String
        var data: Data
    }

    enum ZipError: LocalizedError {
        case invalidArchive
        case unsupportedCompression
        case unsafePath(String)
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .invalidArchive: return "ZIP 归档损坏"
            case .unsupportedCompression: return "备份使用了不支持的压缩方式"
            case .unsafePath(let path): return "备份包含不安全的路径：\(path)"
            case .tooLarge: return "备份内容超出安全大小限制"
            }
        }
    }

    private static let maxTotalSize = 2 * 1024 * 1024 * 1024
    private static let maxEntries = 100_000

    // MARK: - Write

    static func archive(entries: [Entry]) -> Data {
        var output = Data()
        var central = Data()
        let (dosTime, dosDate) = dosDateTime(Date())

        for entry in entries {
            let nameData = Data(entry.path.utf8)
            let crc = crc32(entry.data)
            let offset = UInt32(output.count)

            output.append(le32(0x04034b50))
            output.append(le16(20))
            output.append(le16(0x0800))
            output.append(le16(0))
            output.append(le16(dosTime))
            output.append(le16(dosDate))
            output.append(le32(crc))
            output.append(le32(UInt32(entry.data.count)))
            output.append(le32(UInt32(entry.data.count)))
            output.append(le16(UInt16(nameData.count)))
            output.append(le16(0))
            output.append(nameData)
            output.append(entry.data)

            central.append(le32(0x02014b50))
            central.append(le16(20))
            central.append(le16(20))
            central.append(le16(0x0800))
            central.append(le16(0))
            central.append(le16(dosTime))
            central.append(le16(dosDate))
            central.append(le32(crc))
            central.append(le32(UInt32(entry.data.count)))
            central.append(le32(UInt32(entry.data.count)))
            central.append(le16(UInt16(nameData.count)))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le32(0))
            central.append(le32(offset))
            central.append(nameData)
        }

        let centralOffset = UInt32(output.count)
        output.append(central)
        output.append(le32(0x06054b50))
        output.append(le16(0))
        output.append(le16(0))
        output.append(le16(UInt16(min(entries.count, 0xFFFF))))
        output.append(le16(UInt16(min(entries.count, 0xFFFF))))
        output.append(le32(UInt32(central.count)))
        output.append(le32(centralOffset))
        output.append(le16(0))
        return output
    }

    // MARK: - Read

    static func extract(data: Data) throws -> [String: Data] {
        guard data.count > 22 else { throw ZipError.invalidArchive }
        guard let eocdOffset = findEOCD(in: data) else { throw ZipError.invalidArchive }
        let totalEntries = Int(readU16(data, eocdOffset + 10))
        let centralOffset = Int(readU32(data, eocdOffset + 16))
        guard totalEntries <= maxEntries else { throw ZipError.tooLarge }
        guard centralOffset >= 0, centralOffset < data.count else { throw ZipError.invalidArchive }

        var result: [String: Data] = [:]
        var cursor = centralOffset
        var totalSize = 0

        for _ in 0..<totalEntries {
            guard cursor + 46 <= data.count, readU32(data, cursor) == 0x02014b50 else {
                throw ZipError.invalidArchive
            }
            let method = readU16(data, cursor + 10)
            let expectedCRC = readU32(data, cursor + 16)
            let compressedSize = Int(readU32(data, cursor + 20))
            let uncompressedSize = Int(readU32(data, cursor + 24))
            let nameLength = Int(readU16(data, cursor + 28))
            let extraLength = Int(readU16(data, cursor + 30))
            let commentLength = Int(readU16(data, cursor + 32))
            let localOffset = Int(readU32(data, cursor + 42))
            guard cursor + 46 + nameLength <= data.count else { throw ZipError.invalidArchive }
            let nameData = data.subdata(in: (cursor + 46)..<(cursor + 46 + nameLength))
            guard let path = String(data: nameData, encoding: .utf8) else { throw ZipError.invalidArchive }
            guard isSafePath(path) else { throw ZipError.unsafePath(path) }
            guard method == 0 else { throw ZipError.unsupportedCompression }
            guard compressedSize == uncompressedSize else { throw ZipError.unsupportedCompression }
            totalSize += uncompressedSize
            guard totalSize <= maxTotalSize else { throw ZipError.tooLarge }

            guard localOffset + 30 <= data.count, readU32(data, localOffset) == 0x04034b50 else {
                throw ZipError.invalidArchive
            }
            let localNameLength = Int(readU16(data, localOffset + 26))
            let localExtraLength = Int(readU16(data, localOffset + 28))
            let dataStart = localOffset + 30 + localNameLength + localExtraLength
            guard dataStart + compressedSize <= data.count else { throw ZipError.invalidArchive }
            let payload = data.subdata(in: dataStart..<(dataStart + compressedSize))
            guard crc32(payload) == expectedCRC else { throw ZipError.invalidArchive }
            result[path] = payload
            cursor += 46 + nameLength + extraLength + commentLength
        }
        return result
    }

    static func isSafePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    // MARK: - Helpers

    private static func findEOCD(in data: Data) -> Int? {
        let maxComment = 65535
        let start = max(0, data.count - maxComment - 22)
        var index = data.count - 22
        while index >= start {
            if readU32(data, index) == 0x06054b50 {
                return index
            }
            index -= 1
        }
        return nil
    }

    private static func readU16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { return 0 }
        let slice = data.subdata(in: offset..<(offset + 2))
        return slice.withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
    }

    private static func readU32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        let slice = data.subdata(in: offset..<(offset + 4))
        return slice.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    }

    private static func le16(_ value: UInt16) -> Data {
        var value = value.littleEndian
        return Data(bytes: &value, count: 2)
    }

    private static func le32(_ value: UInt32) -> Data {
        var value = value.littleEndian
        return Data(bytes: &value, count: 4)
    }

    private static func dosDateTime(_ date: Date) -> (UInt16, UInt16) {
        let calendar = FivoDate.defaultCalendar
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, c.year ?? 2024) - 1980
        let month = max(1, c.month ?? 1)
        let day = max(1, c.day ?? 1)
        let hour = max(0, c.hour ?? 0)
        let minute = max(0, c.minute ?? 0)
        let second = max(0, c.second ?? 0) / 2
        let time = UInt16((hour << 11) | (minute << 5) | second)
        let dateValue = UInt16((year << 9) | (month << 5) | day)
        return (time, dateValue)
    }

    private static let crcTable: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var crc = UInt32(index)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (0xEDB88320 ^ (crc >> 1)) : (crc >> 1)
            }
            return crc
        }
    }()

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = crcTable[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}
