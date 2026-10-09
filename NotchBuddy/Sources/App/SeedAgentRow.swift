#if COUCOU_HUB
import SwiftUI

// MARK: - Agent row (Seed's own)
//
// Replaces the upstream Mochi pill in the agent list. The rice in the corner is
// the only character: an agent is just a colour dot and its name. Hover warms
// the row with the brand's gold light instead of scaling it; selection is a
// thin gold rim, drawn inside the row so it is never clipped.

struct SeedAgentRow: View {
    let name: String
    let colorHex: String
    let online: Bool
    let held: Int
    let selected: Bool
    let action: () -> Void

    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let gold = Color(hex: "#F5C542")

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                dot
                Text(name)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(Color(hex: online ? "#F5F6F8" : "#8E939C"))
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                if held > 0 {
                    Text(held > 9 ? "9+" : String(held))
                        .font(.system(size: 9.5, weight: .bold)).monospacedDigit()
                        .foregroundColor(.black)
                        .padding(.horizontal, 5).frame(minWidth: 16, minHeight: 16)
                        .background(Color(hex: "#F5A524"), in: Capsule())
                        .accessibilityHidden(true)
                }
            }
            .padding(.leading, 10).padding(.trailing, 10)
            .frame(height: 34)
            .background(background)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if reduceMotion { hovered = inside } else { withAnimation(.easeOut(duration: 0.18)) { hovered = inside } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue([online ? "online" : "offline",
                             held > 0 ? "\(held) waiting for approval" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// The agent's colour as a plain dot (not a character); offline agents dim.
    private var dot: some View {
        Circle()
            .fill(Color(hex: colorHex).opacity(online ? 1 : 0.35))
            .frame(width: 7, height: 7)
            .frame(width: 12, height: 16)
    }

    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        return shape
            .fill(Color(hex: "#0E0F11"))
            // Hover: a warm wash of gold light from the leading edge.
            .overlay(shape.fill(LinearGradient(colors: [Self.gold.opacity(hovered ? 0.12 : 0), .clear],
                                               startPoint: .leading, endPoint: .trailing)))
            .overlay(shape.strokeBorder(selected ? Self.gold.opacity(0.7)
                                                 : Color.white.opacity(hovered ? 0.1 : 0.05),
                                        lineWidth: selected ? 1.2 : 1))
    }
}
#endif
