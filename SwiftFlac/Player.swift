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
final class PlayerController {
    private(set) var queue: [Track] = []
    private(set) var currentIndex: Int?
    private(set) var isPlaying = false
    private(set) var nowPlaying = TrackMetadata()
    private(set) var isShuffling = false
    private(set) var repeatMode: RepeatMode = .off
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    private let player = AVPlayer()
    // The macOS route picker needs the player reference to offer AirPlay.
    var routePickerPlayer: AVPlayer { player }
    private var originalQueue: [Track] = []
    private var timeObserver: Any?
    private var isSeeking = false
    private var statusObservation: NSKeyValueObservation?
    private var consecutiveFailures = 0

    private static let shuffleKey = "playerShuffle"
    private static let repeatKey = "playerRepeatMode"

    var currentTrack: Track? {
        guard let currentIndex, queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    var displayTitle: String { nowPlaying.title ?? currentTrack?.displayTitle ?? "" }

    init() {
        isShuffling = UserDefaults.standard.bool(forKey: Self.shuffleKey)
        repeatMode = UserDefaults.standard.string(forKey: Self.repeatKey)
            .flatMap(RepeatMode.init(rawValue:)) ?? .off
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        configureRemoteCommands()
        #if os(macOS)
        // Focused lists swallow bare Space (scroll page-down) before menu
        // shortcuts see it, so play/pause is handled app-wide here instead.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self,
                      event.keyCode == 49,  // space
                      event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                      !(NSApp.keyWindow?.firstResponder is NSText),
                      self.currentTrack != nil
                else { return event }
                self.togglePlayPause()
                return nil
            }
        }
        #endif

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isSeeking else { return }
                self.currentTime = time.seconds
            }
        }
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self,
                      let item = notification.object as? AVPlayerItem,
                      item === self.player.currentItem else { return }
                self.trackFinished()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self,
                      let item = notification.object as? AVPlayerItem,
                      item === self.player.currentItem else { return }
                self.currentTrackFailed()
            }
        }
    }

    func play(_ track: Track, in tracks: [Track]) {
        originalQueue = tracks
        if isShuffling {
            var rest = tracks.filter { $0 != track }
            rest.shuffle()
            queue = [track] + rest
            currentIndex = 0
        } else {
            queue = tracks
            currentIndex = tracks.firstIndex(of: track)
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
        guard player.currentItem != nil else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
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
        guard player.currentItem != nil else { return }
        // Scrubbing into the last second means "done with this song": jump
        // straight to the end-of-track behaviour instead of making the
        // decoder grind to the tail (slow for FLAC, and landing exactly on
        // the end can stall without firing the finished notification).
        if duration > 0, time >= duration - 1 {
            trackFinished()
            return
        }
        let target = min(max(0, time), max(duration - 0.1, 0))
        // Freeze observer updates until the async seek lands, otherwise the
        // slider briefly snaps back to the pre-seek position.
        isSeeking = true
        currentTime = target
        // Sample-exact seeks can wedge near the end of a FLAC; allow slack
        // before the target (never after, so we can't trip the track end).
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .positiveInfinity,
            toleranceAfter: .zero
        ) { [weak self] _ in
            Task { @MainActor in self?.isSeeking = false }
        }
        updateNowPlayingInfo()
    }

    private func advance(by offset: Int) {
        guard let currentIndex, !queue.isEmpty else { return }
        var target = currentIndex + offset
        if !queue.indices.contains(target) {
            guard repeatMode == .all else {
                // End of queue: stop but keep the last track visible.
                player.pause()
                isPlaying = false
                updateNowPlayingInfo()
                return
            }
            target = (target + queue.count) % queue.count
        }
        self.currentIndex = target
        startCurrentTrack()
    }

    /// A track that cannot play behaves like one that ended, except it is
    /// never retried (repeat-one would loop on it forever), and a queue
    /// where every track fails stops instead of skip-looping.
    private func currentTrackFailed() {
        consecutiveFailures += 1
        guard consecutiveFailures < max(queue.count, 1) else {
            player.pause()
            isPlaying = false
            updateNowPlayingInfo()
            return
        }
        advance(by: 1)
    }

    private func trackFinished() {
        if repeatMode == .one {
            player.seek(to: .zero)
            player.play()
            isPlaying = true
            currentTime = 0
            updateNowPlayingInfo()
        } else {
            advance(by: 1)
        }
    }

    private func startCurrentTrack(reloadMetadata: Bool = true) {
        guard let track = currentTrack else { return }
        // Without the precise-timing option AVFoundation only estimates the
        // duration of compressed audio, so tracks outrun their slider.
        let asset = AVURLAsset(url: track.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let item = AVPlayerItem(asset: asset)
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            let status = item.status
            Task { @MainActor in
                guard let self, item === self.player.currentItem else { return }
                switch status {
                case .failed:
                    self.currentTrackFailed()
                case .readyToPlay:
                    self.consecutiveFailures = 0
                default:
                    break
                }
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
        isSeeking = false
        currentTime = 0
        duration = 0
        Task {
            let seconds = (try? await item.asset.load(.duration))?.seconds ?? 0
            guard item === player.currentItem else { return }
            duration = seconds.isFinite ? seconds : 0
            updateNowPlayingInfo()
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
            // AirPlay receivers read metadata from the item itself, not
            // from MPNowPlayingInfoCenter. (iOS-only API.)
            #if os(iOS)
            item.externalMetadata = externalMetadata(for: track)
            #endif
        }
    }

    private func externalMetadata(for track: Track) -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []
        func add(_ identifier: AVMetadataIdentifier, _ value: (NSCopying & NSObjectProtocol)?) {
            guard let value else { return }
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value
            item.extendedLanguageTag = "und"
            items.append(item)
        }
        add(.commonIdentifierTitle, (nowPlaying.title ?? track.displayTitle) as NSString)
        add(.commonIdentifierArtist, nowPlaying.artist as NSString?)
        add(.commonIdentifierAlbumName, nowPlaying.album as NSString?)
        add(.commonIdentifierArtwork, nowPlaying.artworkData as NSData?)
        return items
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
            MPMediaItemPropertyTitle: nowPlaying.title ?? track.displayTitle,
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
