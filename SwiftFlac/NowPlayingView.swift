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
        HStack(spacing: 12) {
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
            Spacer()
            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

struct NowPlayingView: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var scrubTime: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            VStack(spacing: 24) {
                ArtworkView(data: player.nowPlaying.artworkData, size: 260, cornerRadius: 12)
                    .shadow(radius: 10)

                VStack(spacing: 4) {
                    Text(player.displayTitle)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                VStack(spacing: 4) {
                    Slider(
                        value: Binding(
                            get: { scrubTime ?? player.currentTime },
                            set: { scrubTime = $0 }
                        ),
                        in: 0...max(player.duration, 1)
                    ) { editing in
                        if !editing {
                            if let scrubTime { player.seek(to: scrubTime) }
                            scrubTime = nil
                        }
                    }
                    HStack {
                        Text(formatted(scrubTime ?? player.currentTime))
                        Spacer()
                        Text(formatted(player.duration))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                HStack(spacing: 48) {
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
                    }
                    Button {
                        player.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 540)
        #endif
        .presentationDragIndicator(.visible)
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
