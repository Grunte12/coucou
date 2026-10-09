import SwiftUI
import AppKit

// MARK: - Rice Motion Lab v3
//
// The real Swift mascot (RiceMotion + RicePainter) in a window you can play
// with: every state, every event, real pointer gaze and press squash, at the
// notch size or large. This replaces brand/rice/motion-lab.html (v2) as the
// place to review motion, because it runs the exact code the app ships.
//
//   scripts/seed-lab.sh --rice

@MainActor
enum RiceMotionLabWindow {
    static func open() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Seed · Rice Motion Lab v3"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.043, green: 0.043, blue: 0.051, alpha: 1)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: RiceMotionLabView())
        window.center()
        return window
    }
}

private struct LabEntry: Identifiable {
    let id: String
    let th: String
    let en: String
    let run: (RiceMotion) -> Void
}

struct RiceMotionLabView: View {
    @StateObject private var holder = RiceMotionHolder()
    @State private var revision = 0
    @State private var state: RiceState = .idle
    @State private var caption: (th: String, en: String) = ("พร้อมแล้ว", "Ready")
    @State private var large = true
    @State private var reduced = false
    @State private var pressing = false

    private var motion: RiceMotion { holder.motion }

    private static let states: [(RiceState, String, String)] = [
        (.idle, "พร้อมแล้ว", "Ready"),
        (.thinking, "กำลังคิด…", "Thinking…"),
        (.working, "กำลังทำงาน…", "Working…"),
        (.sending, "กำลังส่ง…", "Sending…"),
        (.approval, "รอคุณอนุมัติ", "Needs your OK"),
        (.done, "เสร็จแล้ว ขอบคุณครับ", "Done, thank you"),
        (.resting, "พักอยู่", "Resting"),
    ]

    private var events: [LabEntry] {
        [
            LabEntry(id: "Wake + wai", th: "สวัสดีครับ", en: "Sawasdee — hello") { $0.wakeAndGreet() },
            LabEntry(id: "Wai", th: "สวัสดีครับ", en: "Sawasdee — hello") { $0.greet() },
            LabEntry(id: "New request", th: "มีคำขอใหม่", en: "New request") { $0.newApproval() },
            LabEntry(id: "File hover", th: "วางได้เลย", en: "Drop it here") { m in
                m.startHover()
            },
            LabEntry(id: "Drop in", th: "รับไว้แล้ว", en: "Got it") { m in
                if m.fileNow() == nil { m.startHover() }
                m.dropIn()
            },
            LabEntry(id: "Shelf full", th: "ขอโทษนะ ที่เต็มแล้ว", en: "Sorry, shelf is full") { $0.reject() },
            LabEntry(id: "Copied", th: "คัดลอกแล้ว", en: "Copied") { $0.copied() },
            LabEntry(id: "Glance", th: "ดูเมนู", en: "Looks at the rail") { $0.glanceToRail() },
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            stage
            controls
        }
        .frame(minWidth: 720, minHeight: 540)
        .background(Color(red: 0.043, green: 0.043, blue: 0.051))
        .onAppear { motion.select(.idle); bump() }
    }

    // MARK: Stage

    private var stage: some View {
        GeometryReader { geo in
            let side = large ? min(geo.size.width, geo.size.height) * 0.9 : 84
            let box = large ? side * 0.62 : 52
            ZStack {
                // Notch-coloured card behind the small size, so it reads as it does in the app.
                if !large {
                    RoundedRectangle(cornerRadius: 22).fill(Color(red: 0.086, green: 0.09, blue: 0.1))
                        .frame(width: 180, height: 140)
                }
                RiceMascotView(motion: motion, box: box, paused: false, revision: revision)
                    .frame(width: side, height: side)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                guard !pressing else { return }
                                pressing = true; motion.pressDown(); bump()
                            }
                            .onEnded { _ in pressing = false; motion.pressUp(); bump() }
                    )
                VStack(spacing: 4) {
                    Spacer()
                    Text(caption.th).font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
                    Text(caption.en).font(.system(size: 12)).foregroundColor(Color(white: 0.55))
                }
                .padding(.bottom, 18)
                .allowsHitTesting(false)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let p):
                    // Scale the pointer to notch distances so gaze behaves as in the app.
                    let k = large ? 52 / box : 1
                    let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                    holder.pointer(CGPoint(x: c.x + (p.x - c.x) * k, y: c.y + (p.y - c.y) * k), centre: c)
                case .ended:
                    holder.pointer(nil, centre: .zero)
                }
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("State · สถานะ") {
                ForEach(Self.states, id: \.0) { s, th, en in
                    chip(s.name.capitalized, on: state == s) {
                        state = s; caption = (th, en)
                        motion.select(s, replay: true); bump()
                    }
                }
            }
            row("Event · เหตุการณ์") {
                ForEach(events) { e in
                    chip(e.id, on: false) { caption = (e.th, e.en); e.run(motion); bump() }
                }
            }
            HStack(spacing: 8) {
                chip(large ? "Size · Large" : "Size · Notch (52 pt)", on: !large) { large.toggle() }
                chip("Reduce Motion", on: reduced) {
                    reduced.toggle(); motion.setReduced(reduced); bump()
                }
                Spacer()
                Text("Move the pointer to see the gaze · press the grain to squash")
                    .font(.system(size: 11)).foregroundColor(Color(white: 0.45))
            }
        }
        .padding(16)
        .background(Color(red: 0.075, green: 0.078, blue: 0.086))
    }

    private func row<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundColor(Color(white: 0.45))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { content() }
            }
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(on ? .black : Color(white: 0.85))
                .padding(.horizontal, 11).frame(height: 26)
                .background(on ? Color(red: 1, green: 0.84, blue: 0.3) : Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func bump() { revision &+= 1 }
}
