import SwiftUI

/// Soft grey backdrop instead of flat white/black, with a faint
/// top sheen to keep it from looking completely flat.
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            colorScheme == .dark ? Color(white: 0.13) : Color(white: 0.93)
            LinearGradient(
                colors: [Color.white.opacity(colorScheme == .dark ? 0.05 : 0.4), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}
