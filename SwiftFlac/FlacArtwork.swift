import Foundation

/// Reads embedded artwork from a FLAC file's PICTURE metadata blocks.
/// AVFoundation does not surface FLAC PICTURE blocks through common
/// metadata, so this parses the container format directly.
enum FlacArtwork {
    static func pictureData(in url: URL) -> Data? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        guard let magic = try? file.read(upToCount: 4), magic == Data("fLaC".utf8) else { return nil }

        var fallback: Data?
        while true {
            guard let header = try? file.read(upToCount: 4), header.count == 4 else { break }
            let isLast = header[0] & 0x80 != 0
            let blockType = header[0] & 0x7F
            let length = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
            if blockType == 6 {
                guard let block = try? file.read(upToCount: length), block.count == length else { break }
                if let picture = parsePicture(block) {
                    if picture.type == 3 { return picture.data }  // front cover wins
                    if fallback == nil { fallback = picture.data }
                }
            } else {
                guard let offset = try? file.offset(),
                      (try? file.seek(toOffset: offset + UInt64(length))) != nil else { break }
            }
            if isLast { break }
        }
        return fallback
    }

    private static func parsePicture(_ block: Data) -> (type: UInt32, data: Data)? {
        var cursor = 0
        func readUInt32() -> UInt32? {
            guard cursor + 4 <= block.count else { return nil }
            let value = block[cursor..<(cursor + 4)].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            cursor += 4
            return value
        }
        func skip(_ count: Int) -> Bool {
            guard cursor + count <= block.count else { return false }
            cursor += count
            return true
        }
        guard let pictureType = readUInt32(),
              let mimeLength = readUInt32(), skip(Int(mimeLength)),
              let descriptionLength = readUInt32(), skip(Int(descriptionLength)),
              skip(16),  // width, height, colour depth, palette size
              let dataLength = readUInt32(),
              cursor + Int(dataLength) <= block.count
        else { return nil }
        return (pictureType, block.subdata(in: cursor..<(cursor + Int(dataLength))))
    }
}
