import Foundation

/// Reads tags and embedded artwork from a FLAC file's metadata blocks.
/// AVFoundation does not surface FLAC VORBIS_COMMENT or PICTURE blocks
/// through common metadata, so this parses the container format directly.
enum FlacMetadata {
    static func read(from url: URL) -> TrackMetadata {
        var metadata = TrackMetadata()
        guard let file = try? FileHandle(forReadingFrom: url) else { return metadata }
        defer { try? file.close() }
        guard let magic = try? file.read(upToCount: 4), magic == Data("fLaC".utf8) else { return metadata }

        var fallbackArtwork: Data?
        loop: while true {
            guard let header = try? file.read(upToCount: 4), header.count == 4 else { break }
            let isLast = header[0] & 0x80 != 0
            let blockType = header[0] & 0x7F
            let length = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
            switch blockType {
            case 4:  // VORBIS_COMMENT
                guard let block = try? file.read(upToCount: length), block.count == length else { break loop }
                parseVorbisComments(block, into: &metadata)
            case 6:  // PICTURE
                guard let block = try? file.read(upToCount: length), block.count == length else { break loop }
                if let picture = parsePicture(block) {
                    if picture.type == 3 { metadata.artworkData = picture.data }  // front cover wins
                    else if fallbackArtwork == nil { fallbackArtwork = picture.data }
                }
            default:
                guard let offset = try? file.offset(),
                      (try? file.seek(toOffset: offset + UInt64(length))) != nil else { break loop }
            }
            if isLast { break }
        }
        if metadata.artworkData == nil { metadata.artworkData = fallbackArtwork }
        return metadata
    }

    private static func parseVorbisComments(_ block: Data, into metadata: inout TrackMetadata) {
        var cursor = 0
        func readLE32() -> Int? {
            guard cursor + 4 <= block.count else { return nil }
            let value = Int(block[cursor]) | Int(block[cursor + 1]) << 8
                | Int(block[cursor + 2]) << 16 | Int(block[cursor + 3]) << 24
            cursor += 4
            return value
        }
        guard let vendorLength = readLE32(), cursor + vendorLength <= block.count else { return }
        cursor += vendorLength
        guard let commentCount = readLE32() else { return }
        for _ in 0..<commentCount {
            guard let length = readLE32(), cursor + length <= block.count else { return }
            defer { cursor += length }
            guard let comment = String(data: block[cursor..<(cursor + length)], encoding: .utf8),
                  let separator = comment.firstIndex(of: "=") else { continue }
            let value = String(comment[comment.index(after: separator)...])
            guard !value.isEmpty else { continue }
            switch comment[..<separator].uppercased() {
            case "TITLE": metadata.title = metadata.title ?? value
            case "ARTIST": metadata.artist = metadata.artist ?? value
            case "ALBUM": metadata.album = metadata.album ?? value
            default: break
            }
        }
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
