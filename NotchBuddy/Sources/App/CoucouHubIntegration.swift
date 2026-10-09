#if COUCOU_HUB
import Foundation
import SwiftUI
import AppKit

extension Notification.Name {
    static let coucouHubCollapse = Notification.Name("coucouHubCollapse")
}

/// Local integration only. Official Tincan remains the message consumer;
/// this model observes the existing operator API, never claims an inbox.
@MainActor
final class CoucouHubIntegration: ObservableObject {
    static let shared = CoucouHubIntegration()
    #if COUCOU_LAB
    // Test lab only: fixture API, no Keychain, a private pasteboard.
    let model = HubIslandModel(api: SeedLabFixtureAPI.shared, loadCredential: { "seed-lab" })
    let workspace = CoucouWorkspaceStore()
    let clipboard = CoucouClipboardAccessService(pasteboard: SeedLab.pasteboard)
    #else
    let model = HubIslandModel()
    let workspace = CoucouWorkspaceStore()
    let clipboard = CoucouClipboardAccessService()
    #endif
    @Published private(set) var fileShelfError: String?

    /// Local staging only: never uploads, routes, copies or deletes a file.
    func stageFiles(_ urls: [URL]) {
        do {
            _ = try workspace.addFiles(at: urls)
            fileShelfError = nil
        } catch {
            fileShelfError = error.localizedDescription
            NotificationCenter.default.post(name: .coucouShelfRejected, object: nil)
        }
    }

    func claudeUsage(_ usage: PlanUsage?, now: Date = Date()) -> CoucouUsageSnapshot {
        .claude(usage, now: now)
    }

    func start() { model.startOperatorPolling() }
    func stop() {
        clipboard.disableChangeMonitoring()
        model.stopOperatorPolling()
        model.panelHidden()
    }
}

struct CoucouHubPane: View {
    @ObservedObject var state: AppState
    @ObservedObject private var model = CoucouHubIntegration.shared.model

    var body: some View {
        CoucouAgentWorkspace(
            model: model,
            state: state,
            onOpenConsole: { NSWorkspace.shared.open(HubIslandEndpoint.console) },
            onClose: {
                NotificationCenter.default.post(name: .coucouHubCollapse, object: nil)
            }
        )
        .task {
            model.refresh()
            model.refreshOperatorTasks()
        }
        .onDisappear { model.panelHidden() }
    }
}
#endif
