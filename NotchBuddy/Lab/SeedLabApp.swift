import SwiftUI
import AppKit
import Darwin

// MARK: - Seed Lab
//
// Runs the real notch views (IslandRootView, expanded on the agent workspace)
// in an ordinary 720×320 window with fixture data, executes a script, writes
// snapshots of its own window only, and quits. No screen capture, no
// Accessibility permission, no network, no Keychain, no real clipboard.
//
//   SeedLab --out DIR (--script FILE | --run "cmd; cmd; …") [--visible]
//
// Coordinates are window points from the top-left of the 720×320 panel; the
// expanded notch is 640 wide, so its left edge is x = 40. Snapshots are @2x.

@main
enum SeedLabMain {
    static func main() {
        setbuf(stdout, nil)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = SeedLabDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class SeedLabDelegate: NSObject, NSApplicationDelegate {
    private var runner: SeedLabRunner?
    private var riceWindow: NSWindow?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { riceWindow != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if args.contains("--rice") {
            // Interactive Rice Motion Lab: an ordinary app window for a person to play with.
            NSApp.setActivationPolicy(.regular)
            let menu = NSMenu(), item = NSMenuItem()
            item.submenu = NSMenu()
            item.submenu?.addItem(withTitle: "Quit Seed Lab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            menu.addItem(item)
            NSApp.mainMenu = menu
            let window = RiceMotionLabWindow.open()
            riceWindow = window
            if let i = args.firstIndex(of: "--snap"), i + 1 < args.count {
                // Agent check: render the lab window behind everything, save it, quit.
                let path = args[i + 1]
                window.orderBack(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if let v = window.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                        v.cacheDisplay(in: v.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                    }
                    NSApp.terminate(nil)
                }
                return
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        let out = URL(fileURLWithPath: value("--out") ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("seed-lab").path)
        var lines: [String] = []
        if let path = value("--script"), let text = try? String(contentsOfFile: path, encoding: .utf8) {
            lines += text.components(separatedBy: .newlines)
        }
        if let inline = value("--run") { lines += inline.components(separatedBy: ";") }
        if lines.isEmpty { lines = ["snap default"] }
        let runner = SeedLabRunner(out: out, visible: args.contains("--visible"))
        self.runner = runner
        Task { await runner.run(lines); NSApp.terminate(nil) }
    }
}

@MainActor
final class SeedLabRunner {
    let out: URL
    let window: NSPanel
    private let state = AppState.shared
    private let integration = CoucouHubIntegration.shared
    private var outputs: [String] = []
    private var failures: [String] = []
    private var pointer = CGPoint(x: -1, y: -1)

    init(out: URL, visible: Bool) {
        self.out = out
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let size = NSSize(width: 720, height: 320)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        window = NSPanel(contentRect: NSRect(x: screen.minX + 8, y: screen.minY + 8,
                                             width: size.width, height: size.height),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.backgroundColor = NSColor(white: 0.12, alpha: 1)
        window.isOpaque = true
        window.hasShadow = false
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false
        // Behind other windows unless --visible: the lab never covers what the
        // user is doing. Rendering is read from the view, not the screen.
        window.level = visible ? .floating : NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]

        state.soundEnabled = false
        state.notchWidth = 185
        state.notchHeight = 32
        state.hasNotch = true

        let hosting = NSHostingView(rootView: IslandRootView().environmentObject(state))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        if visible { window.orderFrontRegardless() } else { window.orderBack(nil) }
    }

    // MARK: Script

    func run(_ lines: [String]) async {
        log("out \(out.path)")
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            do { try await perform(line) } catch {
                failures.append("\(line): \(error)")
                log("FAIL \(line): \(error)")
            }
        }
        let report: [String: Any] = ["outputs": outputs, "failures": failures,
                                     "decisions": SeedLabFixtureAPI.shared.decisions]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: out.appendingPathComponent("report.json"))
        }
        log("done \(outputs.count) outputs, \(failures.count) failures")
    }

    struct LabError: Error, CustomStringConvertible { let description: String }

    private func perform(_ line: String) async throws {
        let words = Self.split(line)
        guard let cmd = words.first else { return }
        let a = Array(words.dropFirst())
        func num(_ i: Int, _ fallback: Double? = nil) throws -> Double {
            if i < a.count, let v = Double(a[i]) { return v }
            if let fallback { return fallback }
            throw LabError(description: "\(cmd) needs a number at position \(i + 1)")
        }
        func word(_ i: Int) throws -> String {
            guard i < a.count else { throw LabError(description: "\(cmd) needs an argument") }
            return a[i]
        }

        switch cmd {
        case "expand":
            state.view = .linkHub
            state.mode = .expanded
            await settle(0.8)
        case "alert":
            // A hook alert card with fixture data: `alert approval|question|finished|clear`.
            switch try word(0) {
            case "approval":
                state.pendingQuestion = nil
                state.pendingApproval = ApprovalInfo(sessionId: "lab", tool: "Bash",
                    command: "rm -rf node_modules && npm install --legacy-peer-deps",
                    inputKey: "", pillId: a.count > 1 ? a[1] : "integration_claude")
                state.view = .approval
            case "question":
                state.pendingApproval = nil
                state.pendingQuestion = AskQuestion(questions: [
                    AskQuestionItem(question: "Which database should the new service use?", header: "Database",
                                    options: [.init(label: "Postgres", description: "Relational, already in prod"),
                                              .init(label: "SQLite", description: "File-based, simplest"),
                                              .init(label: "Redis", description: "In-memory")],
                                    multiSelect: false),
                    AskQuestionItem(question: "Which checks should run before merge?", header: "CI",
                                    options: [.init(label: "Unit tests", description: ""),
                                              .init(label: "Lint", description: ""),
                                              .init(label: "Type check", description: "")],
                                    multiSelect: true)])
                state.view = .question
            case "finished":
                state.pendingApproval = nil; state.pendingQuestion = nil
                if let i = state.tasks.firstIndex(where: { $0.id == "integration_claude" }) {
                    state.tasks[i].finalLine = "Refactored the auth middleware and added 14 tests, all passing."
                }
                state.focusId = "integration_claude"
                state.view = .finished
            default:
                state.pendingApproval = nil; state.pendingQuestion = nil
                state.view = .linkHub
            }
            state.mode = .expanded
            await settle(0.9)
        case "collapse":
            state.mode = .compact
            await settle(0.6)
        case "fixture":
            guard let f = SeedLabFixture(rawValue: try word(0)) else {
                throw LabError(description: "fixtures: \(SeedLabFixture.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            SeedLabFixtureAPI.shared.fixture = f
            integration.model.refresh()
            integration.model.refreshOperatorTasks()
            await settle(0.4)
        case "section":
            guard let s = CoucouWorkspaceSection(rawValue: try word(0)) else {
                throw LabError(description: "sections: agents, shelf, clipboard, usage")
            }
            NotificationCenter.default.post(name: .coucouWorkspaceShowSection, object: s)
            await settle(0.4)
        case "usage":
            try setUsage(try word(0))
        case "relay":
            state.planRelayInstalled = try word(0) == "on"
        case "drop":
            try drop(count: Int(try num(0, 1)))
            await settle(0.3)
        case "dropin":
            // dropin text "…" | link URL | image: a non-file drop, as from an agent app.
            let pb = NSPasteboard(name: NSPasteboard.Name("com.grunte.seed.lab.drag"))
            pb.clearContents()
            switch try word(0) {
            case "text":  pb.setString(a.dropFirst().joined(separator: " "), forType: .string)
            case "link":  pb.writeObjects([URL(string: try word(1))! as NSURL])
            case "image":
                let img = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { r in
                    NSColor.systemYellow.setFill(); NSBezierPath(ovalIn: r).fill(); return true
                }
                pb.writeObjects([img])
            default: throw LabError(description: "dropin text|link|image")
            }
            SeedDropMaterializer.folderOverride = out.appendingPathComponent("drops")
            let urls = await SeedDropMaterializer.begin(from: pb)()
            log("dropin → \(urls.map(\.lastPathComponent))")
            if !urls.isEmpty { CoucouHubIntegration.shared.stageFiles(urls) }
            await settle(0.3)
        case "pin":
            // pin: makes a small fixture project in the output folder and pins it (lab defaults only).
            let root = out.appendingPathComponent("folders-fixture/seed-app", isDirectory: true)
            let fm = FileManager.default
            try fm.createDirectory(at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true)
            for (i, name) in ["README.md", "design-notes.txt", "Package.swift", "Sources/App.swift", "Sources/Seed.swift"].enumerated() {
                let url = root.appendingPathComponent(name)
                try "fixture \(name)\n".write(to: url, atomically: true, encoding: .utf8)
                try fm.setAttributes([.modificationDate: Date().addingTimeInterval(Double(-i) * 900)], ofItemAtPath: url.path)
            }
            log("pinned \(SeedFolderStore.shared.pin(root))")
        case "unlink":
            // Deletes one lab fixture file so the shelf shows a missing original.
            let dir = out.appendingPathComponent("shelf-fixtures")
            if let first = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted().first {
                try FileManager.default.removeItem(at: dir.appendingPathComponent(first))
                log("unlinked \(first)")
            }
        case "dragover":
            let on = try word(0) == "on"
            state.fileDragOver = on
            if on { NotificationCenter.default.post(name: .coucouWorkspaceShowSection, object: CoucouWorkspaceSection.shelf) }
            await settle(0.3)
        case "copy":
            try copy(kind: try word(0), payload: a.dropFirst().joined(separator: " "))
        case "history":
            if try word(0) == "on" { integration.clipboard.enableChangeMonitoring() }
            else { integration.clipboard.disableChangeMonitoring() }
        case "move":
            try await move(to: CGPoint(x: try num(0), y: try num(1)), steps: Int(try num(2, 12)))
        case "leave":
            try await move(to: CGPoint(x: 700, y: 310), steps: 6)
            send(.mouseExited, pointer)
            NotificationCenter.default.post(name: .seedLabPointer, object: nil)
        case "click":
            let p = CGPoint(x: try num(0), y: try num(1))
            try await move(to: p, steps: 4)
            send(.leftMouseDown, p)
            try await Task.sleep(for: .milliseconds(70))
            send(.leftMouseUp, p)
            await settle(0.35)
        case "press":
            let p = CGPoint(x: try num(0), y: try num(1))
            send(.leftMouseDown, p)
            try await Task.sleep(for: .seconds(try num(2, 0.4)))
            send(.leftMouseUp, p)
        case "flick":
            // flick x1 y1 x2 y2 [seconds]: press, drag in steps, release (Seed's Action Ring flick).
            let a0 = CGPoint(x: try num(0), y: try num(1)), a1 = CGPoint(x: try num(2), y: try num(3))
            let seconds = try num(4, 0.3)
            send(.leftMouseDown, a0)
            for i in 1...10 {
                let k = CGFloat(i) / 10
                let p = CGPoint(x: a0.x + (a1.x - a0.x) * k, y: a0.y + (a1.y - a0.y) * k)
                send(.leftMouseDragged, p)
                try await Task.sleep(for: .seconds(seconds / 10))
            }
            send(.leftMouseUp, a1)
        case "scroll":
            scroll(at: CGPoint(x: try num(0), y: try num(1)), dx: try num(3, 0), dy: try num(2))
            await settle(0.3)
        case "wait":
            try await Task.sleep(for: .seconds(try num(0)))
        case "snap":
            try snap(try word(0), grid: a.contains("grid"), crop: crop(a))
        case "riceref":
            // Deterministic frames of Seed in every pose, to compare renderers: `riceref`.
            try riceReference(layered: a.first == "layers")
        case "settings":
            // Seed's Settings window on one page, rendered behind everything: `settings agents 900`.
            try await settingsSnap(try word(0), height: try num(1, 560))
        case "film":
            try await film(try word(0), seconds: try num(1, 2), fps: try num(2, 8), columns: Int(try num(3, 4)), crop: crop(a))
        case "cpu":
            try await cpu(seconds: try num(0, 5), label: a.count > 1 ? a[1] : "cpu")
        case "log":
            log(a.joined(separator: " "))
        case "scrollers":
            // Every NSScroller in the window: stray scroll bars are easy to miss in a snapshot.
            func walk(_ v: NSView) {
                let name = String(describing: type(of: v))
                if name.contains("Scroll") && !(v is NSScroller) {
                    let f = v.convert(v.bounds, to: nil)
                    log("view \(name) \(Int(f.minX)),\(Int(window.contentView!.bounds.height - f.maxY)) \(Int(f.width))x\(Int(f.height)) hidden=\(v.isHidden)")
                }
                if let s = v as? NSScroller, let sv = s.superview as? NSScrollView {
                    let f = s.convert(s.bounds, to: nil)
                    log("scroller \(Int(f.minX)),\(Int(window.contentView!.bounds.height - f.maxY)) \(Int(f.width))x\(Int(f.height)) hidden=\(s.isHidden) alpha=\(s.alphaValue) style=\(s.scrollerStyle.rawValue) hasH=\(sv.hasHorizontalScroller) hasV=\(sv.hasVerticalScroller) autohide=\(sv.autohidesScrollers) in \(type(of: sv))")
                }
                v.subviews.forEach(walk)
            }
            if let root = window.contentView { walk(root) }
        default:
            throw LabError(description: "unknown command")
        }
    }

    /// `crop=x,y,w,h` in window points.
    private func crop(_ a: [String]) -> CGRect? {
        guard let token = a.first(where: { $0.hasPrefix("crop=") }) else { return nil }
        let v = token.dropFirst(5).split(separator: ",").compactMap { Double($0) }
        return v.count == 4 ? CGRect(x: v[0], y: v[1], width: v[2], height: v[3]) : nil
    }

    /// Splits on spaces, keeping "quoted text" together.
    static func split(_ line: String) -> [String] {
        var words: [String] = [], current = "", quoted = false
        for c in line {
            if c == "\"" { quoted.toggle(); continue }
            if c == " " && !quoted { if !current.isEmpty { words.append(current); current = "" } }
            else { current.append(c) }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    private func settle(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func log(_ text: String) { print("[seed-lab] \(text)") }

    // MARK: Data

    private func setUsage(_ kind: String) throws {
        let now = Date()
        switch kind {
        case "none":
            state.claudePlanUsage = nil
        case "fresh":
            state.claudePlanUsage = PlanUsage(fiveHour: PlanWindow(usedPct: 42, resetsAt: now.addingTimeInterval(2 * 3600)),
                                              sevenDay: PlanWindow(usedPct: 71, resetsAt: now.addingTimeInterval(3 * 86400)),
                                              updatedAt: now.addingTimeInterval(-90))
        case "high":
            state.claudePlanUsage = PlanUsage(fiveHour: PlanWindow(usedPct: 93, resetsAt: now.addingTimeInterval(40 * 60)),
                                              sevenDay: PlanWindow(usedPct: 88, resetsAt: now.addingTimeInterval(86400)),
                                              updatedAt: now.addingTimeInterval(-30))
        case "stale":
            state.claudePlanUsage = PlanUsage(fiveHour: PlanWindow(usedPct: 55, resetsAt: now.addingTimeInterval(3600)),
                                              sevenDay: PlanWindow(usedPct: 60, resetsAt: now.addingTimeInterval(2 * 86400)),
                                              updatedAt: now.addingTimeInterval(-6 * 3600))
        case "passed":
            state.claudePlanUsage = PlanUsage(fiveHour: PlanWindow(usedPct: 80, resetsAt: now.addingTimeInterval(-600)),
                                              sevenDay: PlanWindow(usedPct: 64, resetsAt: now.addingTimeInterval(4 * 86400)),
                                              updatedAt: now.addingTimeInterval(-3 * 3600))
        default:
            throw LabError(description: "usage: none, fresh, high, stale, passed")
        }
    }

    private var dropped = 0
    private func drop(count: Int) throws {
        let dir = out.appendingPathComponent("shelf-fixtures")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let names = ["notch-layout-notes.md", "rice-mascot-v2.svg", "usage-export.csv", "Screenshot 2026-10-07 at 09.41.png",
                     "handoff-receipt.pdf", "clipboard-store.swift", "a-very-long-file-name-that-should-truncate-in-the-middle-nicely.txt"]
        var urls: [URL] = []
        for _ in 0..<count {
            let name = names[dropped % names.count]
            let unique = dropped < names.count ? name : "\(dropped)-\(name)"
            let url = dir.appendingPathComponent(unique)
            try Data(repeating: 0x61, count: 1200 * (dropped + 1)).write(to: url)
            urls.append(url)
            dropped += 1
        }
        integration.stageFiles(urls)
        log("dropped \(count), shelf has \(integration.workspace.files.count)\(integration.fileShelfError.map { ", error: \($0)" } ?? "")")
    }

    private func copy(kind: String, payload: String) throws {
        let pb = SeedLab.pasteboard
        pb.clearContents()
        switch kind {
        case "text":
            pb.setString(payload.isEmpty ? "Seed Lab fixture text" : payload, forType: .string)
        case "url":
            let link = payload.isEmpty ? "https://developer.apple.com/design/human-interface-guidelines/motion" : payload
            pb.setString(link, forType: .URL)
            pb.setString(link, forType: .string)
        case "image":
            let image = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
                NSColor.systemOrange.setFill(); NSBezierPath(ovalIn: rect.insetBy(dx: 6, dy: 6)).fill(); return true
            }
            pb.writeObjects([image])
        case "file":
            let dir = out.appendingPathComponent("shelf-fixtures")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(payload.isEmpty ? "copied-file.txt" : payload)
            try Data("lab".utf8).write(to: url)
            pb.writeObjects([url as NSURL])
        case "private":
            pb.setString("hunter2", forType: .string)
            pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        case "clear":
            break
        default:
            throw LabError(description: "copy: text, url, image, file, private, clear")
        }
        log("lab pasteboard changeCount \(pb.changeCount)")
    }

    // MARK: Events (in-process; no Accessibility permission involved)

    private func windowPoint(_ p: CGPoint) -> NSPoint { NSPoint(x: p.x, y: window.frame.height - p.y) }

    private func send(_ type: NSEvent.EventType, _ p: CGPoint) {
        let event: NSEvent?
        if type == .mouseEntered || type == .mouseExited {
            event = NSEvent.enterExitEvent(with: type, location: windowPoint(p), modifierFlags: [],
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil,
                                           eventNumber: 0, trackingNumber: 0, userData: nil)
        } else {
            event = NSEvent.mouseEvent(with: type, location: windowPoint(p), modifierFlags: [],
                                       timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                       clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)
        }
        if let event { window.sendEvent(event) }
    }

    private func move(to target: CGPoint, steps: Int) async throws {
        let start = pointer.x < 0 ? CGPoint(x: target.x, y: 310) : pointer
        let n = max(1, steps)
        for i in 1...n {
            let t = Double(i) / Double(n)
            let e = t * t * (3 - 2 * t)
            let p = CGPoint(x: start.x + (target.x - start.x) * e, y: start.y + (target.y - start.y) * e)
            send(.mouseMoved, p)
            NotificationCenter.default.post(name: .seedLabPointer, object: NSValue(point: NSPoint(
                x: p.x - SeedLab.paneOrigin.x, y: p.y - SeedLab.paneOrigin.y)))
            pointer = p
            try await Task.sleep(for: .milliseconds(16))
        }
    }

    private func scroll(at p: CGPoint, dx: Double, dy: Double) {
        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                               wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0) else { return }
        cg.location = window.convertPoint(toScreen: windowPoint(p))
        if let event = NSEvent(cgEvent: cg) {
            window.contentView?.hitTest(windowPoint(p))?.scrollWheel(with: event)
        }
        NotificationCenter.default.post(name: .seedLabScroll, object: CGFloat(abs(dx) >= abs(dy) ? dx : dy))
    }

    // MARK: Capture (own window only)

    private func image(scale: CGFloat = 2, crop: CGRect? = nil) -> NSBitmapImageRep? {
        guard let view = window.contentView else { return nil }
        // Window points from the top-left → view rect.
        let rect = crop.map { view.isFlipped ? $0 : CGRect(x: $0.minX, y: view.bounds.height - $0.maxY, width: $0.width, height: $0.height) } ?? view.bounds
        let size = rect.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        view.displayIfNeeded()
        view.cacheDisplay(in: rect, to: rep)
        return rep
    }

    private func write(_ rep: NSBitmapImageRep, _ name: String) throws {
        let url = out.appendingPathComponent(name)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw LabError(description: "png encode") }
        try data.write(to: url)
        outputs.append(url.path)
        log("wrote \(url.path)")
    }

    private func riceReference(layered: Bool) throws {
        typealias Setup = (String, (RiceMotion) -> Void, Double)
        let cases: [Setup] = [
            ("idle", { $0.select(.idle) }, 2.0),
            ("working", { $0.select(.working) }, 2.3),
            ("approval", { $0.select(.approval) }, 2.0),
            ("done", { $0.select(.done) }, 1.0),
            ("resting", { $0.select(.resting) }, 2.5),
            ("copied", { m in m.select(.idle); m.copied() }, 0.35),
            ("ringopen", { m in m.select(.idle); m.ringOpen() }, 0.4),
            ("hover", { m in m.select(.idle); m.startHover() }, 0.5),
            ("drop", { m in m.select(.idle); m.startHover(); m.dropIn() }, 0.45),
            ("press", { m in m.select(.idle); m.pressDown() }, 0.2),
        ]
        for (name, setup, seconds) in cases {
            for (label, box, side) in [("big", CGFloat(52), CGFloat(84)), ("small", CGFloat(26), CGFloat(42))] {
                let m = RiceMotion(seed: 7)
                m.step(1.0 / 60)
                setup(m)
                var t = 0.0
                while t < seconds { m.step(1.0 / 60); t += 1.0 / 60 }
                let render = layered ? RiceRender.layeredImage : RiceRender.image
                guard let img = render(m, box, CGSize(width: side, height: side), 2) else {
                    throw LabError(description: "no image for \(name)")
                }
                let rep = NSBitmapImageRep(cgImage: img)
                try write(rep, "rice-\(name)-\(label).png")
            }
        }
    }

    private func settingsSnap(_ page: String, height: Double) async throws {
        guard SeedSettingsPage(rawValue: page) != nil else { throw LabError(description: "unknown settings page \(page)") }
        UserDefaults.standard.set(page, forKey: "seed.settings.page")
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: height),
                           styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.isReleasedWhenClosed = false
        win.contentView = NSHostingView(rootView: SeedSettingsView())
        win.orderBack(nil)
        await settle(1.5)
        defer { win.close() }
        guard let v = win.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else {
            throw LabError(description: "no image")
        }
        v.cacheDisplay(in: v.bounds, to: rep)
        try write(rep, "settings-\(page).png")
    }

    private func snap(_ name: String, grid: Bool, crop: CGRect?) throws {
        guard let rep = image(scale: crop == nil ? 2 : 3, crop: crop) else { throw LabError(description: "no image") }
        if grid { drawGrid(on: rep) }
        try write(rep, "\(name).png")
    }

    /// 20 pt grid with a label every 100 pt, so click targets can be read off a snapshot.
    private func drawGrid(on rep: NSBitmapImageRep) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let size = rep.size
        for x in stride(from: 0.0, through: Double(size.width), by: 20) {
            (x.truncatingRemainder(dividingBy: 100) == 0 ? NSColor.systemPink.withAlphaComponent(0.55)
                                                          : NSColor.systemPink.withAlphaComponent(0.18)).setFill()
            NSRect(x: x, y: 0, width: 0.5, height: Double(size.height)).fill()
        }
        for y in stride(from: 0.0, through: Double(size.height), by: 20) {
            (y.truncatingRemainder(dividingBy: 100) == 0 ? NSColor.systemPink.withAlphaComponent(0.55)
                                                          : NSColor.systemPink.withAlphaComponent(0.18)).setFill()
            NSRect(x: 0, y: y, width: Double(size.width), height: 0.5).fill()
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 7, weight: .bold),
                                                    .foregroundColor: NSColor.systemPink]
        for x in stride(from: 100.0, to: Double(size.width), by: 100) {
            NSString(string: "\(Int(x))").draw(at: NSPoint(x: x + 1, y: Double(size.height) - 9), withAttributes: attrs)
        }
        for y in stride(from: 100.0, to: Double(size.height), by: 100) {
            NSString(string: "\(Int(y))").draw(at: NSPoint(x: 1, y: Double(size.height) - y - 9), withAttributes: attrs)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Frames over time in one contact sheet, to judge motion from a single image.
    private func film(_ name: String, seconds: Double, fps: Double, columns: Int, crop: CGRect?) async throws {
        let count = max(1, Int(seconds * fps))
        var frames: [NSBitmapImageRep] = []
        for _ in 0..<count {
            if let rep = image(scale: crop == nil ? 1 : 2, crop: crop) { frames.append(rep) }
            try await Task.sleep(for: .seconds(1 / fps))
        }
        guard let first = frames.first else { throw LabError(description: "no frames") }
        let w = first.pixelsWide, h = first.pixelsHigh
        let cols = max(1, min(columns, frames.count)), rows = (frames.count + cols - 1) / cols
        guard let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w * cols, pixelsHigh: h * rows,
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
        NSColor.black.setFill(); NSRect(x: 0, y: 0, width: w * cols, height: h * rows).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
                                                    .foregroundColor: NSColor.systemPink]
        for (i, frame) in frames.enumerated() {
            let x = (i % cols) * w, y = (rows - 1 - i / cols) * h
            frame.draw(in: NSRect(x: x, y: y, width: w, height: h))
            NSString(string: String(format: "%d  %.2fs", i, Double(i) / fps))
                .draw(at: NSPoint(x: x + 6, y: y + 6), withAttributes: attrs)
        }
        NSGraphicsContext.restoreGraphicsState()
        try write(sheet, "\(name).png")
    }

    // MARK: CPU (this process only)

    private func cpuTime() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func s(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return s(usage.ru_utime) + s(usage.ru_stime)
    }

    private func cpu(seconds: Double, label: String) async throws {
        let wall0 = ProcessInfo.processInfo.systemUptime, cpu0 = cpuTime(), f0 = RiceLayerView.framesDrawn
        try await Task.sleep(for: .seconds(seconds))
        let wall = ProcessInfo.processInfo.systemUptime - wall0
        let pct = (cpuTime() - cpu0) / wall * 100
        let fps = Double(RiceLayerView.framesDrawn - f0) / wall
        let m = RiceMotionHolder.shared.motion
        let moving = RiceMotion.Ch.allCases.filter { !m.ch[$0.rawValue].isCalm }.map { "\($0)" }
        let line = String(format: "cpu %@ %.1f%% of one core over %.1fs, Seed %.1f fps", label, pct, seconds, fps)
            + " pace=\(m.pace) state=\(m.state.name) moving=\(moving)"
        log(line)
        let url = out.appendingPathComponent("cpu.txt")
        let previous = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try (previous + line + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
