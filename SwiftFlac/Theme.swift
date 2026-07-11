import SwiftUI

enum Appearance: String, CaseIterable {
    case system, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

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
