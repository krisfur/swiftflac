import SwiftUI

/// Fixed search field that sits between the navigation title and the
/// content, so nothing can overlap or hide it.
struct SearchField: View {
    @Binding var text: String
    var prompt: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                #if os(iOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                #endif
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.bottom, 6)
    }
}

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
    @State private var searchText = ""

    private var filteredArtists: [Artist] {
        guard !searchText.isEmpty else { return library.artists }
        return library.artists.filter { $0.name.localizedStandardContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $searchText, prompt: "Artist")
            List(filteredArtists) { artist in
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
            .overlay {
                if filteredArtists.isEmpty, !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .miniBarClearance()
        }
        .background(AppBackground())
        .navigationTitle("Artists")
        .optionsToolbar()
    }
}

struct AlbumsView: View {
    @Environment(MusicLibrary.self) private var library
    @State private var searchText = ""

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 16)]

    // Album names first; if nothing matches, fall back to the artist so
    // an artist's name pulls up their albums.
    private var filteredAlbums: [Album] {
        guard !searchText.isEmpty else { return library.albums }
        let byName = library.albums.filter { $0.name.localizedStandardContains(searchText) }
        if !byName.isEmpty { return byName }
        return library.albums.filter { $0.artist?.localizedStandardContains(searchText) == true }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $searchText, prompt: "Album or Artist")
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(filteredAlbums) { album in
                        NavigationLink(value: LibraryDestination.album(album)) {
                            AlbumCell(album: album)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .overlay {
                if filteredAlbums.isEmpty, !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .miniBarClearance()
        }
        .background(AppBackground())
        .navigationTitle("Albums")
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
            await loadMetadata(from: url, includeArtwork: true).artworkData
        }.value
        if let data {
            cache[url] = data
        } else {
            misses.insert(url)
        }
        return data
    }
}
