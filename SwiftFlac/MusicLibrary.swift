import Foundation
import Observation

struct LibraryContent {
    var playlists: [Playlist] = []
    var albums: [Album] = []
    var artists: [Artist] = []
    var allTracks: [Track] = []
}

@MainActor
@Observable
final class MusicLibrary {
    private(set) var playlists: [Playlist] = []
    private(set) var albums: [Album] = []
    private(set) var artists: [Artist] = []
    private(set) var allTracks: [Track] = []
    private(set) var isScanning = false
    private(set) var rootURL: URL?

    private var scanGeneration = 0

    private static let bookmarkKey = "libraryFolderBookmark"

    init() {
        restoreRoot()
        rescan()
    }

    /// Points the library at a new root folder and persists access to it.
    func setRootFolder(_ url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        #if os(macOS)
        let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        let bookmark = try? url.bookmarkData()
        #endif
        UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        rootURL = url
        rescan()
    }

    func rescan() {
        scanGeneration += 1
        let generation = scanGeneration
        guard let rootURL else {
            apply(LibraryContent())
            return
        }
        isScanning = true
        Task.detached(priority: .userInitiated) {
            let content = await LibraryScanner.scan(root: rootURL)
            await MainActor.run {
                guard generation == self.scanGeneration else { return }
                self.apply(content)
            }
        }
    }

    private func apply(_ content: LibraryContent) {
        playlists = content.playlists
        albums = content.albums
        artists = content.artists
        allTracks = content.allTracks
        isScanning = false
    }

    private func restoreRoot() {
        if let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) {
            var stale = false
            #if os(macOS)
            let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
            #else
            let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
            #endif
            if let url {
                _ = url.startAccessingSecurityScopedResource()
                rootURL = url
                return
            }
        }
        #if os(iOS)
        // Default to the app's Documents folder so music can be dropped in
        // via Finder/Files file sharing without any setup.
        rootURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        #endif
    }
}

/// Filesystem walking and tag grouping, kept off the main actor since it
/// reads the header of every audio file in the library.
private enum LibraryScanner {
    private static let audioExtensions: Set<String> = ["flac", "mp3", "m4a", "aac", "wav", "aiff", "aif"]

    static func scan(root: URL) async -> LibraryContent {
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var playlists: [Playlist] = []

        // Loose tracks sitting directly in the root form their own playlist.
        let looseTracks = await tracks(from: contents.filter(isAudioFile))
        if !looseTracks.isEmpty {
            playlists.append(Playlist(name: root.lastPathComponent, folderURL: root, tracks: looseTracks))
        }

        let folders = contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        for folder in folders {
            let folderTracks = await tracks(from: audioFiles(under: folder))
            if !folderTracks.isEmpty {
                playlists.append(Playlist(name: folder.lastPathComponent, folderURL: folder, tracks: folderTracks))
            }
        }

        let all = playlists.flatMap(\.tracks)
        return LibraryContent(
            playlists: playlists,
            albums: albums(from: all),
            artists: artists(from: all),
            allTracks: all.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        )
    }

    /// Collects audio files anywhere below the folder, so nested album folders still play.
    private static func audioFiles(under folder: URL) -> [URL] {
        let fm = FileManager.default
        var files: [URL] = []
        if let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator where isAudioFile(url) {
                files.append(url)
            }
        }
        return files
    }

    private static func tracks(from urls: [URL]) async -> [Track] {
        let sorted = urls.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        var tracks: [Track] = []
        for url in sorted {
            // FLAC gets the fast header parser; other formats go through
            // AVFoundation, which understands their ID3/iTunes tags.
            let tags: TrackMetadata
            if url.pathExtension.lowercased() == "flac" {
                tags = FlacMetadata.read(from: url, readArtwork: false)
            } else {
                tags = await loadMetadata(from: url, includeArtwork: false)
            }
            tracks.append(Track(
                url: url,
                title: tags.title,
                artist: tags.artist,
                album: tags.album,
                albumArtist: tags.albumArtist,
                trackNumber: tags.trackNumber,
                discNumber: tags.discNumber
            ))
        }
        return tracks
    }

    private static func albums(from tracks: [Track]) -> [Album] {
        let groups = Dictionary(grouping: tracks) { track in
            "\(track.albumArtist ?? track.artist ?? "")|\(track.album ?? "")"
        }
        return groups.values.map { group in
            let artists = Set(group.compactMap(\.artist))
            let artist = group[0].albumArtist
                ?? (artists.count == 1 ? artists.first : (artists.isEmpty ? nil : "Various Artists"))
            // Disc then track number, falling back to filename order for
            // untagged files.
            let sorted = group.sorted { lhs, rhs in
                let left = (lhs.discNumber ?? 1, lhs.trackNumber ?? Int.max)
                let right = (rhs.discNumber ?? 1, rhs.trackNumber ?? Int.max)
                if left != right { return left < right }
                return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
            }
            return Album(name: group[0].album ?? "Unknown Album", artist: artist, tracks: sorted)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func artists(from tracks: [Track]) -> [Artist] {
        Dictionary(grouping: tracks) { $0.artist ?? "Unknown Artist" }
            .map { name, group in
                Artist(name: name, tracks: group.sorted {
                    $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
                })
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func isAudioFile(_ url: URL) -> Bool {
        audioExtensions.contains(url.pathExtension.lowercased())
    }
}
