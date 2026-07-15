import AVKit
import SwiftUI
#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

func artworkImage(from data: Data?) -> Image? {
    guard let data else { return nil }
    #if canImport(UIKit)
        return UIImage(data: data).map(Image.init(uiImage:))
    #else
        return NSImage(data: data).map(Image.init(nsImage:))
    #endif
}

struct NowPlayingBar: View {
    @Environment(PlayerController.self) private var player
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ProgressLine(progress: player.duration > 0 ? player.currentTime / player.duration : 0)
            HStack(spacing: 14) {
                // Only this leading region opens the full player, so the
                // transport buttons never race against the tap gesture.
                HStack(spacing: 14) {
                    ArtworkView(data: player.nowPlaying.artworkData, size: 40, cornerRadius: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.displayTitle)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        if let artist = player.nowPlaying.artist {
                            Text(artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
                ShuffleButton(compact: true)
                Button {
                    player.previous()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.body)
                }
                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 24)
                }
                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.body)
                }
                RepeatButton(compact: true)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.regularMaterial)
    }
}

struct ProgressLine: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.quaternary)
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 3)
    }
}

struct ShuffleButton: View {
    @Environment(PlayerController.self) private var player
    var compact = false

    var body: some View {
        Button {
            player.toggleShuffle()
        } label: {
            ToggleIcon(systemName: "shuffle", active: player.isShuffling, compact: compact)
        }
        .buttonStyle(.plain)
    }
}

struct RepeatButton: View {
    @Environment(PlayerController.self) private var player
    var compact = false

    var body: some View {
        Button {
            player.cycleRepeatMode()
        } label: {
            ToggleIcon(
                systemName: player.repeatMode == .one ? "repeat.1" : "repeat",
                active: player.repeatMode != .off,
                compact: compact
            )
        }
        .buttonStyle(.plain)
    }
}

/// Active state gets an accent chip behind the icon so on/off is
/// obvious in both light and dark mode.
struct ToggleIcon: View {
    let systemName: String
    let active: Bool
    var compact = false

    var body: some View {
        Image(systemName: systemName)
            .font(compact ? .footnote : .title3)
            .foregroundStyle(active ? Color.accentColor : Color.secondary)
            .padding(compact ? 4 : 6)
            .background(
                active ? Color.accentColor.opacity(0.22) : .clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
    }
}

struct NowPlayingView: View {
    @Environment(PlayerController.self) private var player
    @Environment(MusicLibrary.self) private var library
    @Environment(\.libraryNavigate) private var libraryNavigate
    @State private var dragFraction: Double?

    private var currentAlbum: Album? {
        guard let track = player.currentTrack else { return nil }
        return library.albums.first { $0.tracks.contains(track) }
    }

    private var currentArtist: Artist? {
        guard let track = player.currentTrack else { return nil }
        return library.artists.first { $0.tracks.contains(track) }
    }

    var body: some View {
        GeometryReader { geo in
            if geo.size.width > geo.size.height {
                // Landscape: artwork beside the controls instead of above them.
                HStack(spacing: 40) {
                    artwork(fitting: geo.size, landscape: true)
                    VStack(spacing: 28) {
                        info
                        scrubber
                        transport
                    }
                    .frame(maxWidth: 440)
                }
                .padding(32)
                .frame(width: geo.size.width, height: geo.size.height)
            } else {
                VStack(spacing: 24) {
                    Spacer(minLength: 0)
                    artwork(fitting: geo.size, landscape: false)
                    info
                    scrubber
                    transport
                    Spacer(minLength: 0)
                }
                .padding(32)
                // Pin to the container size: the iOS 26 Slider reports more
                // width than proposed, which would otherwise inflate the
                // stack and hang the overflow off the trailing edge.
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .background(AppBackground())
        #if os(macOS)
            .frame(minWidth: 420, minHeight: 540)
            .overlay(alignment: .topTrailing) {
                AirPlayButton(player: player.routePickerPlayer)
                    .frame(width: 24, height: 24)
                    .padding(12)
            }
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AirPlayButton(player: player.routePickerPlayer)
                    .frame(width: 28, height: 28)
            }
        }
        #endif
    }

