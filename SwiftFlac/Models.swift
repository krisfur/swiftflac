import Foundation
import AVFoundation

struct Track: Identifiable, Hashable {
    let url: URL
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?

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
    // Album artist is not a "common" key; check the iTunes and ID3 tags.
    if let items = try? await asset.load(.metadata) {
        for identifier in [AVMetadataIdentifier.iTunesMetadataAlbumArtist, .id3MetadataBand] {
            if let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier).first,
               let value = try? await item.load(.stringValue) {
                metadata.albumArtist = value
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
        metadata.artworkData = metadata.artworkData ?? flac.artworkData
    }
    return metadata
}
