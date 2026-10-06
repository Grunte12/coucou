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
final class CoucouHubIntegration {
    static let shared = CoucouHubIntegration()
    let model = HubIslandModel()

    func start() { model.startOperatorPolling() }
    func stop() { model.stopOperatorPolling(); model.panelHidden() }
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
