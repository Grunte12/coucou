#if COUCOU_HUB
import SwiftUI
import AppKit

// MARK: - Agent timeline (swimlanes)
//
// Replaces the Trail list. One lane per agent, a curve per message, newest at
// the right next to "now". Hover brightens a curve; a click selects it, dims
// the rest and slides a small card up from the bottom. "Open" hands the
// message to the existing detail view (bodies and Allow/Deny stay there).
// Presentation only: it never claims, sends or decides anything.

extension Notification.Name {
    /// Seed glances toward the timeline (a message arrived or was selected).
    static let seedGlance = Notification.Name("seedGlance")
    /// Seed glances toward something the user just did. object: NSValue(size:), a direction from Seed.
    static let seedNotice = Notification.Name("seedNotice")
}

/// Trackpad and wheel scrolling over the timeline, without a system scroll view.
/// A local monitor only consumes events whose pointer is inside `frame`.
@MainActor
final class SeedWheelMonitor: ObservableObject {
    var frame: CGRect = .zero
    var onScroll: ((CGFloat) -> Void)?
    private var token: Any?

    func start() {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            let used = MainActor.assumeIsolated { () -> Bool in
                guard let content = event.window?.contentView else { return false }
                // SwiftUI's global space is the window's content, top-left origin.
                let p = event.locationInWindow
                guard self.frame.contains(CGPoint(x: p.x, y: content.bounds.height - p.y)) else { return false }
                let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
                var delta = abs(dx) >= abs(dy) ? dx : dy
                if !event.hasPreciseScrollingDeltas { delta *= 8 }
                if delta != 0 { self.onScroll?(delta) }
                return true
            }
            return used ? nil : event
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}

/// Small helper so any view can tell Seed where the user just acted.
enum SeedReaction {
    static func notice(dx: CGFloat, dy: CGFloat) {
        NotificationCenter.default.post(name: .seedNotice, object: NSValue(size: NSSize(width: dx, height: dy)))
    }
}

struct SeedTimelineView: View {
    let transfers: [HubTincanTraceSummary]
    let heldIDs: Set<String>
    let freshIDs: Set<String>
    /// Lane to emphasise (from an agent's Timeline button); nil shows all.
    @Binding var focusAgentID: String?
    let busy: Bool
    let onOpen: (HubTincanTraceSummary) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedID: String?
    @State private var hoveredID: String?
    @State private var pan: CGFloat = 0
    @State private var dragStart: CGFloat?
    @StateObject private var wheel = SeedWheelMonitor()

    private static let labelWidth: CGFloat = 112
    private static let axisHeight: CGFloat = 16
    private static let gold = Color(hex: "#F5C542")
    private static let dim = Color(hex: "#6B7079")

    private var inputs: [SeedTimelineInput] {
        transfers.map {
            SeedTimelineInput(id: $0.requestID, sender: $0.sender, recipient: $0.recipient, state: $0.state,
                              held: heldIDs.contains($0.requestID), date: CoucouHubFormat.date($0.activityAt))
        }
    }

    private var selected: HubTincanTraceSummary? {
        transfers.first { $0.requestID == selectedID }
    }

    private func spring(_ response: Double = 0.32, _ damping: Double = 0.84) -> Animation? {
        reduceMotion ? nil : .spring(response: response, dampingFraction: damping)
    }

    var body: some View {
        GeometryReader { bounds in
            let plotWidth = max(0, bounds.size.width - Self.labelWidth)
            let layout = SeedTimelineLayout.make(inputs, minWidth: plotWidth)
            let cardHeight: CGFloat = selected == nil ? 0 : 58
            let plotHeight = max(0, bounds.size.height - Self.axisHeight - (cardHeight > 0 ? cardHeight + 8 : 0))
            let laneHeight = layout.lanes.isEmpty ? 32 : min(40, max(20, plotHeight / CGFloat(layout.lanes.count)))
            let lanesHeight = laneHeight * CGFloat(layout.lanes.count)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 0) {
                    laneLabels(layout, laneHeight: laneHeight)
                        .frame(width: Self.labelWidth, height: lanesHeight + Self.axisHeight, alignment: .topLeading)
                    plot(layout, laneHeight: laneHeight, height: lanesHeight + Self.axisHeight, width: plotWidth)
                }
                if let selected {
                    card(selected)
                        .frame(height: cardHeight)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(width: bounds.size.width, height: bounds.size.height, alignment: .topLeading)
        }
        .onChange(of: transfers.map(\.requestID)) { _, ids in
            if let selectedID, !ids.contains(selectedID) { self.selectedID = nil }
        }
    }

