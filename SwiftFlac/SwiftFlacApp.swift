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
        #endif
    }
}
