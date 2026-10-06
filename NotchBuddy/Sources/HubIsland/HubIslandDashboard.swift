import AppKit
import SwiftUI

struct HubIslandDashboardView: View {
    @ObservedObject var model: HubIslandModel
    let geometry: IslandScreenGeometry
    let onOpenConsole: () -> Void
    let onClose: () -> Void
    /// Reuse the functional pane within Coucou's existing notch shell.
    /// Do not create another window, header geometry or polling model.
    var embedded = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hubIsland.soundEnabled") private var soundEnabled = false

    private var connectionLabel: String {
        switch model.connection {
        case .notChecked: return "Not checked"
        case .checking: return "Checking"
        case .unpaired: return "Not paired"
        case .awaitingApproval: return "Approval needed"
        case .connected: return "Connected"
        case .unauthorized: return "Pair again"
        case .offline: return "Offline"
        case .error: return "Needs attention"
        }
    }

    private var connectionColor: Color {
        switch model.connection {
        case .connected: return Color(red: 0.26, green: 0.79, blue: 0.57)
        case .awaitingApproval: return Color(red: 0.97, green: 0.69, blue: 0.25)
        case .offline, .unauthorized, .error: return Color(red: 0.95, green: 0.36, blue: 0.39)
        case .notChecked, .checking, .unpaired: return Color.white.opacity(0.55)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 13) {
                header

                if model.dashboardTab != "tasks", let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 1, green: 0.60, blue: 0.57))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Hub Notch message: \(errorMessage)")
                }

                if model.dashboardTab != "tasks" && (model.connection == .awaitingApproval || model.pairing != nil) {
                    awaitingApprovalCard
                } else if model.dashboardTab != "tasks" && model.canPair {
                    pairingCard
                }

                // Navigation belongs to the shell, not the current content.
                // Keep its anchor when moving into a task detail or empty state.
                tabBar

                VStack(alignment: .leading, spacing: 13) {
                switch model.dashboardTab {
                case "tools":
                    if let snapshot = model.snapshot {
                        managerStatus(snapshot)
                        providers(snapshot.providers)
                    } else if model.connection == .checking {
                        hubLoadingMessage
                    } else {
                        hubUnavailableMessage
                    }
                case "activity":
                    if let snapshot = model.snapshot {
                        managerStatus(snapshot)
                        jobs(snapshot.jobs)
                    } else if model.connection == .checking {
                        hubLoadingMessage
                    } else {
                        hubUnavailableMessage
                    }
                default:
                    tincanTasks
                }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            }
            .padding(.horizontal, 17)
            .padding(.top, embedded ? 0 : (geometry.hasNotch ? geometry.height + 8 : 12))
            .padding(.bottom, 12)
            .frame(width: embedded ? 620 : 640, height: embedded ? 250 : 280, alignment: .topLeading)
            .background {
                if !embedded {
                    HubIslandShape(compact: false)
                        .fill(Color.black)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(Color.white.opacity(0.92))
        .background(Color.clear)
        .onExitCommand(perform: onClose)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            tabButton("Tools", tag: "tools", badge: nil)
            tabButton("Activity", tag: "activity", badge: nil)
            tabButton("Tasks", tag: "tasks", badge: model.heldRequestCount)
        }
        .padding(2)
        .background(Color.white.opacity(0.07), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Hub Notch view")
    }

    private func tabButton(_ title: String, tag: String, badge: Int?) -> some View {
        let selected = model.dashboardTab == tag
        return Button { model.dashboardTab = tag } label: {
            HStack(spacing: 5) {
                Text(title).font(.system(size: 11, weight: .medium))
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .background(heldColor, in: Capsule())
                } else if let badge {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(width: 96, height: 26)
            .background(selected ? Color.white.opacity(0.16) : Color.clear, in: Capsule())
            .foregroundStyle(.white.opacity(selected ? 0.95 : 0.6))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge.map { "\(title), \($0) held" } ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var heldColor: Color { Color(red: 0.97, green: 0.69, blue: 0.25) }

    private var hubLoadingMessage: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Reading the local Hub snapshot…")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
        }
        .padding(.vertical, 12)
    }

    private var hubUnavailableMessage: some View {
        Text(model.errorMessage ?? "Open Hub Notch to read the local Hub status.")
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.66))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 8)
    }

    private var header: some View {
        HStack(spacing: 9) {
            HubNotchCompanion(needsAttention: model.heldRequestCount > 0,
                              connected: model.connection == .connected)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Hub Notch")
                    .font(.system(size: 14, weight: .semibold))
            }

            Spacer(minLength: 8)

            Button { model.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)
            .accessibilityLabel("Refresh Hub status")
            .help("Read the latest Hub state without running provider tools.")

            Button { soundEnabled.toggle() } label: {
                Image(systemName: soundEnabled ? "speaker.wave.2" : "speaker.slash")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(soundEnabled ? "Mute interface sounds" : "Enable interface sounds")

            HStack(spacing: 6) {
                Circle().fill(connectionColor).frame(width: 6, height: 6)
                Text(connectionLabel)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(width: 114, alignment: .leading)
            .background(Color.white.opacity(0.075), in: Capsule())
            .accessibilityElement(children: .combine)

            Button(action: onOpenConsole) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Console")
            .controlSize(.small)
            .help("Open the existing Manager Console in your browser.")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 21, height: 21)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.57))
            .accessibilityLabel("Collapse Hub Notch")
            .keyboardShortcut(.cancelAction)
        }
    }

    private var pairingCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.horizontal")
                .font(.system(size: 16))
                .foregroundStyle(Color(red: 0.97, green: 0.69, blue: 0.25))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.connection == .unauthorized ? "Pairing needs renewal" : "Pair this app")
                    .font(.system(size: 12, weight: .semibold))
                Text("Approval stays in the Manager Console. The app credential is saved only to this Mac’s Keychain.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button(model.isBusy ? "Working…" : "Request pairing") {
                model.beginPairing()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(model.isBusy)
        }
        .padding(11)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 11))
    }

    private var awaitingApprovalCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised")
                .font(.system(size: 16))
                .foregroundStyle(Color(red: 0.97, green: 0.69, blue: 0.25))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Approve Hub Notch in the Console")
                    .font(.system(size: 12, weight: .semibold))
                Text("After approval, check once here. Pairing status is not polled in the background.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button("Check approval") {
                model.checkPairingApproval()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(model.isBusy)
        }
        .padding(11)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 11))
    }

    @ViewBuilder
    private var tincanTasks: some View {
        if model.selectedTincanTask != nil {
            tincanTaskDetail
        } else {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.54))
                        .accessibilityHidden(true)
                    Text("Tincan tasks")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                    Spacer()
                    if model.isRefreshingTincan {
                        ProgressView().controlSize(.mini)
                    }
                    Button {
                        model.refreshOperatorTasks()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.isRefreshingTincan)
                    .accessibilityLabel("Refresh Tincan task metadata")
                }

                if let decisionResultMessage = model.decisionResultMessage {
                    Text(decisionResultMessage)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }

                tincanTaskList
            }
        }
    }

    @ViewBuilder
    private var tincanTaskList: some View {
        switch model.tincanAccess {
        case .notChecked:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking local task metadata…")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.68))
            }
            .padding(.vertical, 8)
        case .needsCredential:
            operatorNotice(
                title: "No Hub Notch credential installed",
                message: "Use the trusted local installer to provision scoped Tincan approval permission. Pairing alone does not grant it."
            )
        case .permissionRequired:
            operatorNotice(
                title: "Needs operator permission",
                message: "This credential can read Hub status, but cannot approve Tincan requests. Reconnect through the trusted installer with Tincan approval enabled."
            )
        case .unauthorized:
            operatorNotice(
                title: "Hub Notch credential expired or revoked",
                message: "Provision a new scoped credential through the trusted local installer before sending another task decision."
            )
        case .offline:
            operatorNotice(
                title: "Local Hub unavailable",
                message: model.tincanErrorMessage ?? "Check that the Hub is running, then refresh."
            )
        case .error:
            operatorNotice(
                title: "Could not read task metadata",
                message: model.tincanErrorMessage ?? "Refresh the local Tincan task list and try again."
            )
        case .ready:
            if let inbox = model.tincanInbox, inbox.status == .disabled || !inbox.enabled {
                operatorNotice(
                    title: "Tincan monitoring is disabled",
                    message: "Enable the Tincan option in the local Hub to see task requests here."
                )
            } else if let inbox = model.tincanInbox, inbox.status == .unavailable {
                operatorNotice(
                    title: "Tincan task source unavailable",
                    message: "The Hub could not validate the local Tincan receiver. No decision controls are available."
                )
            } else if let inbox = model.tincanInbox {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 4) {
                        sectionTitle("HELD · REVIEW REQUIRED", count: model.heldRequestCount)
                        if inbox.heldTruncated || model.heldRequestCount > inbox.held.count {
                            Text("Showing \(inbox.held.count) of \(model.heldRequestCount) held requests. Older held requests are omitted in this prototype.")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 3)
                        }
                        if inbox.held.isEmpty {
                            Text("No held requests.")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.57))
                                .padding(.vertical, 3)
                        } else {
                            ForEach(inbox.held) { entry in tincanTaskRow(entry, isHeld: true) }
                        }

                        let needsInput = model.nonHeldTincanTraces.filter { $0.state.lowercased() == "needs_input" }
                        sectionTitle("NEEDS INPUT · CLARIFICATION", count: needsInput.count)
                        if needsInput.isEmpty {
                            Text("No clarification requests.")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.57))
                                .padding(.vertical, 3)
                        } else {
                            ForEach(needsInput) { entry in tincanTaskRow(entry, isHeld: false) }
                        }

                        let otherTasks = model.nonHeldTincanTraces.filter { $0.state.lowercased() != "needs_input" }
                        sectionTitle("OTHER TASKS", count: otherTasks.count)
                        if otherTasks.isEmpty {
                            Text("No other active traces.")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.57))
                                .padding(.vertical, 3)
                        } else {
                            ForEach(otherTasks) { entry in tincanTaskRow(entry, isHeld: false) }
                        }
                    }
                    .padding(.trailing, 2)
                }
                .frame(maxHeight: geometry.hasNotch ? max(96, 150 - geometry.height) : 150)
                .background(Color.black.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
            } else {
                operatorNotice(title: "Task metadata unavailable", message: "Refresh the local Tincan task list.")
            }
        }
    }

    private func operatorNotice(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private func tincanTaskRow(_ entry: HubTincanTraceSummary, isHeld: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            statePill(isHeld ? "held" : entry.state)
            VStack(alignment: .leading, spacing: 2) {
                Text(bounded(entry.title.isEmpty ? "Untitled Tincan task" : entry.title, limit: 180))
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                Text("\(bounded(entry.sender, limit: 64)) → \(bounded(entry.recipient, limit: 64)) · \(relativeTime(entry.createdAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
                Text("Request ID · \(entry.requestID)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(entry.requestID)
            }
            Spacer(minLength: 2)
            Button(isHeld ? "Review" : "Read detail") {
                model.readTincanTask(entry)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.isRefreshingTincan || model.isReadingTincanTrace || model.activeDecisionRequestID != nil)
            .accessibilityLabel("Read bounded details for request \(entry.requestID)")
            .help("Read redacted trace details. Needs input is informational; only held requests can be approved or denied.")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(isHeld ? heldColor.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
        .overlay(alignment: .bottom) {
            if !isHeld { Rectangle().fill(Color.white.opacity(0.055)).frame(height: 1).padding(.leading, 9) }
        }
    }

    /// Compact status pill: glyph + word, so state never relies on colour alone.
    private func statePill(_ raw: String) -> some View {
        let key = raw.lowercased()
        let symbol: String
        switch key {
        case "held": symbol = "hand.raised.fill"
        case "needs_input": symbol = "questionmark.bubble.fill"
        case "running", "working", "claimed", "approved", "pending", "queued": symbol = "circle.dotted"
        case "replied", "answered", "complete", "completed", "succeeded", "success": symbol = "checkmark"
        case "denied", "declined": symbol = "nosign"
        case "failed", "error", "expired": symbol = "exclamationmark.triangle.fill"
        default: symbol = "circle"
        }
        let color = key == "held" ? heldColor : healthColor(key == "needs_input" ? "pending" : key)
        return HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            Text(key == "needs_input" ? "Input" : pretty(raw).capitalized)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(width: 74)
        .background(color.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("State: \(taskStateLabel(raw))")
    }

    private var tincanTaskDetail: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Button {
                    model.closeTincanTaskDetail()
                } label: {
                    Label("Tasks", systemImage: "chevron.left")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to Tincan tasks")

                Spacer(minLength: 0)
                Button("Refresh list") { model.refreshOperatorTasks() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .disabled(model.isRefreshingTincan)
            }

            if let selected = model.selectedTincanTask {
                Text(bounded(selected.title, limit: 180))
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(2)
                Text("\(bounded(selected.sender, limit: 64)) → \(bounded(selected.recipient, limit: 64)) · \(taskStateLabel(selected.state))")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.63))
                Text("Exact request ID · \(selected.requestID)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(selected.requestID)
            }

            if model.isReadingTincanTrace {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("Reading bounded, redacted details…")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.vertical, 6)
            } else if let message = model.tincanTraceErrorMessage {
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(red: 1, green: 0.60, blue: 0.57))
                    .fixedSize(horizontal: false, vertical: true)
            } else if let detail = model.selectedTincanTrace {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(detail.steps.prefix(6)) { step in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(bounded(step.sender, limit: 64)) → \(bounded(step.recipient, limit: 64)) · \(taskStateLabel(step.state)) · \(bounded(step.kind, limit: 40))")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.76))
                                Text(bounded(step.body, limit: 900))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.white.opacity(0.82))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                                if let reply = step.reply {
                                    Text("Reply · \(bounded(reply.sender, limit: 48)) · \(taskStateLabel(reply.status))")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.57))
                                    Text(bounded(reply.body, limit: 700))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.72))
                                        .fixedSize(horizontal: false, vertical: true)
                                        .textSelection(.enabled)
                                }
                                ForEach(step.exchanges.prefix(3)) { exchange in
                                    Text("Q · \(bounded(exchange.question, limit: 360))\nA · \(bounded(exchange.answer, limit: 360))")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.68))
                                        .fixedSize(horizontal: false, vertical: true)
                                        .textSelection(.enabled)
                                }
                                if let progress = step.progress {
                                    Text("Progress · \(bounded(progress.note, limit: 240)) · \(bounded(progress.by, limit: 40))")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.6))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        ForEach(detail.events.suffix(5)) { event in
                            Text("Event \(event.sequence) · \(bounded(event.event, limit: 64)) · \(bounded(event.actor, limit: 48)) · \(event.requestID.map { bounded($0, limit: 64) } ?? "no request ID")")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.52))
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(7)
                }
                .frame(maxHeight: geometry.hasNotch ? max(52, 90 - geometry.height) : 88)
                .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))

                if let decisionResultMessage = model.decisionResultMessage {
                    Text(decisionResultMessage)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }

                decisionControls
            }
        }
    }

    @ViewBuilder
    private var decisionControls: some View {
        if let selected = model.selectedTincanTask,
           model.tincanInbox?.held.contains(where: { $0.requestID == selected.requestID }) == true {
            HStack(spacing: 8) {
                Text("Allow or deny this one request")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(heldColor)
                Spacer(minLength: 6)
                Button {
                    model.decideSelectedTincanTask(.approve)
                } label: {
                    Label("Allow", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!model.canDecideSelectedTincanTask)
                .accessibilityLabel("Allow exact held request \(selected.requestID)")
                .help("Allow only this request after reviewing its bounded details.")

                Button {
                    model.decideSelectedTincanTask(.deny)
                } label: {
                    Label("Deny", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!model.canDecideSelectedTincanTask)
                .accessibilityLabel("Deny exact held request \(selected.requestID)")
                .help("Deny only this exact held request.")

                if model.activeDecisionRequestID == selected.requestID {
                    ProgressView().controlSize(.mini)
                    Text("Sending…").font(.system(size: 10)).foregroundStyle(.white.opacity(0.65))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(heldColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(heldColor.opacity(0.35), lineWidth: 1))
        } else if let selected = model.selectedTincanTask,
                  selected.state.lowercased() == "needs_input" {
            Text("Needs input may require context or receiver permissions. It is not a held request; no Allow or Deny action is available.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.69))
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Allow and Deny are available only after details for an exact, currently held request are loaded.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func taskStateLabel(_ raw: String) -> String {
        raw.lowercased() == "needs_input" ? "Needs input · clarification" : pretty(raw)
    }

    private func bounded(_ value: String, limit: Int) -> String {
        let prefix = String(value.prefix(limit))
        return value.count > limit ? prefix + "…" : prefix
    }

    private func managerStatus(_ snapshot: HubSnapshot) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "server.rack")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.54))
            Text("Hub status")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
            Text(pretty(snapshot.hub.status))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(healthColor(snapshot.hub.status))
            Spacer()
            Text("Revision \(snapshot.revision)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
            Button {
                model.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.isBusy)
            .help("Fetch a new read-only snapshot from the local Hub.")
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    private func providers(_ values: [HubProvider]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("TOOLS", count: values.count)
            if values.isEmpty {
                Text("No configured providers.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.52))
                    .padding(.vertical, 6)
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(values) { provider in providerRow(provider) }
                    }
                }
                .frame(maxHeight: 152)
                .background(Color.black.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func providerRow(_ provider: HubProvider) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(healthColor(provider.health.status))
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.id)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text("Health: \(pretty(provider.health.status))")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.49))
                    .lineLimit(1)
            }
            Spacer(minLength: 3)
            if !provider.selectableAccounts.isEmpty {
                Menu {
                    ForEach(provider.selectableAccounts, id: \.self) { account in
                        Button {
                            model.selectAccount(account, for: provider)
                        } label: {
                            if provider.account == account {
                                Label(account, systemImage: "checkmark")
                            } else {
                                Text(account)
                            }
                        }
                        .disabled(model.busyProviders.contains(provider.id) || model.isBusy)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(provider.account ?? "Select account")
                            .lineLimit(1)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: 126, alignment: .trailing)
                }
                .menuStyle(.borderlessButton)
                .help("Select an account already configured in the Hub.")
            }
            Toggle("Enabled", isOn: Binding(
                get: { provider.enabled },
                set: { model.setEnabled(provider, enabled: $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.mini)
            .accessibilityLabel("\(provider.id) enabled")
            .disabled(model.isBusy || model.busyProviders.contains(provider.id))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.055)).frame(height: 1).padding(.leading, 23)
        }
    }

    private func jobs(_ values: [HubJob]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("RECENT JOBS", count: values.count)
            if values.isEmpty {
                Text("No recent jobs.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.52))
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(values.prefix(4)) { job in jobRow(job) }
                }
            }
        }
    }

    private func jobRow(_ job: HubJob) -> some View {
        HStack(spacing: 8) {
            Image(systemName: job.state.lowercased() == "running" ? "circle.lefthalf.filled" : "checkmark.circle")
                .font(.system(size: 10))
                .foregroundStyle(healthColor(job.state))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(job.provider) · \(job.capability)")
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 7) {
                    Text("\(pretty(job.state)) · started \(relativeTime(job.createdAt))")
                    if let updatedAt = job.updatedAt {
                        Text("· updated \(relativeTime(updatedAt))")
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.47))
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.46))
            Text("\(count)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.36))
            Spacer()
        }
    }

    private func pretty(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private func healthColor(_ raw: String) -> Color {
        switch raw.lowercased() {
        case "ok", "ready", "healthy", "connected", "complete", "completed", "succeeded", "success":
            return Color(red: 0.26, green: 0.79, blue: 0.57)
        case "unknown", "not_checked", "unchecked", "pending", "queued", "running":
            return Color(red: 0.97, green: 0.69, blue: 0.25)
        case "degraded", "error", "failed", "offline", "unhealthy":
            return Color(red: 0.95, green: 0.36, blue: 0.39)
        default:
            return Color.white.opacity(0.55)
        }
    }

    private func relativeTime(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        guard let date else { return value }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
    }
}

/// Original code-native companion; not Coucou's protected mascot artwork.
private struct HubNotchCompanion: View {
    let needsAttention: Bool
    let connected: Bool

    private var tint: Color {
        needsAttention ? Color(red: 1, green: 0.77, blue: 0.43)
            : connected ? Color(red: 0.74, green: 0.88, blue: 0.80)
            : Color(red: 0.77, green: 0.79, blue: 0.83)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(tint)
                .frame(width: 32, height: 29)
            HStack(spacing: 7) {
                Capsule().frame(width: 3, height: needsAttention ? 7 : 5)
                Capsule().frame(width: 3, height: needsAttention ? 7 : 5)
            }
            .foregroundStyle(Color.black.opacity(0.85))
            .offset(y: -2)
            if connected && !needsAttention {
                Capsule().fill(Color.black.opacity(0.65))
                    .frame(width: 5, height: 2).offset(y: 6)
            }
            if needsAttention {
                Circle().fill(Color(red: 1, green: 0.58, blue: 0.25))
                    .frame(width: 7, height: 7).offset(x: 13, y: -12)
            }
        }
        .frame(width: 36, height: 32)
    }
}