    // MARK: Lanes

    private func laneLabels(_ layout: SeedTimelineLayout, laneHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(layout.lanes.enumerated()), id: \.element) { _, id in
                let on = focusAgentID == nil || focusAgentID == id
                Button {
                    SoundEngine.shared.play("tick")
                    withAnimation(spring()) { focusAgentID = focusAgentID == id ? nil : id }
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: CoucouHubFormat.color(for: id))).frame(width: 7, height: 7)
                        Text(CoucouHubFormat.display(id))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(on ? Color(hex: "#E7E9EC") : Self.dim)
                            .lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .frame(height: laneHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(CoucouHubFormat.display(id))
                .accessibilityHint(focusAgentID == id ? "Shows every lane" : "Highlights this agent's messages")
                .accessibilityAddTraits(focusAgentID == id ? .isSelected : [])
            }
        }
    }

    // MARK: Plot

    /// Our own horizontal pan instead of a system scroll view: no scroll bar can
    /// appear at the notch edge, and new messages never yank the view while
    /// the user reads history. `pan` is the distance back from "now".
    private func plot(_ layout: SeedTimelineLayout, laneHeight: CGFloat, height: CGFloat, width: CGFloat) -> some View {
        let animate = !reduceMotion && layout.edges.contains { $0.kind == .held }
        let maxPan = max(0, layout.width - width)
        let shown = min(pan, maxPan)
        let origin = maxPan - shown
        let toContent = { (p: CGPoint) in CGPoint(x: p.x + origin, y: p.y) }
        return ZStack(alignment: .bottomTrailing) {
            ZStack(alignment: .topLeading) {
                TimelineView(.animation(minimumInterval: 1 / 15, paused: !animate)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, size in draw(layout, laneHeight: laneHeight, size: size, ctx: &ctx, t: t) }
                }
                accessibilityTargets(layout, laneHeight: laneHeight)
            }
            .frame(width: layout.width, height: height, alignment: .topLeading)
            .offset(x: -origin)
            .frame(width: width, height: height, alignment: .topLeading)
            .clipped()
            .mask(LinearGradient(stops: [.init(color: shown < maxPan ? .clear : .black, location: 0),
                                         .init(color: .black, location: 0.06),
                                         .init(color: .black, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                let next: String?
                if case .active(let p) = phase { next = layout.hit(toContent(p), laneHeight: laneHeight)?.id } else { next = nil }
                if next != hoveredID { hoveredID = next }
            }
            // One gesture for both: a still press picks a curve, a drag pans.
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    guard abs(v.translation.width) > 4 else { return }
                    if dragStart == nil { dragStart = shown }
                    pan = clampPan((dragStart ?? shown) + v.translation.width, maxPan)
                }
                .onEnded { v in
                    if dragStart == nil { tap(layout.hit(toContent(v.location), laneHeight: laneHeight)?.id) }
                    dragStart = nil
                })
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { wheel.frame = g.frame(in: .global) }
                    .onChange(of: g.frame(in: .global)) { _, f in wheel.frame = f }
            })
            if shown > 24 {
                Button {
                    SoundEngine.shared.play("tick")
                    withAnimation(spring(0.5, 0.9)) { pan = 0 }
                } label: {
                    HStack(spacing: 3) {
                        Text("Now")
                        Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 10, weight: .semibold)).foregroundColor(.black)
                    .padding(.horizontal, 8).frame(height: 20)
                    .background(Self.gold, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, -2)
                .transition(.opacity)
                .accessibilityLabel("Jump to now")
            }
        }
        .onAppear {
            wheel.onScroll = { delta in pan = clampPan(pan + delta, maxPan) }
            wheel.start()
        }
        .onChange(of: maxPan) { old, new in
            // Reading history: keep the same messages in view as new ones arrive.
            if pan > 0 { pan = clampPan(pan + (new - old), new) }
            wheel.onScroll = { delta in pan = clampPan(pan + delta, new) }
        }
        .onDisappear { wheel.stop() }
        #if COUCOU_LAB
        .onReceive(NotificationCenter.default.publisher(for: .seedLabScroll)) { note in
            if let d = note.object as? CGFloat { pan = clampPan(pan + d, maxPan) }
        }
        #endif
    }

    private func clampPan(_ value: CGFloat, _ maxPan: CGFloat) -> CGFloat {
        min(max(0, value), maxPan)
    }

    private func tap(_ id: String?) {
        guard id != selectedID else {
            if id != nil { SoundEngine.shared.play("tick") }
            withAnimation(spring()) { selectedID = nil }
            return
        }
        guard let id else {
            if selectedID != nil { withAnimation(spring()) { selectedID = nil } }
            return
        }
        SoundEngine.shared.play("pop")
        NotificationCenter.default.post(name: .seedGlance, object: nil)
        withAnimation(spring()) { selectedID = id }
    }

    private func color(_ kind: SeedEdgeKind) -> Color {
        switch kind {
        case .held:     return Color(hex: "#F5A524")
        case .open:     return Color(hex: "#22D3EE")
        case .answered: return Color(hex: "#22C55E")
        case .failed:   return Color(hex: "#F4505E")
        }
    }

    private func draw(_ layout: SeedTimelineLayout, laneHeight: CGFloat, size: CGSize,
                      ctx: inout GraphicsContext, t: Double) {
        let lanesBottom = laneHeight * CGFloat(layout.lanes.count)
        // Lane guides.
        for i in layout.lanes.indices {
            let y = SeedTimelineLayout.laneY(i, laneHeight: laneHeight)
            var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(p, with: .color(.white.opacity(0.05)), lineWidth: 1)
        }
        // "Now": a soft gold line at the right edge.
        var now = Path()
        now.move(to: CGPoint(x: layout.nowX, y: 2)); now.addLine(to: CGPoint(x: layout.nowX, y: lanesBottom))
        ctx.stroke(now, with: .color(Self.gold.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        ctx.draw(Text("now").font(.system(size: 9, weight: .semibold)).foregroundColor(Self.gold.opacity(0.8)),
                 at: CGPoint(x: layout.nowX, y: lanesBottom + 8), anchor: .center)
        // Time labels, kept clear of "now".
        for tick in layout.ticks where tick.x < layout.nowX - 30 {
            ctx.draw(Text(tick.label).font(.system(size: 9).monospacedDigit()).foregroundColor(Self.dim),
                     at: CGPoint(x: tick.x, y: lanesBottom + 8), anchor: .leading)
        }

        let focusLane = focusAgentID.flatMap { layout.lanes.firstIndex(of: $0) }
        for e in layout.edges {
            let c = SeedTimelineLayout.curve(e, laneHeight: laneHeight)
            var path = Path(); path.move(to: c.0); path.addCurve(to: c.3, control1: c.1, control2: c.2)
            let isSelected = e.id == selectedID
            let isHovered = e.id == hoveredID
            let isFresh = freshIDs.contains(e.id)
            var alpha = 0.85
            if selectedID != nil && !isSelected { alpha = 0.22 }
            if let f = focusLane, e.from != f && e.to != f { alpha = min(alpha, 0.18) }
            if isHovered && !isSelected { alpha = max(alpha, 0.95) }
            let col = color(e.kind)
            let dash: [CGFloat] = e.kind == .failed ? [3, 3] : []
            // Glow under the selected, hovered or newly arrived curve.
            if isSelected || isHovered || isFresh {
                ctx.stroke(path, with: .color((isFresh && !isSelected ? Self.gold : col).opacity(isSelected ? 0.35 : 0.22)),
                           style: StrokeStyle(lineWidth: 7, lineCap: .round))
            }
            ctx.stroke(path, with: .color(col.opacity(alpha)),
                       style: StrokeStyle(lineWidth: isSelected ? 2.2 : 1.6, lineCap: .round, dash: dash))
            // Answered: a short hook turning back toward the sender.
            if e.kind == .answered && e.from != e.to {
                let back0 = c.3
                let back3 = CGPoint(x: c.3.x + 14, y: c.3.y + (c.0.y - c.3.y) * 0.3)
                var ret = Path(); ret.move(to: back0)
                ret.addQuadCurve(to: back3, control: CGPoint(x: back0.x + 12, y: back0.y))
                ctx.stroke(ret, with: .color(col.opacity(alpha * 0.5)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            }
            // Tail dot in the sender's colour, head dot in the state colour.
            let tail = layout.lanes[e.from]
            ctx.fill(Path(ellipseIn: CGRect(x: c.0.x - 2.5, y: c.0.y - 2.5, width: 5, height: 5)),
                     with: .color(Color(hex: CoucouHubFormat.color(for: tail)).opacity(alpha)))
            var r: CGFloat = isSelected ? 4 : 3.2
            if e.kind == .held && !reduceMotion {
                let breathe = (sin(t * 2.4 + Double(e.x) * 0.05) + 1) / 2
                ctx.fill(Path(ellipseIn: CGRect(x: c.3.x - 7, y: c.3.y - 7, width: 14, height: 14)),
                         with: .color(col.opacity(0.10 + 0.18 * breathe)))
                r += CGFloat(breathe) * 0.8
            }
            ctx.fill(Path(ellipseIn: CGRect(x: c.3.x - r, y: c.3.y - r, width: r * 2, height: r * 2)),
                     with: .color(col.opacity(max(alpha, 0.4))))
        }
    }

    /// Invisible per-curve elements so VoiceOver can read and pick each message.
    private func accessibilityTargets(_ layout: SeedTimelineLayout, laneHeight: CGFloat) -> some View {
        ForEach(layout.edges) { e in
            let c = SeedTimelineLayout.curve(e, laneHeight: laneHeight)
            let mid = SeedTimelineLayout.point(on: c, t: 0.5)
            Color.clear
                .frame(width: SeedTimelineLayout.run, height: max(12, abs(c.3.y - c.0.y)))
                .position(mid)
                .accessibilityElement()
                .accessibilityLabel(accessibilityText(e, layout: layout))
                .accessibilityAddTraits(e.id == selectedID ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { tap(e.id) }
                .allowsHitTesting(false)
        }
    }

    private func accessibilityText(_ e: SeedTimelineLayout.Edge, layout: SeedTimelineLayout) -> String {
        let from = CoucouHubFormat.display(layout.lanes[e.from])
        let to = CoucouHubFormat.display(layout.lanes[e.to])
        let state = transfers.first { $0.requestID == e.id }.map {
            heldIDs.contains($0.requestID) ? "held" : CoucouHubFormat.pretty($0.state)
        } ?? ""
        let time = e.date.map { $0.formatted(date: .omitted, time: .shortened) } ?? ""
        return [("\(from) to \(to)"), state, time].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    // MARK: Card

    private func card(_ entry: HubTincanTraceSummary) -> some View {
        let held = heldIDs.contains(entry.requestID)
        let kind = SeedEdgeKind.of(state: entry.state, held: held)
        let col = color(kind)
        return HStack(alignment: .center, spacing: 10) {
            Capsule().fill(col).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    agent(entry.sender)
                    Image(systemName: "arrow.right").font(.system(size: 8.5, weight: .bold)).foregroundColor(Self.dim)
                    agent(entry.recipient)
                    Text(held ? "Held" : CoucouHubFormat.stateWord(entry.state))
                        .font(.system(size: 10, weight: .semibold)).foregroundColor(col)
                    Text(CoucouHubFormat.relative(entry.activityAt))
                        .font(.system(size: 10).monospacedDigit()).foregroundColor(Self.dim)
                }
                .lineLimit(1)
                Text(entry.title.isEmpty ? "No title" : CoucouHubFormat.bounded(entry.title, limit: 140))
                    .font(.system(size: 11)).foregroundColor(Color(hex: "#C5C8CD"))
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 4)
            Button {
                SoundEngine.shared.play("pop")
                onOpen(entry)
            } label: {
                Text(held ? "Review" : "Open")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(held ? .black : Color(hex: "#F5F6F8"))
                    .padding(.horizontal, 12).frame(height: 26)
                    .background(held ? Color(hex: "#F5A524") : Color.white.opacity(0.09), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .opacity(busy ? 0.5 : 1)
            .accessibilityLabel(held ? "Review this held request" : "Open this message")
            Button {
                SoundEngine.shared.play("tick")
                withAnimation(spring()) { selectedID = nil }
            } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundColor(Self.dim)
                    .frame(width: 20, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#0E0F11")))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(col.opacity(0.25), lineWidth: 1))
    }

    private func agent(_ id: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(Color(hex: CoucouHubFormat.color(for: id))).frame(width: 6, height: 6)
            Text(CoucouHubFormat.display(CoucouHubFormat.bounded(id, limit: 24)))
                .font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
        }
    }
}
#endif
