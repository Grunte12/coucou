import AppKit
import SwiftUI

/// Fixed transparent panel + persistent SwiftUI island, following Coucou's MIT shell.
/// Copyright (c) 2026 Louis Raillé; see LICENSE. No reserved assets are included.
@MainActor
final class HubIslandWindowController: NSWindowController, NSWindowDelegate {
    private let model: HubIslandModel
    private let presentation: HubIslandPresentation
    private var hostingView: HubIslandHostingView?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    var isExpanded: Bool { presentation.expanded }
    var isVisible: Bool { window?.isVisible == true }

    init(model: HubIslandModel) {
        self.model = model
        let (screen, geometry) = Self.preferredScreenAndGeometry()
        presentation = HubIslandPresentation(geometry: geometry)
        let panel = HubIslandPanel(contentRect: Self.panelFrame(on: screen),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.acceptsMouseMovedEvents = true
        let hosting = HubIslandHostingView(rootView: HubIslandShell(model: model,
            presentation: presentation,
            onClose: { [weak self] in self?.collapse() }))
        hosting.presentation = presentation
        hosting.frame = NSRect(origin: .zero, size: panel.frame.size)
        hosting.autoresizingMask = [.width, .height]
        hostingView = hosting
        panel.contentView = hosting
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // Coucou toggles window-level click-through outside the island. Use mouse
        // events rather than its continuous 60 Hz polling; no key/input capture.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor in self?.updateMouseAcceptance() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor in self?.updateMouseAcceptance() }
            return event
        }
    }

    required init?(coder: NSCoder) { nil }
    func showCompact() {
        presentation.expanded = false
        window?.orderFrontRegardless()
        updateMouseAcceptance()
    }
    func expand() {
        guard let panel = window else { return }
        let changed = !presentation.expanded
        transition(expanded: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if changed { HubIslandSound.play(opening: true) }
        model.refresh()
    }
    func collapse() {
        guard presentation.expanded else { return }
        model.panelHidden()
        transition(expanded: false)
        window?.orderOut(nil)
        window?.orderFrontRegardless()
        HubIslandSound.play(opening: false)
    }
    func toggleExpanded() { isExpanded ? collapse() : expand() }
    func windowWillClose(_ notification: Notification) { model.panelHidden() }

    /// Remove process-wide event hooks when the app is shutting down.
    func shutdown() {
        model.panelHidden()
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        NotificationCenter.default.removeObserver(self,
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    private func transition(expanded: Bool) {
        let animation: Animation? = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil
            : expanded ? .spring(response: 0.5, dampingFraction: 0.72)
            : .timingCurve(0.45, 0, 0.2, 1, duration: 0.34)
        withAnimation(animation) { presentation.expanded = expanded }
        updateMouseAcceptance()
    }

    private func updateMouseAcceptance() {
        guard let panel = window else { return }
        // Resting state is entirely passive. The real NSStatusItem opens the UI;
        // no transparent overlay steals clicks from menu-bar icons.
        guard presentation.expanded else {
            panel.ignoresMouseEvents = true
            return
        }
        let rect = NSRect(x: panel.frame.midX - presentation.width / 2,
                          y: panel.frame.maxY - presentation.height,
                          width: presentation.width, height: presentation.height)
        panel.ignoresMouseEvents = !rect.contains(NSEvent.mouseLocation)
    }
    @objc private func screenParametersChanged() {
        let (screen, geometry) = Self.preferredScreenAndGeometry()
        presentation.geometry = geometry
        window?.setFrame(Self.panelFrame(on: screen), display: true)
        updateMouseAcceptance()
    }
    private static func panelFrame(on screen: NSScreen) -> NSRect {
        NSRect(x: screen.frame.midX - 360, y: screen.frame.maxY - 320, width: 720, height: 320)
    }
    private static func preferredScreenAndGeometry() -> (NSScreen, IslandScreenGeometry) {
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens[0]
        let bar = screen.frame.maxY - screen.visibleFrame.maxY
        return (screen, IslandScreenGeometry(screenWidth: screen.frame.width,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width,
            menuBarHeight: bar > 0 ? bar : NSStatusBar.system.thickness))
    }
}

@MainActor
final class HubIslandPresentation: ObservableObject {
    @Published var expanded = false
    @Published var geometry: IslandScreenGeometry
    init(geometry: IslandScreenGeometry) { self.geometry = geometry }
    var width: CGFloat { expanded ? 640 : geometry.restingOverlayWidth }
    var height: CGFloat { expanded ? 280 : geometry.restingOverlayHeight }
}

struct HubIslandShell: View {
    @ObservedObject var model: HubIslandModel
    @ObservedObject var presentation: HubIslandPresentation
    let onClose: () -> Void
    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            ZStack(alignment: .top) {
                HubIslandDashboardView(model: model, geometry: presentation.geometry,
                    onOpenConsole: { NSWorkspace.shared.open(HubIslandEndpoint.console) }, onClose: onClose)
                    .frame(width: 640, height: 280)
                    .opacity(presentation.expanded ? 1 : 0)
                    .allowsHitTesting(presentation.expanded)
                    .accessibilityHidden(!presentation.expanded)
            }
            .frame(width: presentation.width, height: presentation.height, alignment: .top)
            .background {
                HubIslandShape(compact: false).fill(Color.black)
                    .opacity(presentation.expanded ? 1 : 0)
            }
            .clipShape(HubIslandShape(compact: false))
        }
        .frame(width: 720, height: 320, alignment: .top)
        .ignoresSafeArea()
        .onExitCommand(perform: onClose)
    }
}

/// Transparent panel margins do not swallow clicks on the app behind.
private final class HubIslandHostingView: NSHostingView<HubIslandShell> {
    weak var presentation: HubIslandPresentation?
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let presentation, presentation.expanded else { return nil }
        let topY = isFlipped ? point.y : bounds.height - point.y
        let left = (bounds.width - presentation.width) / 2
        guard point.x >= left, point.x <= left + presentation.width,
              topY >= 0, topY <= presentation.height else { return nil }
        return super.hitTest(point)
    }
}
private final class HubIslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
