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

/// Lets deeply nested views (e.g. the now-playing screen) push a library
/// destination onto the detail stack.
private struct LibraryNavigateKey: EnvironmentKey {
    static let defaultValue: (LibraryDestination) -> Void = { _ in }
}

extension EnvironmentValues {
    var libraryNavigate: (LibraryDestination) -> Void {
        get { self[LibraryNavigateKey.self] }
        set { self[LibraryNavigateKey.self] = newValue }
    }
}

#if os(iOS)
/// Installs a single window-level, direction-gated pan recognizer that
/// drives forward navigation. Window-level because pushed NavigationStack
/// screens live in UIKit hosting layers that SwiftUI-attached gestures
/// cannot see into; velocity-gated so it never begins for rightward drags
/// (the system back swipe) or vertical ones (scrolling); simultaneous so
/// it observes without stealing.
private struct ForwardSwipeInstaller: UIViewRepresentable {
    let isEnabled: () -> Bool
    let onForward: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> InstallerView {
        let view = InstallerView()
        view.isUserInteractionEnabled = false
        let coordinator = context.coordinator
        view.onWindow = { window in
            guard coordinator.recognizer == nil else { return }
            let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handle(_:)))
            pan.delegate = coordinator
            pan.maximumNumberOfTouches = 1
            window.addGestureRecognizer(pan)
            coordinator.recognizer = pan
        }
        return view
    }

    func updateUIView(_ view: InstallerView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onForward = onForward
    }

    static func dismantleUIView(_ view: InstallerView, coordinator: Coordinator) {
        if let recognizer = coordinator.recognizer {
            recognizer.view?.removeGestureRecognizer(recognizer)
        }
    }

    final class InstallerView: UIView {
        var onWindow: ((UIWindow) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window {
                onWindow?(window)
            }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEnabled: () -> Bool = { false }
        var onForward: () -> Void = {}
        weak var recognizer: UIPanGestureRecognizer?

        @objc func handle(_ pan: UIPanGestureRecognizer) {
            guard pan.state == .ended, let view = pan.view else { return }
            let translation = pan.translation(in: view)
            if translation.x < -60, abs(translation.y) < 80 {
                onForward()
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard isEnabled(),
                  let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else { return false }
            let velocity = pan.velocity(in: view)
            return velocity.x < 0 && abs(velocity.x) > abs(velocity.y) * 1.5
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
#endif

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
    @State private var lastForwardPush = Date.distantPast
    // Set by the navigation gestures so their mode changes keep the forward
    // history; picking a category by hand clears it.
    @State private var preserveForwardStack = false
    @State private var hasRestoredNavigation = false

    private static let navModeKey = "navMode"
    private static let navPathKey = "navPath"
    private static let navForwardKey = "navForward"
    private static let navOriginModeKey = "navOriginMode"
    private static let navOriginPathKey = "navOriginPath"
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
                            preserveForwardStack = true
                            mode = forwardMode
                        }
                    }
            )
            #endif
            .miniBarClearance()
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
            // Swipe right at a category root to go all the way back to the
            // Library list; leftward (forward) swipes are handled by the
            // window-level recognizer, which sees every screen.
            .simultaneousGesture(
                DragGesture(minimumDistance: 25)
                    .onEnded { value in
                        guard abs(value.translation.height) < 50 else { return }
                        if value.translation.width > 70, path.isEmpty,
                           horizontalSizeClass == .compact {
                            forwardMode = mode
                            preserveForwardStack = true
                            mode = nil
                        }
                    }
            )
            #endif
        }
        #if os(iOS)
        .background(
            ForwardSwipeInstaller(
                // mode == nil means the Library list is showing, where its
                // own gesture handles the forward swipe.
                isEnabled: { mode != nil && !forwardStack.isEmpty && path.last != .nowPlaying },
                onForward: goForward
            )
        )
        #endif
        .onChange(of: mode) { oldMode, newMode in
            #if os(iOS)
            if newMode != nil { forwardMode = nil }
            #endif
            if let oldMode { savedPaths[oldMode] = path }
            let restored = newMode.flatMap { savedPaths[$0] } ?? []
            if preserveForwardStack {
                preserveForwardStack = false
            } else {
                forwardStack = []
            }
            if restored != path {
                isRestoringPath = true
                path = restored
            }
            saveNavigation()
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
            saveNavigation()
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
        .environment(\.libraryNavigate) { destination in
            #if os(macOS)
            showingNowPlaying = false
            #endif
            path.append(destination)
        }
        // Pick up where the last session left off, paused, as soon as any
        // content is available - the launch-time cache makes this nearly
        // instant; a fresh scan (first launch) arrives seconds later.
        .onChange(of: library.contentVersion) {
            attemptRestore()
        }
        .onAppear {
            attemptRestore()
        }
        .preferredColorScheme(Appearance(rawValue: appearanceRaw)?.colorScheme)
        .fileImporter(isPresented: $showingFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                library.setRootFolder(url)
            }
        }
    }

    /// Paths persist relative to the library root: the app's container
    /// path (and any absolute path in it) changes across app updates.
    private func rootRelativePath(_ url: URL) -> String {
        guard let root = library.rootURL?.path, url.path.hasPrefix(root) else { return url.path }
        return String(url.path.dropFirst(root.count))
    }

    private func persistenceToken(for destination: LibraryDestination) -> String {
        switch destination {
        case .playlist(let playlist): "playlist|\(rootRelativePath(playlist.folderURL))"
        case .album(let album): "album|\(album.id)"
        case .artist(let artist): "artist|\(artist.name)"
        case .nowPlaying: "nowPlaying"
        }
    }

    private func saveNavigation() {
        let defaults = UserDefaults.standard
        defaults.set(mode?.rawValue, forKey: Self.navModeKey)
        defaults.set(path.map(persistenceToken(for:)), forKey: Self.navPathKey)
        defaults.set(forwardStack.map(persistenceToken(for:)), forKey: Self.navForwardKey)
        #if os(iOS)
        if let playbackOrigin {
            defaults.set(playbackOrigin.mode?.rawValue, forKey: Self.navOriginModeKey)
            defaults.set(playbackOrigin.path.map(persistenceToken(for:)), forKey: Self.navOriginPathKey)
        } else {
            defaults.removeObject(forKey: Self.navOriginModeKey)
            defaults.removeObject(forKey: Self.navOriginPathKey)
        }
        #endif
    }

    private func resolveDestination(_ token: String) -> LibraryDestination? {
        let parts = token.split(separator: "|", maxSplits: 1)
        guard let kind = parts.first else { return nil }
        let value = parts.count > 1 ? String(parts[1]) : ""
        switch kind {
        case "playlist":
            return library.playlists.first { rootRelativePath($0.folderURL) == value }.map(LibraryDestination.playlist)
        case "album":
            return library.albums.first { $0.id == value }.map(LibraryDestination.album)
        case "artist":
            return library.artists.first { $0.name == value }.map(LibraryDestination.artist)
        case "nowPlaying":
            return .nowPlaying
        default:
            return nil
        }
    }

    private func attemptRestore() {
        guard !library.playlists.isEmpty else { return }
        player.libraryRootPath = library.rootURL?.path
        player.restoreSession(from: library.playlists.flatMap(\.tracks))
        restoreNavigationIfNeeded()
    }

    /// Rebuilds the last visited screen from persisted tokens, truncating
    /// at the first one the rescanned library can no longer resolve.
    private func restoreNavigationIfNeeded() {
        #if os(iOS)
        guard !hasRestoredNavigation else { return }
        hasRestoredNavigation = true
        let defaults = UserDefaults.standard
        guard let modeRaw = defaults.string(forKey: Self.navModeKey),
              let savedMode = BrowseMode(rawValue: modeRaw) else { return }

        var restoredPath: [LibraryDestination] = []
        for token in defaults.stringArray(forKey: Self.navPathKey) ?? [] {
            guard let destination = resolveDestination(token) else { break }
            restoredPath.append(destination)
        }
        // Never land on (or forward-navigate to) an empty player.
        if restoredPath.last == .nowPlaying, player.currentTrack == nil {
            restoredPath.removeLast()
        }
        let restoredForward = (defaults.stringArray(forKey: Self.navForwardKey) ?? [])
            .compactMap(resolveDestination)
            .filter { $0 != .nowPlaying || player.currentTrack != nil }
        if player.currentTrack != nil,
           let originModeRaw = defaults.string(forKey: Self.navOriginModeKey) {
            var originPath: [LibraryDestination] = []
            for token in defaults.stringArray(forKey: Self.navOriginPathKey) ?? [] {
                guard let destination = resolveDestination(token) else { break }
                originPath.append(destination)
            }
            playbackOrigin = (BrowseMode(rawValue: originModeRaw), originPath)
        }

        savedPaths[savedMode] = []
        mode = savedMode
        guard !restoredPath.isEmpty || !restoredForward.isEmpty else { return }
        // The whole path lands in a single animation-free assignment:
        // consecutive mutations corrupt NavigationStack even without
        // animations, but one atomic write materializes cleanly. If the
        // stack still truncates it, the missing tail joins the forward
        // stack, so the full chain stays reachable by swiping forward.
        Task { @MainActor in
            // Path writes made before the app is active (device launches
            // are slower than the simulator's) are discarded outright, so
            // wait for activity first, then retry the atomic assignment
            // until the stack stops writing truncations back. Checked via
            // UIApplication because an @Environment scenePhase captured in
            // this closure would never update.
            for _ in 0..<50 where UIApplication.shared.applicationState != .active {
                try? await Task.sleep(for: .milliseconds(100))
            }
            for attempt in 0..<5 {
                try? await Task.sleep(for: .milliseconds(attempt == 0 ? 200 : 600))
                guard mode == savedMode,
                      path == Array(restoredPath.prefix(path.count)) else {
                    return
                }
                guard path.count < restoredPath.count else { break }
                isRestoringPath = true
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    path = restoredPath
                }
            }
            try? await Task.sleep(for: .milliseconds(500))
            guard mode == savedMode else { return }
            var forward = restoredForward
            if path.count < restoredPath.count {
                forward.append(contentsOf: restoredPath[path.count...].reversed())
            }
            if !forward.isEmpty {
                forwardStack = forward
                saveNavigation()
            }
        }
        #endif
    }

    private func goForward() {
        // NavigationStack silently drops path changes made while a push or
        // pop transition is still running; space consecutive pushes out.
        guard Date().timeIntervalSince(lastForwardPush) > 0.6 else { return }
        guard let next = forwardStack.last else { return }
        lastForwardPush = Date()
        forwardStack.removeLast()
        isRestoringPath = true
        path.append(next)
    }

    /// Called when a track is picked from a list: remembers that list as
    /// the playback origin, then shows the now-playing screen.
    private func playFromList() {
        #if os(iOS)
        playbackOrigin = (mode, path)
        saveNavigation()
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

#if os(iOS)
// The mini bar overlays the window bottom without insetting scroll views
// inside the split view's columns, so lists reserve its height themselves.
private struct MiniBarClearanceModifier: ViewModifier {
    @Environment(PlayerController.self) private var player

    func body(content: Content) -> some View {
        content.contentMargins(.bottom, player.currentTrack != nil ? 62 : 0, for: .scrollContent)
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

    @ViewBuilder
    func miniBarClearance() -> some View {
        #if os(iOS)
        modifier(MiniBarClearanceModifier())
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
    @State private var searchText = ""

    // Titles first; if nothing matches, fall back to the artist so an
    // artist's name pulls up their songs.
    private var filteredTracks: [Track] {
        guard !searchText.isEmpty else { return tracks }
        let byTitle = tracks.filter { $0.displayTitle.localizedStandardContains(searchText) }
        if !byTitle.isEmpty { return byTitle }
        return tracks.filter { $0.artist?.localizedStandardContains(searchText) == true }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $searchText, prompt: "Title or Artist")
            List(filteredTracks) { track in
                // A tap gesture (not a Button): buttons fire on release even
                // after a long horizontal swipe across the row, which turned
                // the forward-swipe into an accidental track change.
                TrackRow(track: track, isPlaying: player.currentTrack == track, showsArtist: showsArtist)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        player.play(track, in: filteredTracks)
                        onPlay()
                    }
            }
            .scrollContentBackground(.hidden)
            .overlay {
                if filteredTracks.isEmpty, !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .miniBarClearance()
        }
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
