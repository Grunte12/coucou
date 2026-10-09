#if COUCOU_HUB
import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Seed's Settings window
//
// Seed's own Settings: a dark sidebar, one card per topic, gold for focus and
// selection. Coucou's SettingsView stays untouched as a code reference; this
// build opens only this one. Every write outside Seed (an agent's hook file,
// Claude's status line) shows its exact JSON first and waits for a click.

enum SeedSettingsPage: String, CaseIterable, Identifiable {
    case general, agents, ring, folders, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .agents:  return "Agents"
        case .ring:    return "Action Ring"
        case .folders: return "Folders"
        case .about:   return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .agents:  return "person.2.fill"
        case .ring:    return "circle.dashed"
        case .folders: return "folder.fill"
        case .about:   return "info.circle.fill"
        }
    }
}

struct SeedSettingsView: View {
    @AppStorage("seed.settings.page") private var pageID = SeedSettingsPage.general.rawValue
    @State private var mascot = RiceMotion()
    @State private var note: Note?

    struct Note: Equatable { let text: String; let isError: Bool }

    private var page: SeedSettingsPage { SeedSettingsPage(rawValue: pageID) ?? .general }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(SeedInk.divider).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                Text(page.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(SeedInk.text)
                    .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch page {
                        case .general: SeedGeneralPage(note: $note)
                        case .agents:  SeedAgentsPage(note: $note)
                        case .ring:    SeedRingPage()
                        case .folders: SeedFoldersSettingsPage()
                        case .about:   SeedAboutPage()
                        }
                    }
                    .padding(.horizontal, 24).padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let note {
                    HStack(spacing: 8) {
                        Circle().fill(note.isError ? SeedInk.red : SeedInk.gold).frame(width: 6, height: 6)
                        Text(note.text).font(.system(size: 12)).foregroundColor(note.isError ? SeedInk.red : SeedInk.second)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        Button { self.note = nil } label: {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundColor(SeedInk.faint)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss")
                    }
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(SeedInk.raised)
                    .overlay(alignment: .top) { Rectangle().fill(SeedInk.line).frame(height: 1) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(SeedInk.bg)
        }
        .background(SeedInk.bg)
        .tint(SeedInk.gold)
        .preferredColorScheme(.dark)
        .onChange(of: pageID) { _, _ in note = nil }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                RiceMascotView(motion: mascot, box: 30, paused: true)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Seed").font(.system(size: 13, weight: .semibold)).foregroundColor(SeedInk.text)
                    Text(version).font(.system(size: 11)).monospacedDigit().foregroundColor(SeedInk.faint)
                }
            }
            .padding(.horizontal, 8).padding(.top, 16).padding(.bottom, 12)
            ForEach(SeedSettingsPage.allCases) { item in
                SeedSidebarRow(page: item, selected: item == page) { pageID = item.rawValue }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(width: 192)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(SeedInk.raised)
    }
}

private struct SeedSidebarRow: View {
    let page: SeedSettingsPage
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: page.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(selected ? SeedInk.gold : SeedInk.muted)
                    .frame(width: 16)
                Text(page.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundColor(selected ? SeedInk.text : SeedInk.second)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(SeedInk.gold.opacity(selected ? 0.12 : (hover ? 0.06 : 0))))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Building blocks

private struct SeedCard<Content: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold)).tracking(0.6)
                    .foregroundColor(SeedInk.muted)
                if let detail {
                    Text(detail).font(.system(size: 12)).foregroundColor(SeedInk.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: 12).fill(SeedInk.raised))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(SeedInk.line))
        }
    }
}

/// One line in a card: label on the left, control on the right, hairline below unless last.
private struct SeedRow<Trailing: View>: View {
    let title: String
    var detail: String? = nil
    var last = false
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13)).foregroundColor(SeedInk.text)
                if let detail {
                    Text(detail).font(.system(size: 11)).foregroundColor(SeedInk.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(SeedInk.line).frame(height: 1).padding(.leading, 16) }
        }
    }
}

private struct SeedStatus: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 11, weight: .medium)).foregroundColor(color)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.12)))
    }
}

