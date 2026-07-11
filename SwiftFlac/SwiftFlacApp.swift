import SwiftUI

@main
struct SwiftFlacApp: App {
    @State private var library = MusicLibrary()
    @State private var player = PlayerController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
                .environment(player)
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 620)
        .commands {
            CommandMenu("Playback") {
                Button(player.isPlaying ? "Pause" : "Play") {
                    player.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(player.currentTrack == nil)
                Button("Next Track") {
                    player.next()
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(player.currentTrack == nil)
                Button("Previous Track") {
                    player.previous()
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(player.currentTrack == nil)
            }
        }
        #endif
    }
}
