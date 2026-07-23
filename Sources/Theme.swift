import SwiftUI

/// One place for the app's look, so every screen shares the same palette, spacing, and
/// controls instead of ad-hoc system styles. Colours are chosen to match the app icon
/// (deep navy frame + green check) and to keep a clean semantic split:
/// navy = the thing to tap, green = passed, orange = check this, red = fix this.
enum Brand {
    /// Primary action / brand colour — deep navy-teal, matches the icon frame.
    static let primary = Color(red: 0.10, green: 0.28, blue: 0.42)
    /// Success / verified.
    static let pass = Color(red: 0.15, green: 0.62, blue: 0.42)
    /// Needs attention.
    static let attention = Color(red: 0.85, green: 0.56, blue: 0.15)
    /// A soft tint of the primary for chips and backgrounds.
    static let primarySoft = Color(red: 0.10, green: 0.28, blue: 0.42).opacity(0.10)
}

/// The one call-to-action button used on every screen.
struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(enabled ? Brand.primary : Color.secondary.opacity(0.3),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

extension View {
    /// Groups content on a rounded surface, the app's standard "card".
    func card() -> some View {
        self
            .padding(16)
            .background(Color(.secondarySystemBackground),
                       in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
