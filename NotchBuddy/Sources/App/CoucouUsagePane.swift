#if COUCOU_HUB
import SwiftUI

// MARK: - AI usage cards
//
// Presentation over snapshots that already exist. Only Claude's opt-in
// statusline relay is wired; other providers say "unavailable", never 0%.

struct CoucouUsagePane: View {
    @ObservedObject var state: AppState
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    @State private var now = Date()
    /// Details open only when a card is tapped; tapping it again closes them.
    @State private var selectedID: String?
    @State private var showInfo = false

    private static let unwiredProviders = ["codex", "gemini-cli", "antigravity"]

    private var claude: CoucouUsageSnapshot {
        CoucouHubIntegration.shared.claudeUsage(state.claudePlanUsage, now: now)
    }
    private var snapshots: [CoucouUsageSnapshot] {
        [claude] + Self.unwiredProviders.map { CoucouUsageSnapshot.unavailable(providerID: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CoucouWorkspaceStyle.sectionGap) {
            CoucouSectionHeader(title: "Usage", subtitle: "", onClose: onClose) {
                CoucouInfoToggle(isOn: $showInfo)
            }
            if showInfo {
                CoucouWorkspaceStyle.finePrint([
                    "Only what each provider reports. \(CoucouBrand.name) never reads credentials or scrapes a provider to fill these cards.",
                    "A provider without a supported source shows “No data”, never 0%.",
                ])
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CoucouWorkspaceStyle.gap) {
                    ForEach(snapshots, id: \.providerID) { snapshot in card(snapshot) }
                }
            }
            .frame(height: Self.cardHeight)
            Group {
                if selectedSnapshot != nil {
                    detail
                } else {
                    Text("Tap a card for details.")
                        .font(.system(size: 11)).foregroundColor(Color(hex: "#6B7079"))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // Only ticks while this pane is on screen.
        .background(
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Color.clear.onChange(of: context.date) { _, date in now = date }
            }
        )
        .onAppear { now = Date() }
    }

    // MARK: Cards

    static let cardHeight: CGFloat = 96

    private func card(_ snapshot: CoucouUsageSnapshot) -> some View {
        let selected = selectedID == snapshot.providerID
        let stale = snapshot.availability == .stale
        let unavailable = snapshot.availability == .unavailable
        let isClaude = snapshot.providerID == "claude-code"
        return Button {
            SoundEngine.shared.play("tick")
            SeedReaction.notice(dx: 1, dy: 0.2)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedID = selected ? nil : snapshot.providerID
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: dotHex(snapshot))).frame(width: 6, height: 6)
                    Text(CoucouWorkspaceFormat.providerName(snapshot.providerID))
                        .font(.system(size: 11.5, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                    if stale {
                        Text("Stale").font(.system(size: 9, weight: .bold)).foregroundColor(.black)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color(hex: "#F5A524"), in: Capsule())
                    }
                }
                if unavailable {
                    Spacer(minLength: 0)
                    Text(isClaude ? claudeUnavailableTitle : "No data")
                        .font(.system(size: 11)).foregroundColor(Color(hex: "#6B7079"))
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(snapshot.windows, id: \.id) { window in bar(window) }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(12)
            .frame(width: unavailable && !isClaude ? 112 : 184, height: Self.cardHeight, alignment: .topLeading)
            .background(CoucouWorkspaceStyle.rowBackground(RoundedRectangle(cornerRadius: 14)))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(selected ? 0.22 : 0), lineWidth: 1))
            .opacity(stale || (unavailable && !isClaude) ? 0.7 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(snapshot))
        .accessibilityHint(selected ? "Hide details" : "Show details")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func bar(_ window: CoucouUsageSnapshot.Window) -> some View {
        let passed = window.resetsAt <= now
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(CoucouWorkspaceFormat.windowTitle(window.id))
                    .font(.system(size: 10.5)).foregroundColor(Color(hex: "#8E939C"))
                Spacer(minLength: 2)
                Text(passed ? "Reset passed" : "\(Int(window.usedPercent.rounded()))%")
                    .font(.system(size: passed ? 10.5 : 12, weight: .semibold)).monospacedDigit()
                    .foregroundColor(Color(hex: passed ? "#F5A524" : "#F5F6F8"))
            }
            // A passed reset draws no bar: an elapsed window is not an empty limit.
            if !passed {
                GeometryReader { bounds in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(Color(hex: ClaudePlanGauge.color(for: window.usedPercent)))
                            .frame(width: bounds.size.width * min(1, max(0, window.usedPercent / 100)))
                    }
                }
                .frame(height: 4)
            }
        }
    }

    // MARK: Detail

    private var selectedSnapshot: CoucouUsageSnapshot? { snapshots.first { $0.providerID == selectedID } }

    @ViewBuilder private var detail: some View {
        if let snapshot = selectedSnapshot {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 7) {
                    fact("Source", CoucouWorkspaceFormat.sourceName(snapshot.source))
                    if let observed = snapshot.observedAt {
                        fact("Observed", "\(CoucouWorkspaceFormat.ago(observed, now: now)) · \(observed.formatted(date: .abbreviated, time: .shortened))")
                    }
                    if let reason = CoucouWorkspaceFormat.staleReason(snapshot, now: now) {
                        fact("Stale", reason, warn: true)
                    }
                    ForEach(snapshot.windows, id: \.id) { window in
                        fact(CoucouWorkspaceFormat.windowTitle(window.id),
                             CoucouWorkspaceFormat.windowDetail(window, now: now))
                    }
                    if snapshot.availability == .unavailable { unavailableDetail(snapshot) }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(12)
                .padding(.bottom, 6)
            }
            .mask(CoucouWorkspaceStyle.scrollFade)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "#0E0F11")))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.05), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder private func unavailableDetail(_ snapshot: CoucouUsageSnapshot) -> some View {
        if snapshot.providerID == "claude-code" {
            Text(state.planRelayInstalled
                 ? "The statusline relay is on. Numbers appear after Claude Code's next reply."
                 : "Turn on the Claude Code statusline relay in Settings to see plan usage here.")
                .font(.system(size: 11)).foregroundColor(Color(hex: "#C5C8CD"))
                .fixedSize(horizontal: false, vertical: true)
            if !state.planRelayInstalled {
                SecondaryButton("Open Settings", action: onOpenSettings)
            }
        } else {
            Text("\(CoucouWorkspaceFormat.providerName(snapshot.providerID)) has no supported usage source yet, so nothing is shown rather than a guess.")
                .font(.system(size: 11)).foregroundColor(Color(hex: "#C5C8CD"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fact(_ key: String, _ value: String, warn: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key).font(.system(size: 11)).foregroundColor(Color(hex: "#6B7079")).frame(width: 66, alignment: .leading)
            Text(value).font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: warn ? "#F5A524" : "#C5C8CD"))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Text

    private var claudeUnavailableTitle: String { state.planRelayInstalled ? "Waiting for data" : "Relay off · tap to set up" }

    private func dotHex(_ snapshot: CoucouUsageSnapshot) -> String {
        guard snapshot.availability == .available,
              let top = snapshot.windows.map(\.usedPercent).max() else { return "#6B7079" }
        return ClaudePlanGauge.color(for: top)
    }

    private func accessibilityText(_ snapshot: CoucouUsageSnapshot) -> String {
        let name = CoucouWorkspaceFormat.providerName(snapshot.providerID)
        switch snapshot.availability {
        case .unavailable: return "\(name), unavailable"
        case .available, .stale:
            let windows = snapshot.windows.map {
                "\(CoucouWorkspaceFormat.windowTitle($0.id)) \(CoucouWorkspaceFormat.usedText($0)), \(CoucouWorkspaceFormat.resetText($0, now: now))"
            }.joined(separator: "; ")
            return "\(name)\(snapshot.availability == .stale ? ", stale" : ""), \(windows)"
        }
    }
}
#endif
