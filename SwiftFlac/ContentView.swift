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

enum LibraryDestination: Hashable {
    case playlist(Playlist)
    case album(Album)
    case artist(Artist)
    case nowPlaying
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
    @State private var path: [LibraryDestination] = []
    @State private var savedPaths: [BrowseMode: [LibraryDestination]] = [:]
    @State private var forwardStack: [LibraryDestination] = []
    @State private var isRestoringPath = false
    @State private var showingFolderPicker = false
    @State private var showingNowPlaying = false
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var forwardMode: BrowseMode?
    // Where the current song was played from, so the now-playing screen
    // can always swipe back to that list.
    @State private var playbackOrigin: (mode: BrowseMode?, path: [LibraryDestination])?
    #endif

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
            // Swipe left on the Library list to return to the category
            // you swiped back out of.
            .simultaneousGesture(
                DragGesture(minimumDistance: 25)
                    .onEnded { value in
                        if value.translation.width < -70, abs(value.translation.height) < 50,
                           let forwardMode {
                            mode = forwardMode
                        }
                    }
            )
            #endif
            .optionsToolbar()
        } detail: {
            NavigationStack(path: $path) {
                detailRoot
                    .navigationDestination(for: LibraryDestination.self) { destination in
                        switch destination {
                        case .playlist(let playlist):
                            TrackListView(title: playlist.name, tracks: playlist.tracks, onPlay: playFromList)
                        case .album(let album):
                            TrackListView(title: album.name, tracks: album.tracks, onPlay: playFromList)
                        case .artist(let artist):
                            TrackListView(title: artist.name, tracks: artist.tracks, showsArtist: false, onPlay: playFromList)
                        case .nowPlaying:
                            NowPlayingView()
                        }
                    }
            }
            #if os(iOS)
            // Swipe left to re-enter the screen you just swiped back out of;
            // swipe right at a category root to go all the way back to the
            // Library list (the system swipe only pops within the stack).
            .simultaneousGesture(
                DragGesture(minimumDistance: 25)
                    .onEnded { value in
                        guard abs(value.translation.height) < 50 else { return }
                        if value.translation.width < -70 {
                            goForward()
                        } else if value.translation.width > 70, path.isEmpty,
                                  horizontalSizeClass == .compact {
                            forwardMode = mode
                            mode = nil
                        }
                    }
            )
            #endif
        }
        .onChange(of: mode) { oldMode, newMode in
            #if os(iOS)
            if newMode != nil { forwardMode = nil }
            #endif
            if let oldMode { savedPaths[oldMode] = path }
            let restored = newMode.flatMap { savedPaths[$0] } ?? []
            forwardStack = []
            if restored != path {
                isRestoringPath = true
                path = restored
            }
        }
        .onChange(of: path) { oldPath, newPath in
            if isRestoringPath {
                isRestoringPath = false
                return
            }
            if newPath.count < oldPath.count {
                forwardStack.append(contentsOf: oldPath[newPath.count...].reversed())
            } else if newPath.count > oldPath.count {
                forwardStack = []
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if player.currentTrack != nil, path.last != .nowPlaying {
                nowPlayingBar
            }
        }
        #if os(macOS)
        // The sidebar toolbar is too narrow and pushes items into the »
        // overflow menu, so the options menu lives in the window toolbar.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                OptionsMenu(showingFolderPicker: $showingFolderPicker)
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
        #endif
        .preferredColorScheme(Appearance(rawValue: appearanceRaw)?.colorScheme)
        .fileImporter(isPresented: $showingFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                library.setRootFolder(url)
            }
        }
    }

    private func goForward() {
        guard let next = forwardStack.last else { return }
        forwardStack.removeLast()
        isRestoringPath = true
        path.append(next)
    }

    /// Called when a track is picked from a list: remembers that list as
    /// the playback origin, then shows the now-playing screen.
    private func playFromList() {
        #if os(iOS)
        playbackOrigin = (mode, path)
        #endif
        openNowPlaying()
    }

    /// On iOS this navigates to the dedicated now-playing screen, restoring
    /// the list the song was played from underneath it so a back swipe
    /// returns there; macOS keeps its popover instead.
    private func openNowPlaying() {
        #if os(iOS)
        guard path.last != .nowPlaying else { return }
        let origin = playbackOrigin ?? (mode ?? .allTracks, [])
        if mode != origin.mode { mode = origin.mode }
        // Defer the push one cycle so a mode change's path restoration
        // (onChange) cannot overwrite it.
        Task { @MainActor in
            guard path.last != .nowPlaying else { return }
            isRestoringPath = true
            path = origin.path + [.nowPlaying]
        }
        #endif
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
                TrackListView(title: "All Tracks", tracks: library.allTracks, onPlay: playFromList)
            case nil:
                ContentUnavailableView("Select a Category", systemImage: "music.note")
            }
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
        NowPlayingBar { openNowPlaying() }
        #endif
    }
}

struct OptionsMenu: View {
    @Environment(MusicLibrary.self) private var library
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @Binding var showingFolderPicker: Bool

    var body: some View {
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
}

#if os(iOS)
// Every screen carries its own options menu so it stays reachable
// anywhere in the navigation stack.
private struct OptionsToolbarModifier: ViewModifier {
    @Environment(MusicLibrary.self) private var library
    @State private var showingFolderPicker = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem {
                    OptionsMenu(showingFolderPicker: $showingFolderPicker)
                }
            }
            .fileImporter(isPresented: $showingFolderPicker, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    library.setRootFolder(url)
                }
            }
    }
}
#endif

extension View {
    @ViewBuilder
    func optionsToolbar() -> some View {
        #if os(iOS)
        modifier(OptionsToolbarModifier())
        #else
        self
        #endif
    }
}

struct TrackListView: View {
    @Environment(PlayerController.self) private var player
    let title: String
    let tracks: [Track]
    var showsArtist = true
    var onPlay: () -> Void = {}

    var body: some View {
        List(tracks) { track in
            Button {
                player.play(track, in: tracks)
                onPlay()
            } label: {
                TrackRow(track: track, isPlaying: player.currentTrack == track, showsArtist: showsArtist)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle(title)
        .optionsToolbar()
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
