#if COUCOU_HUB
import SwiftUI

// MARK: - Seed's Action Ring (view)
//
// Drawn by the workspace above everything but Seed. The slots bloom out of
// Seed's centre; the slot being pointed at grows, turns gold and shows its
// name. Picking and pointing are handled by the workspace, which owns the
// pointer; this view only draws.

struct SeedActionRing: View {
    let center: CGPoint
    let slots: [SeedAction]
    let highlighted: Int?
    /// Slots fly out from Seed when true, fold back in when false.
    let bloomed: Bool
    let badges: [SeedAction: Int]
    let onCustomize: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let gold = Color(hex: "#F5C542")
    private static let size: CGFloat = 34

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(slots.enumerated()), id: \.element) { i, action in
                let on = highlighted == i
                let o = SeedRingGeometry.offset(index: i, count: slots.count)
                slot(action, on: on)
                    .scaleEffect(bloomed ? (on ? 1.14 : 1) : 0.3)
                    .opacity(bloomed ? 1 : 0)
                    .position(x: center.x + (bloomed ? o.width : 0), y: center.y + (bloomed ? o.height : 0))
                    .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.72)
                        .delay(bloomed ? Double(i) * 0.022 : 0), value: bloomed)
                    .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.7), value: on)
                    // The workspace owns pointing and picking; slots never swallow it.
                    .allowsHitTesting(false)
            }
            if let i = highlighted, slots.indices.contains(i), bloomed {
                label(slots[i], index: i)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .id(i)
            }
            // Customize sits well past the fan, clear of the slot labels whatever the slot count.
            let mid = SeedRingGeometry.offset(index: 0, count: 1, radius: SeedRingGeometry.radius + 90)
            Button(action: onCustomize) {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 9.5, weight: .semibold))
                    Text("Customize")
                }
                .font(.system(size: 10, weight: .medium)).foregroundColor(Color(hex: "#8E939C"))
                .padding(.horizontal, 8).frame(height: 22)
                .background(Color(hex: "#1A1C20"), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(bloomed ? 1 : 0)
            .position(x: center.x + mid.width + 18, y: center.y + mid.height)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2).delay(bloomed ? 0.12 : 0), value: bloomed)
            .accessibilityLabel("Customize the Action Ring")
        }
        .allowsHitTesting(bloomed)
    }

    private func slot(_ action: SeedAction, on: Bool) -> some View {
        let badge = badges[action] ?? 0
        return ZStack {
            Circle().fill(on ? Color(hex: "#2A2410") : Color(hex: "#131518"))
            Circle().strokeBorder(Self.gold.opacity(on ? 0.9 : 0.22), lineWidth: on ? 1.5 : 1)
            Image(systemName: action.symbol)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(on ? Self.gold : Color(hex: "#C5C8CD"))
        }
        .frame(width: Self.size, height: Self.size)
        .shadow(color: on ? Self.gold.opacity(0.35) : .black.opacity(0.45), radius: on ? 10 : 6)
        .overlay(alignment: .topTrailing) {
            if badge > 0 {
                Text(badge > 99 ? "99+" : String(badge))
                    .font(.system(size: 8.5, weight: .bold)).foregroundColor(.black)
                    .padding(.horizontal, 4).frame(minWidth: 15, minHeight: 15)
                    .background(Color(hex: action == .review ? "#F5A524" : "#E7E9EC"), in: Capsule())
                    .offset(x: 4, y: -3)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(badge > 0 ? "\(action.title), \(badge)" : action.title)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    /// The name of the slot being pointed at, just outside it.
    private func label(_ action: SeedAction, index: Int) -> some View {
        let o = SeedRingGeometry.offset(index: index, count: slots.count, radius: SeedRingGeometry.radius + 34)
        return Text(action.title)
            .font(.system(size: 10.5, weight: .semibold)).foregroundColor(.black)
            .padding(.horizontal, 8).frame(height: 20)
            .background(Self.gold, in: Capsule())
            .fixedSize()
            .position(x: max(center.x + o.width, 44), y: center.y + o.height)
    }
}

/// Choose the ring's actions: tap to add or remove; order follows taps.
struct SeedRingEditor: View {
    @ObservedObject var store: SeedRingStore
    let onDone: () -> Void

    private static let gold = Color(hex: "#F5C542")

    var body: some View {
        VStack(alignment: .leading, spacing: CoucouWorkspaceStyle.sectionGap) {
            HStack(spacing: 8) {
                Text("Action Ring").font(.system(size: 13, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
                Text("\(store.slots.count) of \(SeedRingStore.capacity)")
                    .font(.system(size: 11).monospacedDigit()).foregroundColor(Color(hex: "#6B7079"))
                Spacer(minLength: 4)
                Button("Reset") {
                    SoundEngine.shared.play("tick")
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { store.reset() }
                }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
                Button {
                    SoundEngine.shared.play("close")
                    onDone()
                } label: {
                    Text("Done").font(.system(size: 11, weight: .semibold)).foregroundColor(.black)
                        .padding(.horizontal, 12).frame(height: 24)
                        .background(Self.gold, in: Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            Text("Tap to add or remove. The first sits at the top of the ring.")
                .font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: CoucouWorkspaceStyle.gap), count: 3),
                      spacing: CoucouWorkspaceStyle.gap) {
                ForEach(SeedAction.allCases, id: \.self) { action in chip(action) }
            }
        }
    }

    private func chip(_ action: SeedAction) -> some View {
        let index = store.slots.firstIndex(of: action)
        let on = index != nil
        let full = !on && store.slots.count >= SeedRingStore.capacity
        return Button {
            SoundEngine.shared.play(on ? "close" : "pop")
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { store.toggle(action) }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: action.symbol).font(.system(size: 11, weight: .semibold))
                    .foregroundColor(on ? Self.gold : Color(hex: "#8E939C")).frame(width: 16)
                Text(action.title).font(.system(size: 11, weight: .medium))
                    .foregroundColor(on ? Color(hex: "#F5F6F8") : Color(hex: "#8E939C")).lineLimit(1)
                Spacer(minLength: 0)
                if let index {
                    Text("\(index + 1)").font(.system(size: 9.5, weight: .bold).monospacedDigit()).foregroundColor(.black)
                        .frame(width: 16, height: 16).background(Self.gold, in: Circle())
                }
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 10).fill(on ? Color(hex: "#1C1A12") : Color(hex: "#0E0F11")))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? Self.gold.opacity(0.45) : Color.white.opacity(0.05), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .opacity(full ? 0.4 : 1)
        .disabled(full)
        .accessibilityLabel(action.title)
        .accessibilityValue(index.map { "In the ring, position \($0 + 1)" } ?? "Not in the ring")
    }
}
#endif
