#if COUCOU_HUB
import Foundation
import SwiftUI
import AppKit

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
        HubIslandDashboardView(
            model: model,
            geometry: IslandScreenGeometry(screenWidth: 640,
                                          safeAreaTop: state.hasNotch ? state.notchHeight : 0,
                                          auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil,
                                          menuBarHeight: state.notchHeight),
            onOpenConsole: { NSWorkspace.shared.open(HubIslandEndpoint.console) },
            onClose: { state.view = state.tasks.isEmpty ? .empty : .overview },
            embedded: true
        )
        .task {
            model.refresh()
            model.refreshOperatorTasks()
        }
        .onDisappear { model.panelHidden() }
    }
}
#endif