/// The exact JSON about to be written, with Write and Cancel. Nothing is written before Write.
private struct SeedDiffBox: View {
    let title: String
    let json: String
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11)).foregroundColor(SeedInk.muted)
            ScrollView {
                Text(json)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(SeedInk.second)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 140)
            .background(RoundedRectangle(cornerRadius: 8).fill(SeedInk.bg))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SeedInk.line))
            HStack(spacing: 8) {
                Button("Write", action: confirm).buttonStyle(SeedButtonStyle(primary: true))
                Button("Cancel", action: cancel).buttonStyle(SeedButtonStyle())
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
    }
}

// MARK: - General

private struct SeedGeneralPage: View {
    @Binding var note: SeedSettingsView.Note?
    @ObservedObject private var state = AppState.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var hotkeyFlags = AppState.shared.hotkeyFlags
    @State private var hotkeyCode = AppState.shared.hotkeyCode

    private var absenceMinutes: Binding<Double> {
        Binding(get: { state.absenceInterval / 60 }, set: { state.absenceInterval = max(1, $0) * 60 })
    }

    var body: some View {
        SeedCard(title: "Sound") {
            SeedRow(title: "Sounds", detail: "Seed's soft cues for new requests, files and replies.") {
                Toggle("", isOn: $state.soundEnabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            SeedRow(title: "Volume", last: true) {
                HStack(spacing: 8) {
                    Slider(value: $state.soundVolume, in: 0...0.2) { editing in
                        if !editing { SoundEngine.shared.play("pop") }
                    }
                    .frame(width: 180)
                    .disabled(!state.soundEnabled)
                    Text("\(Int(state.soundVolume / 0.2 * 100))%")
                        .font(.system(size: 12)).monospacedDigit().foregroundColor(SeedInk.muted)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }

        SeedCard(title: "Notch") {
            SeedRow(title: "Fold the notch", detail: "After this many seconds without the pointer.") {
                numberField(Binding(get: { state.autoCloseInterval }, set: { state.autoCloseInterval = max(3, $0) }), unit: "s")
            }
            SeedRow(title: "Hide Seed", detail: "After this many minutes without any movement.", last: true) {
                numberField(absenceMinutes, unit: "min")
            }
        }

        SeedCard(title: "Keyboard") {
            SeedRow(title: "Open the notch with a shortcut", last: !state.hotkeyEnabled) {
                Toggle("", isOn: $state.hotkeyEnabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .onChange(of: state.hotkeyEnabled) { _, _ in HotKeyCenter.shared.reregister(.toggleIsland) }
            }
            if state.hotkeyEnabled {
                SeedRow(title: "Shortcut", last: true) {
                    ShortcutRecorderButton(flags: $hotkeyFlags, code: $hotkeyCode)
                        .onChange(of: hotkeyFlags) { _, v in
                            state.hotkeyFlags = v
                            HotKeyCenter.shared.reregister(.toggleIsland)
                        }
                        .onChange(of: hotkeyCode) { _, v in
                            state.hotkeyCode = v
                            HotKeyCenter.shared.reregister(.toggleIsland)
                        }
                }
            }
        }

        SeedCard(title: "Startup") {
            SeedRow(title: "Open Seed when you log in", last: true) {
                Toggle("", isOn: $launchAtLogin).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
            }
        }
    }

    private func numberField(_ value: Binding<Double>, unit: String) -> some View {
        HStack(spacing: 8) {
            TextField("", value: value, format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 12)).monospacedDigit()
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .frame(width: 56)
                .background(RoundedRectangle(cornerRadius: 6).fill(SeedInk.bg))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(SeedInk.line))
            Text(unit).font(.system(size: 12)).foregroundColor(SeedInk.muted).frame(width: 28, alignment: .leading)
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            note = .init(text: "macOS did not accept the change: \(error.localizedDescription)", isError: true)
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Agents

/// Agents that report to Seed through a small hook in their own settings file.
private enum SeedHookAgent: String, CaseIterable, Identifiable {
    case claude, codex, gemini, antigravity
    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude:      return "Claude Code"
        case .codex:       return "Codex"
        case .gemini:      return "Gemini CLI"
        case .antigravity: return "Antigravity"
        }
    }

    var file: String {
        switch self {
        case .claude:      return "~/.claude/settings.json"
        case .codex:       return "~/.codex/hooks.json"
        case .gemini:      return "~/.gemini/settings.json"
        case .antigravity: return "~/.gemini/config/hooks.json"
        }
    }

    /// What the user does after connecting so the agent picks the hook up.
    var afterConnect: String {
        switch self {
        case .claude:      return "Start a new Claude Code session to use it."
        case .codex:       return "In Codex, run /hooks (or open Hooks in the app's settings) and trust Seed's hooks."
        case .gemini:      return "Restart Gemini CLI to use it."
        case .antigravity: return "Restart Antigravity to use it."
        }
    }

    var installed: Bool {
        switch self {
        case .claude:
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
            return (try? String(contentsOf: url, encoding: .utf8))?.contains("nb-hook") ?? false
        case .codex:       return HookServer.codexHooksInstalled()
        case .gemini:      return HookServer.geminiHooksInstalled()
        case .antigravity: return HookServer.agyHooksInstalled()
        }
    }
}

private struct SeedAgentsPage: View {
    @Binding var note: SeedSettingsView.Note?
    @ObservedObject private var model = CoucouHubIntegration.shared.model
    @ObservedObject private var state = AppState.shared

    private enum Pending: Equatable {
        case hook(SeedHookAgent, install: Bool, json: String)
        case statusLine(install: Bool, json: String)
    }

    @State private var installed: [SeedHookAgent: Bool] = [:]
    @State private var claudeNeedsUpdate = HookServer.hooksNeedUpdate()
    @State private var pending: Pending?
    @State private var inviteName = ""
    @State private var inviteKind = "codex"
    @State private var inviting = false
    @State private var invite: String?
    @State private var showAllAgents = false

    var body: some View {
        teamCard
        inviteCard
        hooksCard
        usageCard
            .onAppear {
                reloadInstalled()
                state.refreshPlanRelayState()
                model.refresh()
                model.refreshOperatorTasks()
            }
    }

    // MARK: Team (Tincan through LinkHub)

    private var teamStatus: (String, Color, String?) {
        switch model.tincanAccess {
        case .notChecked: return ("Checking", SeedInk.muted, nil)
        case .needsCredential:
            return ("Not set up", SeedInk.amber, "This Mac has no LinkHub credential for Seed yet. Connect it with the trusted installer in agent-linkhub (with Tincan approval on), then Refresh.")
        case .permissionRequired:
            return ("Read-only", SeedInk.amber, "The LinkHub credential can read tools but not your agent team. Reconnect it with Tincan approval on.")
        case .unauthorized:
            return ("Access denied", SeedInk.red, "The LinkHub credential was revoked or expired. Reconnect it with the trusted installer.")
        case .offline:
            return ("LinkHub offline", SeedInk.red, "Start LinkHub on this Mac, then Refresh. Seed reads your agents from it at 127.0.0.1:8768.")
        case .error:
            return ("Error", SeedInk.red, model.tincanErrorMessage ?? "Refresh and try again.")
        case .ready:
            guard let roster = model.tincanRoster, roster.status == .ready, roster.enabled else {
                return ("Connected", SeedInk.cyan, "LinkHub is connected, but it has not read the Tincan roster yet.")
            }
            let online = roster.agents.filter(\.online).count
            return ("\(online) of \(roster.agents.count) online", SeedInk.green, nil)
        }
    }

    private var teamCard: some View {
        let (label, color, help) = teamStatus
        let agents = model.tincanRoster?.agents ?? []
        let visible = showAllAgents ? agents : agents.filter { !CoucouHubFormat.isDiagnostic($0) }
        let hidden = agents.count - agents.filter { !CoucouHubFormat.isDiagnostic($0) }.count
        return SeedCard(title: "Your agent team",
                        detail: "Agents that joined your Tincan team, read through LinkHub. They fill the Agents and Timeline tabs and their requests wait for you in Review.") {
            SeedRow(title: "Tincan through LinkHub", detail: help, last: visible.isEmpty && hidden == 0) {
                HStack(spacing: 8) {
                    SeedStatus(text: label, color: color)
                    Button {
                        model.refresh()
                        model.refreshOperatorTasks()
                    } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(SeedButtonStyle())
                    .accessibilityLabel("Refresh")
                    Button("Open Manager") { NSWorkspace.shared.open(HubIslandEndpoint.console) }
                        .buttonStyle(SeedButtonStyle())
                }
            }
            ForEach(Array(visible.enumerated()), id: \.element.id) { i, agent in
                agentRow(agent, last: i == visible.count - 1 && hidden == 0)
            }
            if hidden > 0 {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showAllAgents.toggle() }
                } label: {
                    Text(showAllAgents ? "Hide \(hidden) diagnostic" : "Show \(hidden) diagnostic")
                        .font(.system(size: 11)).foregroundColor(SeedInk.faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func agentRow(_ agent: HubTincanAgent, last: Bool) -> some View {
        let name = CoucouHubFormat.display(agent.name.isEmpty ? agent.id : agent.name)
        var bits: [String] = []
        if let kind = agent.kind, !kind.isEmpty { bits.append(CoucouHubFormat.pretty(kind)) }
        if let wake = agent.wake, !wake.isEmpty, wake.lowercased() != "none" { bits.append("wakes by \(CoucouHubFormat.pretty(wake).lowercased())") }
        if agent.queued > 0 { bits.append("\(agent.queued) queued") }
        return HStack(spacing: 8) {
            Circle().fill(Color(hex: CoucouHubFormat.color(for: agent.id))).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13)).foregroundColor(SeedInk.text)
                if !bits.isEmpty {
                    Text(bits.joined(separator: " · ")).font(.system(size: 11)).foregroundColor(SeedInk.faint).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            SeedStatus(text: agent.online ? "Online" : "Offline", color: agent.online ? SeedInk.green : SeedInk.faint)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(SeedInk.line).frame(height: 1).padding(.leading, 32) }
        }
    }

    // MARK: Invite

    private var inviteCard: some View {
        SeedCard(title: "Add an agent",
                 detail: "Seed asks Tincan on this Mac for a one-time invite. Paste the message into the agent (within 10 minutes) and it joins itself.") {
            HStack(spacing: 8) {
                TextField("name, e.g. codex-2", text: $inviteName)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(width: 160)
                    .background(RoundedRectangle(cornerRadius: 6).fill(SeedInk.bg))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(SeedInk.line))
                    .onChange(of: inviteName) { _, v in
                        let clean = String(v.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(24))
                        if clean != v { inviteName = clean }
                    }
                Picker("", selection: $inviteKind) {
                    ForEach(SeedAgentInvite.kinds, id: \.id) { Text($0.title).tag($0.id) }
                }
                .labelsHidden().frame(width: 140)
                Spacer(minLength: 0)
                Button(inviting ? "Creating…" : "Create invite") { createInvite() }
                    .buttonStyle(SeedButtonStyle(primary: true))
                    .disabled(inviting || !SeedAgentInvite.validName(inviteName))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            if let invite {
                VStack(alignment: .leading, spacing: 8) {
                    Text(invite)
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(SeedInk.second)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(SeedInk.bg))
                    HStack(spacing: 8) {
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(invite, forType: .string)
                            note = .init(text: "Copied. Paste it into the agent.", isError: false)
                        }
                        .buttonStyle(SeedButtonStyle(primary: true))
                        Button("Done") { self.invite = nil; inviteName = "" }.buttonStyle(SeedButtonStyle())
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 12)
            }
        }
    }

    private func createInvite() {
        inviting = true
        let name = inviteName, kind = inviteKind
        Task {
            let result = await SeedAgentInvite.create(name: name, kind: kind)
            inviting = false
            switch result {
            case .success(let text):
                invite = text
                note = .init(text: "Invite for \(name) is ready.", isError: false)
            case .failure(let error):
                note = .init(text: error.message, isError: true)
            }
        }
    }

    // MARK: Hooks

    private var hooksCard: some View {
        SeedCard(title: "Live from your terminal",
                 detail: "A small hook lets an agent tell Seed what it is doing and ask you before it runs a command. Seed shows you the exact change and writes it only when you click Write.") {
            ForEach(Array(SeedHookAgent.allCases.enumerated()), id: \.element) { i, agent in
                let isOn = installed[agent] ?? false
                SeedRow(title: agent.title,
                        detail: agent == .claude && isOn && claudeNeedsUpdate
                            ? "Hook is out of date. Update it to answer Claude's questions from the notch."
                            : agent.file,
                        last: i == SeedHookAgent.allCases.count - 1 && !isPending(agent)) {
                    HStack(spacing: 8) {
                        SeedStatus(text: isOn ? "Connected" : "Not connected", color: isOn ? SeedInk.green : SeedInk.faint)
                        if agent == .claude && isOn && claudeNeedsUpdate {
                            Button("Update") { preview(agent, install: true) }.buttonStyle(SeedButtonStyle(primary: true))
                        }
                        Button(isOn ? "Disconnect" : "Connect") { preview(agent, install: !isOn) }
                            .buttonStyle(SeedButtonStyle(primary: !isOn))
                            .disabled(pending != nil)
                    }
                }
                if case .hook(let a, let install, let json) = pending, a == agent {
                    SeedDiffBox(title: install ? "\(agent.file) after this change:" : (agent == .claude ? "Disconnect Claude Code:" : "\(agent.file) after removing Seed's hook:"),
                                json: json, confirm: { write(agent, install: install) }, cancel: { pending = nil })
                }
            }
        }
    }

    private func isPending(_ agent: SeedHookAgent) -> Bool {
        if case .hook(let a, _, _) = pending { return a == agent }
        return false
    }

    private func reloadInstalled() {
        for agent in SeedHookAgent.allCases { installed[agent] = agent.installed }
        claudeNeedsUpdate = HookServer.hooksNeedUpdate()
    }

    private func preview(_ agent: SeedHookAgent, install: Bool) {
        do {
            let json: String
            switch agent {
            case .claude:
                guard install else {
                    // Claude's uninstaller has no preview: say exactly what it removes.
                    pending = .hook(agent, install: false, json: "Removes the hook entries whose command points to Seed's nb-hook (in Application Support/NotchBuddy) from \"hooks\" in ~/.claude/settings.json. Everything else in the file stays as it is.")
                    return
                }
                json = try HookServer.shared.previewClaudeHooks()
            case .codex:       json = try HookServer.shared.previewCodexHooks(install: install)
            case .gemini:      json = try HookServer.shared.previewGeminiHooks(install: install)
            case .antigravity: json = try HookServer.shared.previewAgyHooks(install: install)
            }
            pending = .hook(agent, install: install, json: json)
        } catch let e as NSError where e.domain == "CoucouNoop" {
            note = .init(text: e.localizedDescription, isError: false)
        } catch {
            note = .init(text: error.localizedDescription, isError: true)
        }
    }

    private func write(_ agent: SeedHookAgent, install: Bool) {
        do {
            switch agent {
            case .claude:      try install ? HookServer.shared.writeClaudeHooks() : HookServer.shared.uninstallClaudeHooks()
            case .codex:       try HookServer.shared.writeCodexHooks()
            case .gemini:      try HookServer.shared.writeGeminiHooks()
            case .antigravity: try HookServer.shared.writeAgyHooks()
            }
            pending = nil
            reloadInstalled()
            note = .init(text: install ? "\(agent.title) connected. \(agent.afterConnect)" : "\(agent.title) disconnected.", isError: false)
        } catch {
            note = .init(text: "Could not write \(agent.file): \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: Usage

    private var usageCard: some View {
        SeedCard(title: "Plan usage",
                 detail: "Your Claude plan's 5-hour and weekly limits in the Usage tab. Seed adds a status line relay to ~/.claude/settings.json; a status line you already have keeps working. Pro and Max plans only.") {
            SeedRow(title: "Claude status line relay",
                    detail: state.planRelayInstalled ? "Installed" : "Not installed",
                    last: !isStatusLinePending) {
                Button(state.planRelayInstalled ? "Remove" : "Install") { previewStatusLine(install: !state.planRelayInstalled) }
                    .buttonStyle(SeedButtonStyle(primary: !state.planRelayInstalled))
                    .disabled(pending != nil)
            }
            if case .statusLine(let install, let json) = pending {
                SeedDiffBox(title: "~/.claude/settings.json after this change:", json: json,
                            confirm: { writeStatusLine(install: install) }, cancel: { pending = nil })
            }
        }
    }

    private var isStatusLinePending: Bool {
        if case .statusLine = pending { return true }
        return false
    }

    private func previewStatusLine(install: Bool) {
        do {
            pending = .statusLine(install: install, json: try HookServer.shared.previewStatusLine(install: install))
        } catch {
            note = .init(text: error.localizedDescription, isError: true)
        }
    }

    private func writeStatusLine(install: Bool) {
        do {
            try HookServer.shared.writeStatusLine()
            pending = nil
            state.refreshPlanRelayState()
            state.showPlanInNotch = install
            note = .init(text: install ? "Status line relay installed." : "Status line relay removed.", isError: false)
        } catch {
            note = .init(text: error.localizedDescription, isError: true)
        }
    }
}

// MARK: - Action Ring

private struct SeedRingPage: View {
    @ObservedObject private var ring = SeedRingStore.shared

    var body: some View {
        SeedCard(title: "In the ring · \(ring.slots.count) of \(SeedRingStore.capacity)",
                 detail: "Tap Seed in the notch and these bloom around it. The first sits at the top of the fan.") {
            ForEach(Array(ring.slots.enumerated()), id: \.element) { i, action in
                SeedRow(title: action.title, last: i == ring.slots.count - 1) {
                    HStack(spacing: 4) {
                        Button { ring.move(action, by: -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(SeedButtonStyle()).disabled(i == 0)
                            .accessibilityLabel("Move \(action.title) up")
                        Button { ring.move(action, by: 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(SeedButtonStyle()).disabled(i == ring.slots.count - 1)
                            .accessibilityLabel("Move \(action.title) down")
                        Button { ring.toggle(action) } label: { Image(systemName: "minus") }
                            .buttonStyle(SeedButtonStyle()).disabled(ring.slots.count <= 1)
                            .accessibilityLabel("Remove \(action.title)")
                    }
                }
            }
        }

        let rest = SeedAction.allCases.filter { !ring.slots.contains($0) }
        if !rest.isEmpty {
            SeedCard(title: "More actions",
                     detail: ring.slots.count >= SeedRingStore.capacity ? "The ring is full. Remove one to add another." : nil) {
                ForEach(Array(rest.enumerated()), id: \.element) { i, action in
                    SeedRow(title: action.title, last: i == rest.count - 1) {
                        Button { ring.toggle(action) } label: { Image(systemName: "plus") }
                            .buttonStyle(SeedButtonStyle())
                            .disabled(ring.slots.count >= SeedRingStore.capacity)
                            .accessibilityLabel("Add \(action.title)")
                    }
                }
            }
        }

        HStack {
            Button("Reset to defaults") { ring.reset() }.buttonStyle(SeedButtonStyle())
            Spacer()
        }
        .onAppear { ring.reload() }
    }
}

// MARK: - Folders

private struct SeedFoldersSettingsPage: View {
    @ObservedObject private var folders = SeedFolderStore.shared

    var body: some View {
        SeedCard(title: "Pinned folders · \(folders.pins.count) of \(SeedFolderStore.capacity)",
                 detail: "Browse these from the notch and drag files out into your agents. Seed only lists them: it never moves, renames or deletes anything.") {
            if folders.pins.isEmpty {
                SeedRow(title: "No folders yet", detail: "Add one here, or drop a folder on the notch while Folders is open.", last: true) { EmptyView() }
            }
            ForEach(Array(folders.pins.enumerated()), id: \.element) { i, url in
                SeedRow(title: url.lastPathComponent,
                        detail: (url.path as NSString).abbreviatingWithTildeInPath,
                        last: i == folders.pins.count - 1) {
                    HStack(spacing: 4) {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            .buttonStyle(SeedButtonStyle())
                        Button("Unpin") { folders.unpin(url) }.buttonStyle(SeedButtonStyle())
                    }
                }
            }
        }
        HStack {
            Button("Add folder…") { addFolder() }
                .buttonStyle(SeedButtonStyle(primary: true))
                .disabled(folders.pins.count >= SeedFolderStore.capacity)
            Spacer()
        }
        .onAppear { folders.reload() }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Pin"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { folders.pin(url) }
    }
}

// MARK: - About

private struct SeedAboutPage: View {
    var body: some View {
        SeedCard(title: "Seed") {
            SeedRow(title: "Version",
                    detail: Bundle.main.bundleIdentifier) {
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                    .font(.system(size: 12)).monospacedDigit().foregroundColor(SeedInk.muted)
            }
            SeedRow(title: "Customize Seed with your agent",
                    detail: "Ask your agent to read docs/seed/SEED_SKILL.md. It can change the Action Ring and pinned folders for you.",
                    last: true) { EmptyView() }
        }
        SeedCard(title: "Privacy") {
            SeedRow(title: "No telemetry", detail: "Seed sends nothing about you anywhere.") { EmptyView() }
            SeedRow(title: "Stays on this Mac", detail: "Seed talks only to LinkHub and Tincan on this Mac, and to the agents you connect.") { EmptyView() }
            SeedRow(title: "Secrets in the Keychain", detail: "Credentials are never written to disk or to settings files.", last: true) { EmptyView() }
        }
        HStack {
            Button("Quit Seed") { NSApp.terminate(nil) }.buttonStyle(SeedButtonStyle())
            Spacer()
        }
    }
}
#endif
