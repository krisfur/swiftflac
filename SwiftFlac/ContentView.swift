import SwiftUI

struct ContentView: View {
    @Environment(MusicLibrary.self) private var library
    @Environment(PlayerController.self) private var player
    @State private var selectedPlaylist: Playlist?
    @State private var showingFolderPicker = false
    @State private var showingNowPlaying = false
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue

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
            #if os(iOS)
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            #endif
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
            #if os(iOS)
            .toolbar {
                ToolbarItem {
                    optionsMenu
                }
            }
            #endif
        } detail: {
            Group {
                if let selectedPlaylist {
                    TrackListView(playlist: selectedPlaylist)
                } else {
                    ContentUnavailableView("Select a Playlist", systemImage: "music.note.list")
                }
            }
            .background(AppBackground())
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if player.currentTrack != nil {
                nowPlayingBar
            }
        }
        #if os(macOS)
        // The sidebar toolbar is too narrow and pushes items into the »
        // overflow menu, so the options menu lives in the window toolbar.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                optionsMenu
            }
        }
        // Swallow the popover-dismissing click so it can't hit a track
        // row or a transport button underneath.
        .overlay {
            if showingNowPlaying {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { showingNowPlaying = false }
            }
        }
        #else
        .sheet(isPresented: $showingNowPlaying) {
            NowPlayingView()
        }
        #endif
        .preferredColorScheme(Appearance(rawValue: appearanceRaw)?.colorScheme)
        .fileImporter(isPresented: $showingFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                library.setRootFolder(url)
                selectedPlaylist = nil
            }
        }
    }

    private var optionsMenu: some View {
        Menu {
            Button("Choose Folder…", systemImage: "folder.badge.plus") {
                showingFolderPicker = true
            }
            Button("Rescan Library", systemImage: "arrow.clockwise") {
                library.rescan()
            }
            Picker("Appearance", selection: $appearanceRaw) {
                ForEach(Appearance.allCases, id: \.rawValue) { appearance in
                    Text(appearance.label).tag(appearance.rawValue)
                }
            }
            .pickerStyle(.menu)
        } label: {
            Label("Options", systemImage: "ellipsis.circle")
        }
    }

    // On macOS a popover dismisses when clicking anywhere else, which a
    // sheet there does not; iOS keeps the swipeable sheet.
    @ViewBuilder
    private var nowPlayingBar: some View {
        #if os(macOS)
        NowPlayingBar { showingNowPlaying = true }
            .popover(isPresented: $showingNowPlaying, arrowEdge: .bottom) {
                NowPlayingView()
            }
        #else
        NowPlayingBar { showingNowPlaying = true }
        #endif
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
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle(playlist.name)
    }
}
