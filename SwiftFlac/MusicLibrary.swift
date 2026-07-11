import Foundation
import Observation

@MainActor
@Observable
final class MusicLibrary {
    private(set) var playlists: [Playlist] = []
    private(set) var rootURL: URL?

    private static let bookmarkKey = "libraryFolderBookmark"
    private static let audioExtensions: Set<String> = ["flac"]

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
        guard let rootURL else {
            playlists = []
            return
        }
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var result: [Playlist] = []

        // Loose tracks sitting directly in the root form their own playlist.
        let looseTracks = sortedTracks(contents.filter(Self.isAudioFile))
        if !looseTracks.isEmpty {
            result.append(Playlist(name: rootURL.lastPathComponent, folderURL: rootURL, tracks: looseTracks))
        }

        let folders = contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        for folder in folders {
            let tracks = tracksInFolder(folder)
            if !tracks.isEmpty {
                result.append(Playlist(name: folder.lastPathComponent, folderURL: folder, tracks: tracks))
            }
        }
        playlists = result
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

    /// Collects audio files anywhere below the folder, so nested album folders still play.
    private func tracksInFolder(_ folder: URL) -> [Track] {
        let fm = FileManager.default
        var files: [URL] = []
        if let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator where Self.isAudioFile(url) {
                files.append(url)
            }
        }
        return sortedTracks(files)
    }

    private func sortedTracks(_ urls: [URL]) -> [Track] {
        urls
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map(Track.init)
    }

    private static func isAudioFile(_ url: URL) -> Bool {
        audioExtensions.contains(url.pathExtension.lowercased())
    }
}
