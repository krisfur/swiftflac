import Foundation
import AVFoundation

struct Track: Identifiable, Hashable {
    let url: URL

    var id: URL { url }
    var displayName: String { url.deletingPathExtension().lastPathComponent }
}

struct Playlist: Identifiable, Hashable {
    let name: String
    let folderURL: URL
    let tracks: [Track]

    var id: URL { folderURL }
}

struct TrackMetadata: Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var artworkData: Data?
}

func loadMetadata(for track: Track) async -> TrackMetadata {
    var metadata = TrackMetadata()
    let asset = AVURLAsset(url: track.url)
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
                metadata.artworkData = try? await item.load(.dataValue)
            default:
                break
            }
        }
    }
    if track.url.pathExtension.lowercased() == "flac" {
        let flac = FlacMetadata.read(from: track.url)
        metadata.title = metadata.title ?? flac.title
        metadata.artist = metadata.artist ?? flac.artist
        metadata.album = metadata.album ?? flac.album
        metadata.artworkData = metadata.artworkData ?? flac.artworkData
    }
    return metadata
}
