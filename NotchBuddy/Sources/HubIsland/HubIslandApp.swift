import AppKit
import Combine
import SwiftUI

@main
struct HubIslandApp: App {
    @NSApplicationDelegateAdaptor(HubIslandAppDelegate.self) private var delegate

    init() {
        if let status = HubIslandInstaller.run(arguments: Array(CommandLine.arguments.dropFirst())) {
            exit(status)
        }
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Open Hub Notch") { delegate.openPanel() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
final class HubIslandAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private weak var statusButton: NSStatusBarButton?
    private var windowController: HubIslandWindowController?
    private let model = HubIslandModel()
    private var subscriptions = Set<AnyCancellable>()
    private var pendingPeekTask: Task<Void, Never>?
    private var pendingPeekID: UUID?
    private var latestPendingCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMenuBarItem()
        observePendingCount()
        model.onNewHeldRequests = { [weak self] entries in self?.showNewHeldPeek(entries) }
        model.startOperatorPolling()
        windowController = HubIslandWindowController(model: model)
        windowController?.showCompact()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stopOperatorPolling()
        pendingPeekTask?.cancel()
        windowController?.shutdown()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // A normal Finder/Dock reopen should reveal the dashboard even though
        // this accessory app keeps its transparent resting panel ordered in.
        windowController?.expand()
        return true
    }

    private func installMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "square.3.layers.3d", accessibilityDescription: "Hub Notch")
            button.image?.isTemplate = true
            button.toolTip = "Hub Notch"
            button.target = self
            button.action = #selector(togglePanel)
            statusButton = button
        }

        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Hub Notch", action: #selector(openPanel), keyEquivalent: "h")
        open.keyEquivalentModifierMask = [.command, .shift]
        open.target = self
        menu.addItem(open)

        let refresh = NSMenuItem(title: "Refresh Hub", action: #selector(refreshHub), keyEquivalent: "r")
        refresh.keyEquivalentModifierMask = [.command, .option]
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(.separator())
        let console = NSMenuItem(title: "Open Manager Console", action: #selector(openConsole), keyEquivalent: "")
        console.target = self
        menu.addItem(console)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Hub Notch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    private func observePendingCount() {
        model.$tincanInbox
            .map { $0?.heldCount ?? $0?.held.count ?? 0 }
            .removeDuplicates()
            .sink { [weak self] count in
                Task { @MainActor in self?.updatePendingBadge(count) }
            }
            .store(in: &subscriptions)
    }

    private func updatePendingBadge(_ count: Int) {
        latestPendingCount = max(0, count)
        guard pendingPeekID == nil else { return }
        guard let statusButton else { return }
        let safeCount = latestPendingCount
        statusButton.title = safeCount == 0 ? "" : " \(safeCount > 99 ? "99+" : String(safeCount))"
        statusButton.toolTip = safeCount == 0
            ? "Hub Notch"
            : "\(safeCount) held Tincan request\(safeCount == 1 ? "" : "s"). Click to review in Hub Notch."
    }

    private func showNewHeldPeek(_ entries: [HubTincanTraceSummary]) {
        guard let first = entries.first else { return }
        let peekID = UUID()
        pendingPeekID = peekID
        pendingPeekTask?.cancel()
        if let statusButton {
            statusButton.title = entries.count == 1 ? " NEW" : " NEW \(entries.count)"
            statusButton.toolTip = "New held request: \(first.sender) → \(first.recipient) · \(String(first.title.prefix(100)))"
        }
        pendingPeekTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            guard let self, self.pendingPeekID == peekID else { return }
            self.pendingPeekID = nil
            self.updatePendingBadge(self.latestPendingCount)
        }
    }

    @objc private func togglePanel() {
        if let windowController {
            windowController.toggleExpanded()
        } else {
            openPanel()
        }
    }

    @objc func openPanel() {
        windowController?.expand()
    }

    @objc private func refreshHub() {
        if windowController?.isExpanded != true {
            openPanel()
        } else {
            model.refresh()
        }
    }

    @objc private func openConsole() {
        NSWorkspace.shared.open(HubIslandEndpoint.console)
    }

}
