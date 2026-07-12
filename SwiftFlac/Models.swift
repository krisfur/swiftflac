import Foundation
import AVFoundation

struct Track: Identifiable, Hashable {
    let url: URL
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var trackNumber: Int?
    var discNumber: Int?

    var id: URL { url }
    var displayTitle: String { title ?? url.deletingPathExtension().lastPathComponent }
}

struct Playlist: Identifiable, Hashable {
    let name: String
    let folderURL: URL
    let tracks: [Track]

    var id: URL { folderURL }
}

struct Album: Identifiable, Hashable {
    let name: String
    let artist: String?
    let tracks: [Track]

    var id: String { "\(artist ?? "")|\(name)" }
}

struct Artist: Identifiable, Hashable {
    let name: String
    let tracks: [Track]

    var id: String { name }
}

struct TrackMetadata: Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var trackNumber: Int?
    var discNumber: Int?
    var artworkData: Data?
}

func loadMetadata(for track: Track) async -> TrackMetadata {
    await loadMetadata(from: track.url, includeArtwork: true)
}

func loadMetadata(from url: URL, includeArtwork: Bool) async -> TrackMetadata {
    var metadata = TrackMetadata()
    let asset = AVURLAsset(url: url)
    if let items = try? await asset.load(.commonMetadata) {
        for item in items {
            switch item.commonKey {
            case .commonKeyTitle:
                metadata.title = try? await item.load(.stringValue)
            case .commonKeyArtist:
                metadata.artist = try? await item.load(.stringValue)
            case .commonKeyAlbumName:
                metadata.album = try? await item.load(.stringValue)
            case .commonKeyArtwork:
                if includeArtwork {
                    metadata.artworkData = try? await item.load(.dataValue)
                }
            default:
                break
            }
        }
    }
    // Album artist and track/disc numbers are not "common" keys; check
    // the iTunes and ID3 tags directly.
    if let items = try? await asset.load(.metadata) {
        for identifier in [AVMetadataIdentifier.iTunesMetadataAlbumArtist, .id3MetadataBand] {
            if let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier).first,
               let value = try? await item.load(.stringValue) {
                metadata.albumArtist = value
                break
            }
        }
        for identifier in [AVMetadataIdentifier.iTunesMetadataTrackNumber, .id3MetadataTrackNumber] {
            if let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier).first,
               let value = await loadNumber(from: item) {
                metadata.trackNumber = value
                break
            }
        }
        for identifier in [AVMetadataIdentifier.iTunesMetadataDiscNumber, .id3MetadataPartOfASet] {
            if let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier).first,
               let value = await loadNumber(from: item) {
                metadata.discNumber = value
                break
            }
        }
    }
    if url.pathExtension.lowercased() == "flac" {
        let flac = FlacMetadata.read(from: url, readArtwork: includeArtwork)
        metadata.title = metadata.title ?? flac.title
        metadata.artist = metadata.artist ?? flac.artist
        metadata.album = metadata.album ?? flac.album
        metadata.albumArtist = metadata.albumArtist ?? flac.albumArtist
        metadata.trackNumber = metadata.trackNumber ?? flac.trackNumber
        metadata.discNumber = metadata.discNumber ?? flac.discNumber
        metadata.artworkData = metadata.artworkData ?? flac.artworkData
    }
    return metadata
}

/// Reads a numeric tag that may arrive as a number, a "3/12" style string
/// (ID3), or a packed big-endian data blob (iTunes trkn/disk atoms).
private func loadNumber(from item: AVMetadataItem) async -> Int? {
    if let number = try? await item.load(.numberValue) {
        return number.intValue
    }
    if let string = try? await item.load(.stringValue),
       let leading = string.split(separator: "/").first, let value = Int(leading) {
        return value
    }
    if let data = try? await item.load(.dataValue), data.count >= 4 {
        return Int(data[data.startIndex + 2]) << 8 | Int(data[data.startIndex + 3])
    }
    return nil
}
