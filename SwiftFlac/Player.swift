import AVFoundation
import MediaPlayer
import Observation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

enum RepeatMode: String {
    case off, all, one
}

@MainActor
@Observable
final class PlayerController: NSObject {
    private(set) var queue: [Track] = []
    private(set) var currentIndex: Int?
    private(set) var isPlaying = false
    private(set) var nowPlaying = TrackMetadata()
    private(set) var isShuffling = false
    private(set) var repeatMode: RepeatMode = .off

    private var player: AVAudioPlayer?
    private var originalQueue: [Track] = []

    private static let shuffleKey = "playerShuffle"
    private static let repeatKey = "playerRepeatMode"

    var currentTrack: Track? {
        guard let currentIndex, queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    var currentTime: TimeInterval { player?.currentTime ?? 0 }
    var duration: TimeInterval { player?.duration ?? 0 }

    var displayTitle: String { nowPlaying.title ?? currentTrack?.displayName ?? "" }

    override init() {
        super.init()
        isShuffling = UserDefaults.standard.bool(forKey: Self.shuffleKey)
        repeatMode = UserDefaults.standard.string(forKey: Self.repeatKey)
            .flatMap(RepeatMode.init(rawValue:)) ?? .off
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        configureRemoteCommands()
    }

    func play(_ track: Track, from playlist: Playlist) {
        originalQueue = playlist.tracks
        if isShuffling {
            var rest = playlist.tracks.filter { $0 != track }
            rest.shuffle()
            queue = [track] + rest
            currentIndex = 0
        } else {
            queue = playlist.tracks
            currentIndex = playlist.tracks.firstIndex(of: track)
        }
        startCurrentTrack()
    }

    func toggleShuffle() {
        isShuffling.toggle()
        UserDefaults.standard.set(isShuffling, forKey: Self.shuffleKey)
        guard let current = currentTrack else { return }
        if isShuffling {
            var rest = queue.filter { $0 != current }
            rest.shuffle()
            queue = [current] + rest
            currentIndex = 0
        } else {
            queue = originalQueue
            currentIndex = originalQueue.firstIndex(of: current)
        }
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        UserDefaults.standard.set(repeatMode.rawValue, forKey: Self.repeatKey)
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        updateNowPlayingInfo()
    }

    func next() {
        advance(by: 1)
    }

    func previous() {
        // Restart the current track unless we're right at its start.
        if currentTime > 3 {
            seek(to: 0)
        } else {
            advance(by: -1)
        }
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        // Setting currentTime on a playing AVAudioPlayer can wedge the
        // decoder; pause around the jump, and stay clear of the very end.
        let wasPlaying = isPlaying
        let target = min(max(0, time), max(duration - 0.1, 0))
        player.pause()
        player.currentTime = target
        if wasPlaying { player.play() }
        updateNowPlayingInfo()
    }

    private func advance(by offset: Int) {
        guard let currentIndex, !queue.isEmpty else { return }
        var target = currentIndex + offset
        if !queue.indices.contains(target) {
            guard repeatMode == .all else {
                // End of queue: stop but keep the last track visible.
                player?.stop()
                isPlaying = false
                updateNowPlayingInfo()
                return
            }
            target = (target + queue.count) % queue.count
        }
        self.currentIndex = target
        startCurrentTrack()
    }

    private func trackFinished() {
        if repeatMode == .one {
            // A finished AVAudioPlayer does not reliably restart with play(),
            // so rebuild it just like a track change (keeping the metadata).
            startCurrentTrack(reloadMetadata: false)
        } else {
            advance(by: 1)
        }
    }

    private func startCurrentTrack(reloadMetadata: Bool = true) {
        guard let track = currentTrack else { return }
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: track.url)
            newPlayer.delegate = self
            player = newPlayer
            newPlayer.play()
            isPlaying = true
        } catch {
            player = nil
            isPlaying = false
        }
        guard reloadMetadata else {
            updateNowPlayingInfo()
            return
        }
        nowPlaying = TrackMetadata()
        updateNowPlayingInfo()
        Task {
            let metadata = await loadMetadata(for: track)
            guard track == currentTrack else { return }
            nowPlaying = metadata
            updateNowPlayingInfo()
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if self?.isPlaying == false { self?.togglePlayPause() }
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if self?.isPlaying == true { self?.togglePlayPause() }
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlaying.title ?? track.displayName,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let artist = nowPlaying.artist { info[MPMediaItemPropertyArtist] = artist }
        if let album = nowPlaying.album { info[MPMediaItemPropertyAlbumTitle] = album }
        #if canImport(UIKit)
        if let data = nowPlaying.artworkData, let image = UIImage(data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        #else
        if let data = nowPlaying.artworkData, let image = NSImage(data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        #endif
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

extension PlayerController: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.trackFinished() }
    }
}
