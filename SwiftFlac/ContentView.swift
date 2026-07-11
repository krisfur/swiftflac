import SwiftUI

struct ContentView: View {
    @Environment(MusicLibrary.self) private var library
    @Environment(PlayerController.self) private var player
    @State private var selectedPlaylist: Playlist?
    @State private var showingFolderPicker = false
    @State private var showingNowPlaying = false

    var body: some View {
        NavigationSplitView {
            List(library.playlists, selection: $selectedPlaylist) { playlist in
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
                .tag(playlist)
            }
            .navigationTitle("Playlists")
            .overlay {
                if library.playlists.isEmpty {
                    ContentUnavailableView {
                        Label("No Music", systemImage: "music.note.list")
                    } description: {
                        Text("Choose a folder with music in it. Each subfolder becomes a playlist.")
                    } actions: {
                        Button("Choose Folder") { showingFolderPicker = true }
                    }
                }
            }
            .toolbar {
                ToolbarItem {
                    Button("Choose Folder", systemImage: "folder.badge.plus") {
                        showingFolderPicker = true
                    }
                }
                ToolbarItem {
                    Button("Rescan", systemImage: "arrow.clockwise") {
                        library.rescan()
                    }
                }
            }
        } detail: {
            if let selectedPlaylist {
                TrackListView(playlist: selectedPlaylist)
            } else {
                ContentUnavailableView("Select a Playlist", systemImage: "music.note.list")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if player.currentTrack != nil {
                NowPlayingBar { showingNowPlaying = true }
            }
        }
        .sheet(isPresented: $showingNowPlaying) {
            NowPlayingView()
        }
        .fileImporter(isPresented: $showingFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                library.setRootFolder(url)
                selectedPlaylist = nil
            }
        }
    }
}

struct TrackListView: View {
    @Environment(PlayerController.self) private var player
    let playlist: Playlist

    var body: some View {
        List(playlist.tracks) { track in
            Button {
                player.play(track, from: playlist)
            } label: {
                HStack {
                    Image(systemName: player.currentTrack == track ? "speaker.wave.2.fill" : "music.note")
                        .foregroundStyle(player.currentTrack == track ? Color.accentColor : Color.secondary)
                        .frame(width: 24)
                    Text(track.displayName)
                        .lineLimit(1)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .navigationTitle(playlist.name)
    }
}
