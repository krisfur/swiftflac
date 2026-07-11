import AVFoundation
import MediaPlayer
import Observation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@MainActor
@Observable
final class PlayerController: NSObject {
    private(set) var queue: [Track] = []
    private(set) var currentIndex: Int?
    private(set) var isPlaying = false
    private(set) var nowPlaying = TrackMetadata()

    private var player: AVAudioPlayer?

    var currentTrack: Track? {
        guard let currentIndex, queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    var currentTime: TimeInterval { player?.currentTime ?? 0 }
    var duration: TimeInterval { player?.duration ?? 0 }

    var displayTitle: String { nowPlaying.title ?? currentTrack?.displayName ?? "" }

    override init() {
        super.init()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        configureRemoteCommands()
    }

    func play(_ track: Track, from playlist: Playlist) {
        queue = playlist.tracks
        currentIndex = playlist.tracks.firstIndex(of: track)
        startCurrentTrack()
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
        player?.currentTime = min(max(0, time), duration)
        updateNowPlayingInfo()
    }

    private func advance(by offset: Int) {
        guard let currentIndex else { return }
        let target = currentIndex + offset
        guard queue.indices.contains(target) else {
            // End of queue: stop but keep the last track visible.
            player?.stop()
            isPlaying = false
            updateNowPlayingInfo()
            return
        }
        self.currentIndex = target
        startCurrentTrack()
    }

    private func startCurrentTrack() {
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
        Task { @MainActor in self.next() }
    }
}
