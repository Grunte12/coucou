#if COUCOU_HUB
import SwiftUI
import AppKit

// MARK: - Agent workspace pane (Coucou-native)
//
// Mochi pills are the entry point. Everything here is presentation over the
// shared `HubIslandModel`; it never claims an inbox, sends, or routes.

enum CoucouHubTab: String, CaseIterable {
    case agents, trail, mcp, review

    var title: String {
        switch self {
        case .agents: return "Agents"
        case .trail:  return "Trail"
        case .mcp:    return "MCP"
        case .review: return "Review"
        }
    }
    var icon: String {
        switch self {
        case .agents: return "person.2.fill"
        case .trail:  return "point.3.connected.trianglepath.dotted"
        case .mcp:    return "server.rack"
        case .review: return "hand.raised.fill"
        }
    }
}

extension CoucouHubFormat {
    static func stateColor(_ raw: String) -> Color { Color(hex: stateHex(raw)) }
}

// MARK: - Workspace

struct CoucouAgentWorkspace: View {
    @ObservedObject var model: HubIslandModel
    @ObservedObject var state: AppState
    let onOpenConsole: () -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: CoucouHubTab = .agents
    @State private var selectedAgentID: String?
    @State private var trailAgentID: String?
    @State private var showAllAgents = false
    @State private var seenIDs: Set<String> = []
    @State private var freshIDs: Set<String> = []
    @State private var baselined = false

    private var transferIDs: [String] {
        model.tincanInbox.map { CoucouHubFormat.transfers($0).map(\.requestID) } ?? []
    }

    private func spring(_ response: Double = 0.3, _ damping: Double = 0.8) -> Animation? {
        reduceMotion ? nil : .spring(response: response, dampingFraction: damping)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 8) {
                header
                if model.canPair || model.connection == .awaitingApproval || model.pairing != nil {
                    pairingStrip
                }
                // Fixed-height body: tab changes never move the header anchors.
                Group {
                    switch tab {
                    case .agents: agentsPage
                    case .trail:  trailPage
                    case .mcp:    mcpPage
                    case .review: reviewPage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .id(tab)
                .transition(.opacity)
            }
            .padding(.leading, 84)
            .padding(.trailing, 16)
            .padding(.vertical, 12)
        }
        .onExitCommand(perform: onClose)
        .onAppear(perform: observeTransfers)
        .onChange(of: transferIDs) { _, _ in observeTransfers() }
    }

    /// Newly observed IDs get a single highlight. The first read is a baseline
    /// so history is never replayed on launch or on tab/panel changes.
    private func observeTransfers() {
        let ids = Set(transferIDs)
        guard baselined else {
            if model.tincanInbox != nil { seenIDs = ids; baselined = true }
            return
        }
        let fresh = ids.subtracting(seenIDs)
        seenIDs.formUnion(ids)
        guard !fresh.isEmpty else { return }
        withAnimation(spring(0.4, 0.75)) { freshIDs.formUnion(fresh) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(spring(0.4, 0.9)) { freshIDs.subtract(fresh) }
        }
    }

    private func select(_ next: CoucouHubTab) {
        guard next != tab else { return }
        SoundEngine.shared.play("tick")
        withAnimation(spring()) { tab = next }
    }

    // MARK: Header

    private var connectionLabel: (String, String) {
        switch model.connection {
        case .connected:        return ("Connected", "#22C55E")
        case .checking:         return ("Checking", "#8E939C")
        case .notChecked:       return ("Not checked", "#8E939C")
        case .unpaired:         return ("Not paired", "#8E939C")
        case .awaitingApproval: return ("Approval needed", "#F5A524")
        case .unauthorized:     return ("Pair again", "#F4505E")
        case .offline:          return ("Offline", "#F4505E")
        case .error:            return ("Needs attention", "#F4505E")
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(CoucouHubTab.allCases, id: \.self) { t in tabButton(t) }
            }
            Spacer(minLength: 4)
            HStack(spacing: 5) {
                Circle().fill(Color(hex: connectionLabel.1)).frame(width: 6, height: 6)
                Text(connectionLabel.0)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            iconButton("arrow.clockwise", label: "Refresh agent status", disabled: model.isBusy || model.isRefreshingTincan) {
                model.refresh(); model.refreshOperatorTasks()
            }
            iconButton("slider.horizontal.3", label: "Open Manager", help: "Open the existing Manager in your browser.", action: onOpenConsole)
            iconButton("xmark", label: "Collapse", action: onClose)
        }
        .frame(height: 24)
    }

