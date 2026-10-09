#if COUCOU_HUB
import SwiftUI

// MARK: - Seed's design tokens
//
// One place for Seed's colours and its button, shared by the notch cards and
// Settings. Gold is Seed's accent: focus, selection and the one main action.

enum SeedInk {
    static let bg      = Color(hex: "#0E0F11")
    static let raised  = Color(hex: "#131518")
    static let line    = Color.white.opacity(0.07)
    /// Opaque, so it never picks up the window behind it.
    static let divider = Color(hex: "#1C1E22")
    static let text    = Color(hex: "#F5F6F8")
    static let second  = Color(hex: "#C5C8CD")
    static let muted   = Color(hex: "#8E939C")
    static let faint   = Color(hex: "#6B7079")
    static let gold    = Color(hex: "#F5C542")
    /// Text on a gold fill.
    static let onGold  = Color(hex: "#1A1405")
    static let amber   = Color(hex: "#F5A524")
    static let cyan    = Color(hex: "#22D3EE")
    static let green   = Color(hex: "#22C55E")
    static let red     = Color(hex: "#F4505E")

    /// Seed's spring: soft, settles without a wobble.
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.8)
}

struct SeedButtonStyle: ButtonStyle {
    var primary = false
    var compact = false
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(primary ? SeedInk.onGold : SeedInk.text)
            .padding(.horizontal, compact ? 8 : 12).padding(.vertical, compact ? 4 : 6)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(primary ? SeedInk.gold : Color.white.opacity(hover && enabled ? 0.11 : 0.07)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(primary ? Color.clear : (hover && enabled ? SeedInk.gold.opacity(0.45) : SeedInk.line)))
            .brightness(primary && hover && enabled ? 0.05 : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .animation(SeedInk.spring, value: configuration.isPressed)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
    }
}
#endif