    private func artwork(fitting size: CGSize, landscape: Bool) -> some View {
        // Reserve room for the controls: beside the artwork in landscape,
        // below it (~280pt) in portrait.
        let side = landscape
            ? min(size.height - 64, size.width * 0.45, 320)
            : min(size.width - 64, size.height - 280, 320)
        return Menu {
            goToMenuItems
        } label: {
            ArtworkView(data: player.nowPlaying.artworkData, size: max(side, 120), cornerRadius: 12)
                .shadow(radius: 10)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var goToMenuItems: some View {
        if let album = currentAlbum {
            Button("Go to Album", systemImage: "square.stack") {
                libraryNavigate(.album(album))
            }
        }
        if let artist = currentArtist {
            Button("Go to Artist", systemImage: "music.mic") {
                libraryNavigate(.artist(artist))
            }
        }
    }

    private var info: some View {
        Menu {
            goToMenuItems
        } label: {
            VStack(spacing: 4) {
                Text(player.displayTitle)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    /// Custom scrubber instead of Slider: the iOS 26 system slider opens
    /// phantom editing sessions and echoes stale values through its binding
    /// around track changes, which repeatedly froze this view.
    private var scrubber: some View {
        let playbackFraction = player.duration > 0 ? player.currentTime / player.duration : 0
        return VStack(spacing: 4) {
            ScrubberBar(fraction: dragFraction ?? playbackFraction) { fraction, ended in
                if ended {
                    dragFraction = nil
                    player.seek(to: fraction * player.duration)
                } else {
                    dragFraction = fraction
                }
            }
            HStack {
                Text(formatted((dragFraction ?? playbackFraction) * player.duration))
                Spacer()
                Text(formatted(player.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private var transport: some View {
        HStack(spacing: 36) {
            ShuffleButton()
            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title)
            }
            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 44))
                    .frame(width: 52)
            }
            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
            }
            RepeatButton()
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        [player.nowPlaying.artist, player.nowPlaying.album]
            .compactMap { $0 }
            .joined(separator: " - ")
    }

    private func formatted(_ time: TimeInterval) -> String {
        Duration.seconds(time).formatted(.time(pattern: .minuteSecond))
    }
}

#if os(iOS)
    struct AirPlayButton: UIViewRepresentable {
        let player: AVPlayer

        func makeUIView(context _: Context) -> AVRoutePickerView {
            let picker = AVRoutePickerView()
            picker.backgroundColor = .clear
            picker.tintColor = .secondaryLabel
            picker.activeTintColor = .label
            return picker
        }

        func updateUIView(_: AVRoutePickerView, context _: Context) {}
    }
#else
    struct AirPlayButton: NSViewRepresentable {
        let player: AVPlayer

        func makeNSView(context _: Context) -> AVRoutePickerView {
            let picker = AVRoutePickerView()
            picker.player = player
            picker.isRoutePickerButtonBordered = false
            return picker
        }

        func updateNSView(_: AVRoutePickerView, context _: Context) {}
    }
#endif

/// A capsule progress bar with drag-to-seek. `onScrub` is called with the
/// dragged fraction and whether the touch has ended.
struct ScrubberBar: View {
    let fraction: Double
    let onScrub: (Double, Bool) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(geo.size.width * min(max(fraction, 0), 1), 8))
            }
            .frame(height: 8)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onScrub(min(max(value.location.x / geo.size.width, 0), 1), false)
                    }
                    .onEnded { value in
                        onScrub(min(max(value.location.x / geo.size.width, 0), 1), true)
                    }
            )
        }
        .frame(height: 28)
    }
}

struct ArtworkView: View {
    let data: Data?
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let image = artworkImage(from: data) {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Rectangle()
                        .fill(.quaternary)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
