import SwiftUI

enum BrowseMode: String, CaseIterable, Identifiable {
    case albums, artists, folders, allTracks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .albums: "Albums"
        case .artists: "Artists"
        case .folders: "Folders"
        case .allTracks: "All Tracks"
        }
    }

    var icon: String {
        switch self {
        case .albums: "square.stack"
        case .artists: "music.mic"
        case .folders: "folder"
        case .allTracks: "music.note.list"
        }
    }
}

struct ContentView: View {
    @Environment(MusicLibrary.self) private var library
    @Environment(PlayerController.self) private var player
    // iPhone starts on the Library list itself; macOS needs a selection
    // because its detail pane is always visible.
    #if os(macOS)
    @State private var mode: BrowseMode? = .folders
    #else
    @State private var mode: BrowseMode?
    #endif
    @State private var showingFolderPicker = false
    @State private var showingNowPlaying = false
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue

    var body: some View {
        NavigationSplitView {
            List(BrowseMode.allCases, selection: $mode) { mode in
                Label(mode.title, systemImage: mode.icon)
                    .tag(mode)
            }
            .navigationTitle("Library")
            #if os(iOS)
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .toolbar {
                ToolbarItem {
                    optionsMenu
                }
            }
            #endif
        } detail: {
            NavigationStack {
                detailRoot
                    .navigationDestination(for: Playlist.self) { playlist in
                        TrackListView(title: playlist.name, tracks: playlist.tracks)
                    }
                    .navigationDestination(for: Album.self) { album in
                        TrackListView(title: album.name, tracks: album.tracks)
                    }
                    .navigationDestination(for: Artist.self) { artist in
                        TrackListView(title: artist.name, tracks: artist.tracks, showsArtist: false)
                    }
            }
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
            }
        }
    }

    @ViewBuilder
    private var detailRoot: some View {
        if library.allTracks.isEmpty {
            if library.isScanning {
                ProgressView()
            } else {
                ContentUnavailableView {
                    Label("No Music", systemImage: "music.note.list")
                } description: {
                    Text("Choose a folder with music in it. Each subfolder becomes a playlist.")
                } actions: {
                    Button("Choose Folder") { showingFolderPicker = true }
                }
            }
        } else {
            switch mode {
            case .albums:
                AlbumsView()
            case .artists:
                ArtistsView()
            case .folders:
                FoldersView()
            case .allTracks:
                TrackListView(title: "All Tracks", tracks: library.allTracks)
            case nil:
                ContentUnavailableView("Select a Category", systemImage: "music.note")
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
    let title: String
    let tracks: [Track]
    var showsArtist = true

    var body: some View {
        List(tracks) { track in
            Button {
                player.play(track, in: tracks)
            } label: {
                TrackRow(track: track, isPlaying: player.currentTrack == track, showsArtist: showsArtist)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle(title)
    }
}

struct TrackRow: View {
    let track: Track
    let isPlaying: Bool
    let showsArtist: Bool
    @State private var artworkData: Data?

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(data: artworkData, size: 40, cornerRadius: 6)
                .overlay {
                    if isPlaying {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.black.opacity(0.45))
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.footnote)
                            .foregroundStyle(.white)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle)
                    .foregroundStyle(isPlaying ? Color.accentColor : Color.primary)
                    .lineLimit(1)
                if showsArtist, let artist = track.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .task(id: track.url) {
            artworkData = await ArtworkStore.shared.artwork(for: track)
        }
    }
}
