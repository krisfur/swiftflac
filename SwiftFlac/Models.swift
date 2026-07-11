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
    guard let items = try? await asset.load(.commonMetadata) else { return metadata }
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
    return metadata
}