    private func tabButton(_ t: CoucouHubTab) -> some View {
        let on = tab == t
        let badge = t == .review ? model.heldRequestCount : 0
        return Button { select(t) } label: {
            HStack(spacing: 5) {
                Image(systemName: t.icon).font(.system(size: 10.5))
                Text(t.title).font(.system(size: 11, weight: .medium))
                if badge > 0 {
                    Text(badge > 99 ? "99+" : String(badge))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 4)
                        .background(Color(hex: "#F5A524"), in: Capsule())
                }
            }
            .foregroundColor(on ? Color(hex: "#F5F6F8") : Color(hex: "#8E939C"))
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(on ? Color(hex: "#1D1F23") : Color.clear)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge > 0 ? "\(t.title), \(badge) awaiting review" : t.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func iconButton(_ symbol: String, label: String, help: String? = nil,
                            disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: "#8E939C"))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .accessibilityLabel(label)
        .help(help ?? label)
    }

    private var pairingStrip: some View {
        let awaiting = model.connection == .awaitingApproval || model.pairing != nil
        return HStack(spacing: 8) {
            Image(systemName: awaiting ? "hand.raised" : "key.horizontal")
                .font(.system(size: 12)).foregroundColor(Color(hex: "#F5A524"))
            Text(awaiting
                 ? "Approve this app in the Manager, then check once."
                 : (model.connection == .unauthorized ? "Pairing needs renewal." : "Pair this app with the local Hub."))
                .font(.system(size: 11)).foregroundColor(Color(hex: "#C5C8CD")).lineLimit(1)
            Spacer(minLength: 4)
            SecondaryButton(awaiting ? "Check approval" : (model.isBusy ? "Working…" : "Request pairing")) {
                awaiting ? model.checkPairingApproval() : model.beginPairing()
            }
            .disabled(model.isBusy)
        }
    }

    // MARK: Shared notices

    private func notice(_ title: String, _ message: String, symbol: String = "info.circle") -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundColor(Color(hex: "#6B7079"))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
                Text(message).font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    /// Explains why Tincan data is not shown. nil when the roster/inbox is trustworthy.
    private var tincanGate: (String, String)? {
        switch model.tincanAccess {
        case .notChecked: return ("Checking…", "Reading local Tincan metadata. Nothing is verified yet.")
        case .needsCredential: return ("Not set up", "No scoped credential is installed on this Mac. Use the trusted local installer; pairing alone does not grant Tincan access.")
        case .permissionRequired: return ("Read-only credential", "This credential can read Hub status but not Tincan. Reconnect through the trusted installer.")
        case .unauthorized: return ("Access denied", "The scoped credential is invalid or revoked. Reconnect through the trusted local installer.")
        case .offline: return ("Hub unavailable", model.tincanErrorMessage ?? "The local Hub is not reachable. Start it, then refresh.")
        case .error: return ("Could not read Tincan", model.tincanErrorMessage ?? "Refresh and try again.")
        case .ready:
            guard let inbox = model.tincanInbox else { return ("Unverified", "Task metadata has not loaded yet.") }
            if inbox.status == .disabled || !inbox.enabled { return ("Tincan observation is off", "Connect the local operator view to the official Tincan relay. LinkHub remains tools-only.") }
            if inbox.status == .unavailable { return ("Tincan unavailable", "The local operator view could not read the official Tincan relay. No controls are available.") }
            return nil
        }
    }

    // MARK: Agents page

    private struct AgentRow: Identifiable {
        let agent: HubTincanAgent
        let task: AgentTask
        var id: String { agent.id }
    }

    private func heldInvolving(_ id: String) -> Int {
        model.tincanInbox?.held.filter { $0.sender == id || $0.recipient == id }.count ?? 0
    }

    private func task(for agent: HubTincanAgent) -> AgentTask {
        // Presence is not execution: online is idle, offline sleeps.
        AgentTask(id: agent.id,
                  name: CoucouHubFormat.display(agent.name.isEmpty ? agent.id : agent.name),
                  color: CoucouHubFormat.color(for: agent.id),
                  state: agent.online ? .idle : .sleeping,
                  steps: [], source: .agent,
                  pillBadge: heldInvolving(agent.id) > 0 ? .approval : nil)
    }

    @ViewBuilder private var agentsPage: some View {
        if let gate = tincanGate {
            notice(gate.0, gate.1, symbol: "person.2")
        } else if let roster = model.tincanRoster {
            rosterContent(roster)
        } else {
            notice("Roster unverified", "The agent list has not been read from the Hub yet. This is not an empty roster.", symbol: "person.2")
        }
    }

    @ViewBuilder private func rosterContent(_ roster: HubTincanRoster) -> some View {
        if roster.status != .ready || !roster.enabled {
            notice("Roster unavailable", "The Hub could not read the Tincan roster.", symbol: "person.2")
        } else if roster.agents.isEmpty {
            notice("No agents joined", "Tincan reports zero joined agents. Join an agent through the official Tincan setup.", symbol: "person.2")
        } else {
            let hidden = roster.agents.filter(CoucouHubFormat.isDiagnostic)
            let visible = showAllAgents ? roster.agents : roster.agents.filter { !CoucouHubFormat.isDiagnostic($0) }
            let rows = visible.map { AgentRow(agent: $0, task: task(for: $0)) }
            let selected = roster.agents.first { $0.id == selectedAgentID } ?? visible.first
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 4) {
                            ForEach(rows) { row in
                                AgentPill(task: row.task, state: state, swapping: .constant(false)) {
                                    SoundEngine.shared.play("blip")
                                    withAnimation(spring()) { selectedAgentID = row.id }
                                }
                                .overlay(
                                    Capsule()
                                        .stroke(Color(hex: row.task.color).opacity(selected?.id == row.id ? 0.9 : 0), lineWidth: 1.5)
                                        .allowsHitTesting(false)
                                )
                                .opacity(row.agent.online ? 1 : 0.55)
                                .accessibilityLabel("\(row.task.name), \(row.agent.online ? "online" : "offline")")
                                .accessibilityAddTraits(selected?.id == row.id ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    if !hidden.isEmpty {
                        Button {
                            withAnimation(spring()) { showAllAgents.toggle() }
                        } label: {
                            Text(showAllAgents
                                 ? "Hide \(hidden.count) diagnostic"
                                 : "\(hidden.count) diagnostic hidden · Show all (\(roster.agents.count))")
                                .font(.system(size: 10)).foregroundColor(Color(hex: "#6B7079"))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 236)
                if let selected { agentDetail(selected) }
            }
        }
    }

    private func presence(_ agent: HubTincanAgent) -> (String, String) {
        if !agent.online { return ("Offline", "#6B7079") }
        return ("Online", "#22C55E")
    }

    private func wakeText(_ agent: HubTincanAgent) -> String {
        guard let wake = agent.wake?.trimmingCharacters(in: .whitespaces), !wake.isEmpty, wake.lowercased() != "none" else {
            return "Not configured"
        }
        return CoucouHubFormat.bounded(CoucouHubFormat.pretty(wake), limit: 40)
    }

    private func agentDetail(_ agent: HubTincanAgent) -> some View {
        let label = CoucouHubFormat.display(agent.name.isEmpty ? agent.id : agent.name)
        let (presenceText, presenceHex) = presence(agent)
        let wakeMissing = wakeText(agent) == "Not configured"
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Circle().fill(Color(hex: CoucouHubFormat.color(for: agent.id))).frame(width: 8, height: 8)
                Text(label).font(.system(size: 12.5, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8")).lineLimit(1)
                Spacer(minLength: 2)
                HStack(spacing: 4) {
                    Circle().fill(Color(hex: presenceHex)).frame(width: 6, height: 6)
                    Text(presenceText).font(.system(size: 10.5, weight: .medium)).foregroundColor(Color(hex: presenceHex))
                }
            }
            if label != agent.id {
                Text(agent.id).font(.system(size: 10, design: .monospaced)).foregroundColor(Color(hex: "#6B7079"))
                    .lineLimit(1).truncationMode(.middle)
            }
            factRow("Wake", wakeText(agent), warn: wakeMissing)
            factRow("Last active", CoucouHubFormat.relative(agent.lastActive))
            factRow("Queue", "\(agent.queued) queued · \(agent.claimed) claimed")
            if let kind = agent.kind, !kind.isEmpty {
                factRow("Kind", CoucouHubFormat.bounded(kind, limit: 28) + (agent.version.map { " · v\(CoucouHubFormat.bounded($0, limit: 12))" } ?? ""))
            }
            Text("Presence is not proof a task is running.")
                .font(.system(size: 10)).foregroundColor(Color(hex: "#6B7079"))
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                SecondaryButton("Trail") {
                    trailAgentID = agent.id
                    select(.trail)
                }
                if wakeMissing || !agent.online {
                    SecondaryButton("Set up", action: onOpenConsole)
                        .help("Opens the existing Manager. No keys are shown here.")
                }
                SecondaryButton("Wake") {}
                    .disabled(true).opacity(0.4)
                    .help("The Hub has no wake action yet.")
            }
            if wakeMissing || !agent.online {
                Text("Wake from here isn’t available yet; the Hub has no such action.")
                    .font(.system(size: 10)).foregroundColor(Color(hex: "#6B7079"))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "#0E0F11")))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.05), lineWidth: 1))
    }

    private func factRow(_ key: String, _ value: String, warn: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(key).font(.system(size: 11)).foregroundColor(Color(hex: "#6B7079")).frame(width: 66, alignment: .leading)
            Text(value).font(.system(size: 11, weight: .medium))
                .foregroundColor(warn ? Color(hex: "#F5A524") : Color(hex: "#C5C8CD")).lineLimit(1)
        }
    }

    // MARK: Trail page

    @ViewBuilder private var trailPage: some View {
        if model.selectedTincanTask != nil {
            transferDetail
        } else if let gate = tincanGate {
            notice(gate.0, gate.1, symbol: "point.3.connected.trianglepath.dotted")
        } else if let inbox = model.tincanInbox {
            let all = CoucouHubFormat.transfers(inbox)
            let rows = all.filter { trailAgentID == nil || $0.sender == trailAgentID || $0.recipient == trailAgentID }
            let shown = Array(rows.prefix(8))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("Who is talking to whom. Open a transfer to read it.")
                        .font(.system(size: 10.5)).foregroundColor(Color(hex: "#6B7079")).lineLimit(1)
                    Spacer(minLength: 2)
                    if let trailAgentID {
                        Button {
                            withAnimation(spring()) { self.trailAgentID = nil }
                        } label: {
                            HStack(spacing: 4) {
                                Text(CoucouHubFormat.display(trailAgentID)).lineLimit(1)
                                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                            }
                            .font(.system(size: 10.5, weight: .medium)).foregroundColor(Color(hex: "#F5F6F8"))
                            .padding(.horizontal, 8).frame(height: 20)
                            .background(Color.white.opacity(0.09), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear agent filter")
                    }
                }
                if shown.isEmpty {
                    notice(trailAgentID == nil ? "Quiet" : "Nothing for this agent",
                           "No recent transfers in the Hub snapshot. Older history is not shown here.",
                           symbol: "moon.zzz")
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 3) {
                            ForEach(shown, id: \.requestID) { entry in
                                transferRow(entry, held: inbox.held.contains { $0.requestID == entry.requestID })
                                    .transition(reduceMotion ? .identity
                                                : .asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                            }
                        }
                        // Animates only when IDs change while visible; a fresh page never replays history.
                        .animation(spring(0.4, 0.8), value: shown.map(\.requestID))
                    }
                    if rows.count > shown.count {
                        Text("Latest \(shown.count) of \(rows.count) in this snapshot")
                            .font(.system(size: 10)).foregroundColor(Color(hex: "#6B7079"))
                    }
                }
            }
        } else {
            notice("Unverified", "Task metadata has not loaded yet.")
        }
    }

    private func agentChip(_ id: String, trailing: Bool) -> some View {
        HStack(spacing: 5) {
            if !trailing { Circle().fill(Color(hex: CoucouHubFormat.color(for: id))).frame(width: 7, height: 7) }
            Text(CoucouHubFormat.display(CoucouHubFormat.bounded(id, limit: 24)))
                .font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8")).lineLimit(1)
            if trailing { Circle().fill(Color(hex: CoucouHubFormat.color(for: id))).frame(width: 7, height: 7) }
        }
        .frame(width: 92, alignment: trailing ? .trailing : .leading)
    }

    private func statePill(_ raw: String) -> some View {
        let color = CoucouHubFormat.stateColor(raw)
        return HStack(spacing: 4) {
            Image(systemName: CoucouHubFormat.stateSymbol(raw)).font(.system(size: 8.5, weight: .bold))
            Text(CoucouHubFormat.stateWord(raw)).font(.system(size: 10, weight: .semibold)).lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 7).frame(width: 74, height: 20)
        .background(color.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("State: \(CoucouHubFormat.pretty(raw))")
    }

    /// One lane: sender ── state ──▶ recipient. Title and body are never shown here.
    private func transferRow(_ entry: HubTincanTraceSummary, held: Bool) -> some View {
        let fresh = freshIDs.contains(entry.requestID)
        let state = held ? "held" : entry.state
        let color = CoucouHubFormat.stateColor(state)
        let busy = model.isRefreshingTincan || model.isReadingTincanTrace || model.activeDecisionRequestID != nil
        return Button {
            SoundEngine.shared.play("pop")
            model.readTincanTask(entry)
        } label: {
            HStack(spacing: 6) {
                agentChip(entry.sender, trailing: false)
                ZStack {
                    Capsule().fill(color.opacity(0.35)).frame(height: 2)
                    Image(systemName: "arrowtriangle.right.fill").font(.system(size: 7))
                        .foregroundColor(color).frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(minWidth: 24, maxWidth: .infinity)
                agentChip(entry.recipient, trailing: true)
                statePill(state)
                Text(CoucouHubFormat.relative(entry.createdAt))
                    .font(.system(size: 10)).foregroundColor(Color(hex: "#6B7079")).frame(width: 40, alignment: .trailing)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundColor(Color(hex: "#6B7079"))
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(Capsule().fill(held ? Color(hex: "#F5A524").opacity(0.10) : Color(hex: "#0E0F11")))
            .overlay(Capsule().stroke(fresh ? color.opacity(0.8) : Color.white.opacity(0.05), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel("\(CoucouHubFormat.display(entry.sender)) to \(CoucouHubFormat.display(entry.recipient)), \(CoucouHubFormat.pretty(state)), request \(entry.requestID)")
        .accessibilityHint("Opens this transfer’s details")
    }

    // MARK: Transfer detail

    @ViewBuilder private var transferDetail: some View {
        if let selected = model.selectedTincanTask {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Button {
                        SoundEngine.shared.play("tick")
                        model.closeTincanTaskDetail()
                    } label: {
                        Label("Back", systemImage: "chevron.left").font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#C5C8CD"))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Back to the list")
                    Text("\(CoucouHubFormat.display(selected.sender)) → \(CoucouHubFormat.display(selected.recipient))")
                        .font(.system(size: 11.5, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8")).lineLimit(1)
                    Spacer(minLength: 2)
                    statePill(model.tincanInbox?.held.contains { $0.requestID == selected.requestID } == true ? "held" : selected.state)
                }
                Text("Request \(selected.requestID)")
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(Color(hex: "#6B7079"))
                    .lineLimit(1).truncationMode(.middle).help(selected.requestID)

                Group {
                    if model.isReadingTincanTrace {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text("Reading bounded, redacted details…")
                                .font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
                        }
                        .padding(.top, 6)
                    } else if let message = model.tincanTraceErrorMessage {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(message).font(.system(size: 11)).foregroundColor(Color(hex: "#F4505E"))
                                .fixedSize(horizontal: false, vertical: true)
                            SecondaryButton("Retry") { model.readTincanTask(selected) }
                        }
                        .padding(.top, 4)
                    } else if let detail = model.selectedTincanTrace {
                        traceBody(detail, selected: selected)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if model.selectedTincanTrace != nil || model.decisionResultMessage != nil {
                    if let result = model.decisionResultMessage {
                        Text(result).font(.system(size: 10.5, weight: .medium)).foregroundColor(Color(hex: "#C5C8CD"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    decisionControls(selected)
                }
            }
        }
    }

    private func traceBody(_ detail: HubTincanTrace, selected: HubTincanTraceSummary) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 7) {
                if !selected.title.isEmpty {
                    Text(CoucouHubFormat.bounded(selected.title, limit: 180))
                        .font(.system(size: 11.5, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                // The selected request may be deep in a bounded trace. Never
                // hide it behind a prefix while offering its approval controls.
                ForEach(detail.steps) { step in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(CoucouHubFormat.display(step.sender)) → \(CoucouHubFormat.display(step.recipient)) · \(CoucouHubFormat.pretty(step.state)) · \(CoucouHubFormat.bounded(step.kind, limit: 32))")
                            .font(.system(size: 10, weight: .semibold)).foregroundColor(Color(hex: "#8E939C"))
                        Text(step.id == selected.requestID ? step.body : CoucouHubFormat.bounded(step.body, limit: 900))
                            .font(.system(size: 11)).foregroundColor(Color(hex: "#C5C8CD"))
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        if let reply = step.reply {
                            Text("Reply · \(CoucouHubFormat.display(reply.sender)) · \(CoucouHubFormat.pretty(reply.status))")
                                .font(.system(size: 10, weight: .medium)).foregroundColor(Color(hex: "#8E939C"))
                            Text(CoucouHubFormat.bounded(reply.body, limit: 700))
                                .font(.system(size: 10.5)).foregroundColor(Color(hex: "#C5C8CD"))
                                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                        ForEach(step.exchanges.prefix(3)) { ex in
                            Text("Q · \(CoucouHubFormat.bounded(ex.question, limit: 360))\nA · \(ex.answer.isEmpty ? "—" : CoucouHubFormat.bounded(ex.answer, limit: 360))")
                                .font(.system(size: 10.5)).foregroundColor(Color(hex: "#8E939C"))
                                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                        if let p = step.progress {
                            Text("Progress · \(CoucouHubFormat.bounded(p.note, limit: 240))")
                                .font(.system(size: 10.5)).foregroundColor(Color(hex: "#8E939C"))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                let events = detail.events.suffix(8)
                if !events.isEmpty {
                    Text("EVENTS").font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundColor(Color(hex: "#6B7079"))
                    ForEach(Array(events)) { e in
                        HStack(spacing: 6) {
                            Text("#\(e.sequence)").font(.system(size: 10, design: .monospaced)).foregroundColor(Color(hex: "#6B7079"))
                            Text(CoucouHubFormat.pretty(CoucouHubFormat.bounded(e.event, limit: 40)))
                                .font(.system(size: 10.5, weight: .medium)).foregroundColor(Color(hex: "#C5C8CD"))
                            Text(CoucouHubFormat.display(CoucouHubFormat.bounded(e.actor, limit: 28)))
                                .font(.system(size: 10.5)).foregroundColor(Color(hex: "#8E939C"))
                            Spacer(minLength: 2)
                            Text(CoucouHubFormat.relative(e.at)).font(.system(size: 10)).foregroundColor(Color(hex: "#6B7079"))
                        }
                        .lineLimit(1)
                    }
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#0E0F11")))
    }

    @ViewBuilder private func decisionControls(_ selected: HubTincanTraceSummary) -> some View {
        let isHeld = model.tincanInbox?.held.contains { $0.requestID == selected.requestID } == true
        if isHeld {
            HStack(spacing: 8) {
                Text("Allow or deny this one request")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(Color(hex: "#F5A524")).lineLimit(1)
                Spacer(minLength: 4)
                if model.activeDecisionRequestID == selected.requestID {
                    ProgressView().controlSize(.mini)
                    Text("Sending…").font(.system(size: 10.5)).foregroundColor(Color(hex: "#8E939C"))
                }
                SecondaryButton("Deny") { model.decideSelectedTincanTask(.deny) }
                    .disabled(!model.canDecideSelectedTincanTask).opacity(model.canDecideSelectedTincanTask ? 1 : 0.4)
                    .accessibilityLabel("Deny exact held request \(selected.requestID)")
                PrimaryButton("Allow") { model.decideSelectedTincanTask(.approve) }
                    .disabled(!model.canDecideSelectedTincanTask).opacity(model.canDecideSelectedTincanTask ? 1 : 0.4)
                    .accessibilityLabel("Allow exact held request \(selected.requestID)")
            }
        } else if selected.state.lowercased() == "needs_input" {
            Text("Needs input is a clarification, not a held request. There is nothing to allow or deny here.")
                .font(.system(size: 10.5)).foregroundColor(Color(hex: "#8E939C")).fixedSize(horizontal: false, vertical: true)
        } else {
            Text(CoucouHubFormat.isClosed(selected.state)
                 ? "Closed. This is history and is read-only."
                 : "Not held for review. Nothing to allow or deny.")
                .font(.system(size: 10.5)).foregroundColor(Color(hex: "#6B7079"))
        }
    }

    // MARK: Review page

    @ViewBuilder private var reviewPage: some View {
        if model.selectedTincanTask != nil {
            transferDetail
        } else if let gate = tincanGate {
            notice(gate.0, gate.1, symbol: "hand.raised")
        } else if let inbox = model.tincanInbox {
            let held = inbox.held
            let needsInput = model.nonHeldTincanTraces.filter { $0.state.lowercased() == "needs_input" }
            let closed = model.nonHeldTincanTraces.filter { CoucouHubFormat.isClosed($0.state) }
            VStack(alignment: .leading, spacing: 5) {
                if let result = model.decisionResultMessage {
                    Text(result).font(.system(size: 10.5, weight: .medium)).foregroundColor(Color(hex: "#C5C8CD"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if held.isEmpty && needsInput.isEmpty && closed.isEmpty {
                    notice("All clear", "Nothing is waiting for you.", symbol: "checkmark.circle")
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 3) {
                            section("WAITING FOR YOU", count: model.heldRequestCount)
                            if inbox.heldTruncated || model.heldRequestCount > held.count {
                                Text("Showing \(held.count) of \(model.heldRequestCount) held requests.")
                                    .font(.system(size: 10)).foregroundColor(Color(hex: "#F5A524"))
                            }
                            if held.isEmpty {
                                Text("Nothing is held.").font(.system(size: 11)).foregroundColor(Color(hex: "#6B7079"))
                            }
                            ForEach(held, id: \.requestID) { transferRow($0, held: true) }
                            if !needsInput.isEmpty {
                                section("NEEDS INPUT · INFORMATIONAL", count: needsInput.count)
                                ForEach(needsInput.prefix(4), id: \.requestID) { transferRow($0, held: false) }
                            }
                            if !closed.isEmpty {
                                section("CLOSED · READ-ONLY", count: closed.count)
                                ForEach(closed.prefix(4), id: \.requestID) { transferRow($0, held: false) }
                            }
                        }
                    }
                }
            }
        } else {
            notice("Unverified", "Task metadata has not loaded yet.")
        }
    }

    private func section(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundColor(Color(hex: "#6B7079"))
            Text("\(count)").font(.system(size: 9.5, weight: .medium, design: .monospaced)).foregroundColor(Color(hex: "#6B7079"))
        }
        .padding(.top, 4)
    }

    // MARK: MCP page

    @ViewBuilder private var mcpPage: some View {
        if let snapshot = model.snapshot {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(CoucouHubFormat.stateColor(snapshot.hub.status)).frame(width: 6, height: 6)
                    Text("Manager · \(CoucouHubFormat.pretty(snapshot.hub.status))")
                        .font(.system(size: 11, weight: .medium)).foregroundColor(Color(hex: "#C5C8CD"))
                    Spacer(minLength: 2)
                    Button(action: onOpenConsole) {
                        Text("Configure in Manager").font(.system(size: 10.5)).foregroundColor(Color(hex: "#8E939C"))
                    }
                    .buttonStyle(.plain)
                }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 3) {
                        ForEach(snapshot.providers) { providerRow($0) }
                        if let job = snapshot.jobs.first {
                            HStack(spacing: 6) {
                                Text("LATEST JOB").font(.system(size: 9.5, weight: .semibold)).tracking(0.6)
                                    .foregroundColor(Color(hex: "#6B7079"))
                                Text("\(CoucouHubFormat.bounded(job.provider, limit: 20)) · \(CoucouHubFormat.bounded(job.capability, limit: 24)) · \(CoucouHubFormat.pretty(job.state))")
                                    .font(.system(size: 10.5)).foregroundColor(Color(hex: "#8E939C")).lineLimit(1)
                                Spacer(minLength: 2)
                                Text(CoucouHubFormat.relative(job.updatedAt ?? job.createdAt))
                                    .font(.system(size: 10)).foregroundColor(Color(hex: "#6B7079"))
                            }
                            .padding(.top, 6)
                        }
                    }
                }
            }
        } else if model.connection == .checking {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading the local Hub…").font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
            }
            .padding(.top, 8)
        } else {
            notice("Hub status unavailable", model.errorMessage ?? "Open the Manager or refresh to read the local Hub.", symbol: "server.rack")
        }
    }

    private func providerRow(_ p: HubProvider) -> some View {
        let health = p.health.status
        let color = p.enabled ? CoucouHubFormat.stateColor(health) : Color(hex: "#6B7079")
        return HStack(spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(CoucouHubFormat.bounded(p.id, limit: 28)).font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(Color(hex: "#F5F6F8")).lineLimit(1)
            if let account = p.account, !account.isEmpty {
                Text(CoucouHubFormat.bounded(account, limit: 28)).font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#8E939C")).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(p.enabled ? CoucouHubFormat.pretty(health) : "Off")
                .font(.system(size: 10.5, weight: .medium)).foregroundColor(color).lineLimit(1)
        }
        .padding(.horizontal, 10).frame(height: 28)
        .background(Capsule().fill(Color(hex: "#0E0F11")))
        .overlay(Capsule().stroke(Color.white.opacity(0.05), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(p.id), \(p.enabled ? "enabled" : "disabled"), health \(CoucouHubFormat.pretty(health))")
    }
}
#endif
