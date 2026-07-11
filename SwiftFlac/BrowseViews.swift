import SwiftUI

struct FoldersView: View {
    @Environment(MusicLibrary.self) private var library

    var body: some View {
        List(library.playlists) { playlist in
            NavigationLink(value: LibraryDestination.playlist(playlist)) {
                Label {
                    VStack(alignment: .leading) {
                        Text(playlist.name)
                        Text("\(playlist.tracks.count) tracks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "folder.fill")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Folders")
        .miniBarClearance()
        .optionsToolbar()
    }
}

struct ArtistsView: View {
    @Environment(MusicLibrary.self) private var library

    var body: some View {
        List(library.artists) { artist in
            NavigationLink(value: LibraryDestination.artist(artist)) {
                Label {
                    VStack(alignment: .leading) {
                        Text(artist.name)
                        Text("\(artist.tracks.count) tracks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "music.mic")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Artists")
        .miniBarClearance()
        .optionsToolbar()
    }
}

struct AlbumsView: View {
    @Environment(MusicLibrary.self) private var library

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(library.albums) { album in
                    NavigationLink(value: LibraryDestination.album(album)) {
                        AlbumCell(album: album)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(AppBackground())
        .navigationTitle("Albums")
        .miniBarClearance()
        .optionsToolbar()
    }
}

struct AlbumCell: View {
    let album: Album
    @State private var artworkData: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image = artworkImage(from: artworkData) {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            Rectangle()
                                .fill(.quaternary)
                            Image(systemName: "music.note")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(album.name)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Text(album.artist ?? "Unknown Artist")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .task(id: album.id) {
            artworkData = await ArtworkStore.shared.artwork(for: album.tracks.first)
        }
    }
}

/// Caches embedded artwork so grid cells don't re-read files while scrolling.
@MainActor
final class ArtworkStore {
    static let shared = ArtworkStore()

    private var cache: [URL: Data] = [:]
    private var misses: Set<URL> = []

    func artwork(for track: Track?) async -> Data? {
        guard let url = track?.url else { return nil }
        if let cached = cache[url] { return cached }
        if misses.contains(url) { return nil }
        let data = await Task.detached(priority: .utility) {
            FlacMetadata.read(from: url).artworkData
        }.value
        if let data {
            cache[url] = data
        } else {
            misses.insert(url)
        }
        return data
    }
}
