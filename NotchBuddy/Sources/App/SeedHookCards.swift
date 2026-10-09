#if COUCOU_HUB
import SwiftUI
import AppKit

// MARK: - Seed's cards for terminal agents (hooks)
//
// When Claude Code, Codex or Gemini asks through its hook, the notch opens on
// one of these cards. Seed stands on the left (its pose follows the card) and
// the card says who is asking, what, and offers the answer. Allow is never
// bound to a key: approving always takes a click. The decisions go through the
// existing HookServer calls, unchanged.

/// The card surface: Seed's raised dark, a hairline, and a thin status light on top.
struct SeedAlertCard<Content: View>: View {
    let tone: Color
    @ViewBuilder let content: Content
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16).fill(SeedInk.raised)
            RoundedRectangle(cornerRadius: 16).strokeBorder(SeedInk.line)
            // The status light: a short line of the card's colour along the top edge.
            Capsule().fill(tone)
                .frame(width: 32, height: 2)
                .padding(.leading, 116)
                .shadow(color: tone.opacity(0.6), radius: 4)
                .opacity(0.9)
            content
                .padding(.leading, 116).padding(.trailing, 16).padding(.vertical, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .opacity(shown ? 1 : 0)
                .offset(y: shown || reduceMotion ? 0 : 4)
        }
        .onAppear { withAnimation(reduceMotion ? nil : SeedInk.spring.delay(0.05)) { shown = true } }
    }
}

/// "● Codex  wants to run" — who, in its colour, then what.
struct SeedWho: View {
    let task: AgentTask?
    let label: String
    var fallback = "An agent"

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(task.map { Color(hex: $0.color) } ?? SeedInk.muted).frame(width: 8, height: 8)
            Text(task?.name ?? fallback).font(.system(size: 12, weight: .semibold)).foregroundColor(SeedInk.text)
            Text(label).font(.system(size: 12)).foregroundColor(SeedInk.muted)
        }
        .lineLimit(1)
    }
}

// MARK: Approval

struct SeedApprovalCard: View {
    @ObservedObject var state: AppState
    @State private var decided: String?
    @State private var expanded = false

    private var approval: ApprovalInfo? { state.pendingApproval }
    private var task: AgentTask? {
        approval.flatMap { a in state.tasks.first { $0.id == a.pillId } } ?? state.focusTask
    }
    private var text: String { approval?.command.isEmpty == false ? approval!.command : (approval?.tool ?? "…") }

    var body: some View {
        SeedAlertCard(tone: SeedInk.amber) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    SeedWho(task: task, label: "wants to run")
                    Spacer(minLength: 8)
                    if let tool = approval?.tool, !tool.isEmpty {
                        Text(tool)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(SeedInk.muted)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                    }
                }
                Button { withAnimation(SeedInk.spring) { expanded.toggle() } } label: {
                    Text(text)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(SeedInk.text)
                        .lineLimit(expanded ? 4 : 1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(SeedInk.bg))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SeedInk.amber.opacity(0.25)))
                }
                .buttonStyle(.plain)
                .help(text)
                .accessibilityLabel("Command: \(text)")
                HStack(spacing: 8) {
                    Button("Allow") { decide("allow") }
                        .buttonStyle(SeedButtonStyle(primary: true))
                    Button("Deny") { decide("deny") }
                        .buttonStyle(SeedButtonStyle())
                    // Codex rejects updatedPermissions, so "Always" is not offered.
                    if approval?.pillId != "agent_codex" {
                        Button("Always allow") { decide("always") }
                            .buttonStyle(SeedButtonStyle())
                    }
                    Spacer(minLength: 0)
                    if let decided {
                        Text(decided == "deny" ? "Denied" : "Allowed")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(decided == "deny" ? SeedInk.muted : SeedInk.green)
                            .transition(.opacity)
                    }
                }
                .disabled(decided != nil)
            }
        }
        .onChange(of: state.pendingApproval?.sessionId) { _, _ in decided = nil; expanded = false }
    }

    private func decide(_ answer: String) {
        guard decided == nil else { return }
        withAnimation(SeedInk.spring) { decided = answer }
        HookServer.shared.sendApprovalDecision(answer)
    }
}

// MARK: Question

struct SeedQuestionCard: View {
    @ObservedObject var state: AppState
    @State private var index = 0
    @State private var selections: [[String]] = []
    @State private var otherTexts: [String] = []
    @State private var showOther: [Bool] = []
    @FocusState private var otherFocused: Bool

    private var question: AskQuestion? { state.pendingQuestion }

    var body: some View {
        SeedAlertCard(tone: SeedInk.cyan) {
            if let q = question, !q.questions.isEmpty {
                let qi = min(index, q.questions.count - 1)
                let item = q.questions[qi]
                let isLast = qi == q.questions.count - 1
                let picked = qi < selections.count ? selections[qi] : []
                let other = qi < showOther.count && showOther[qi]
                let otherText = qi < otherTexts.count ? otherTexts[qi] : ""
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        SeedWho(task: state.tasks.first { $0.id == "integration_claude" }, label: "is asking")
                        if !item.header.isEmpty {
                            Text(item.header.uppercased())
                                .font(.system(size: 10, weight: .semibold)).tracking(0.5)
                                .foregroundColor(SeedInk.faint)
                        }
                        Spacer(minLength: 8)
                        if q.questions.count > 1 { steps(q.questions.count, current: qi) }
                        Button("Answer in terminal") { HookServer.shared.sendQuestionAsk() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundColor(SeedInk.faint)
                    }
                    Text(item.question)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SeedInk.text)
                        .lineLimit(2)
                        .id("q\(qi)")
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .opacity))
                    if other {
                        otherRow(q: q, qi: qi, isLast: isLast, text: otherText)
                    } else {
                        ChipFlowLayout(spacing: 6) {
                            ForEach(Array(item.options.enumerated()), id: \.offset) { i, opt in
                                SeedOptionChip(number: i + 1, label: opt.label, detail: opt.description,
                                               selected: picked.contains(opt.label), multi: item.multiSelect) {
                                    if item.multiSelect { toggle(qi, opt.label) } else { pick(q: q, qi: qi, label: opt.label, isLast: isLast) }
                                }
                                .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: [])
                            }
                            SeedOptionChip(number: nil, label: "Other…", detail: "", selected: false, multi: false) {
                                if qi < showOther.count { withAnimation(SeedInk.spring) { showOther[qi] = true } }
                            }
                            if item.multiSelect {
                                Button(isLast ? "Send" : "Next") { advance(q: q, qi: qi, isLast: isLast) }
                                    .buttonStyle(SeedButtonStyle(primary: true, compact: true))
                                    .disabled(picked.isEmpty)
                            }
                        }
                    }
                }
            }
        }
        .onAppear(perform: reset)
        .onChange(of: state.pendingQuestion) { _, _ in reset() }
        .onDisappear { HookServer.shared.releaseQuestionFD() }
    }

    /// Small dots for a multi-question form, the current one in gold.
    private func steps(_ count: Int, current: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(i == current ? SeedInk.gold : (i < current ? SeedInk.muted : SeedInk.line))
                    .frame(width: i == current ? 12 : 4, height: 4)
            }
        }
        .animation(SeedInk.spring, value: current)
        .accessibilityElement()
        .accessibilityLabel("Question \(current + 1) of \(count)")
    }

    private func otherRow(q: AskQuestion, qi: Int, isLast: Bool, text: String) -> some View {
        HStack(spacing: 8) {
            TextField("Your answer…", text: Binding(
                get: { qi < otherTexts.count ? otherTexts[qi] : "" },
                set: { if qi < otherTexts.count { otherTexts[qi] = $0 } }))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(SeedInk.text)
                .focused($otherFocused)
                .onAppear { otherFocused = true }
                .onSubmit { commitOther(q: q, qi: qi, isLast: isLast) }
                .onExitCommand { if qi < showOther.count { showOther[qi] = false } }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(SeedInk.bg))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SeedInk.gold.opacity(otherFocused ? 0.5 : 0.15)))
            Button(isLast ? "Send" : "Next") { commitOther(q: q, qi: qi, isLast: isLast) }
                .buttonStyle(SeedButtonStyle(primary: true, compact: true))
                .disabled(text.isEmpty)
            Button { if qi < showOther.count { withAnimation(SeedInk.spring) { showOther[qi] = false } } } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundColor(SeedInk.faint)
            .accessibilityLabel("Back to the choices")
        }
    }

    private func reset() {
        index = 0
        let n = state.pendingQuestion?.questions.count ?? 0
        selections = Array(repeating: [], count: n)
        otherTexts = Array(repeating: "", count: n)
        showOther = Array(repeating: false, count: n)
    }

    private func toggle(_ qi: Int, _ label: String) {
        guard qi < selections.count else { return }
        withAnimation(SeedInk.spring) {
            if let i = selections[qi].firstIndex(of: label) { selections[qi].remove(at: i) } else { selections[qi].append(label) }
        }
    }

    private func pick(q: AskQuestion, qi: Int, label: String, isLast: Bool) {
        guard qi < selections.count else { return }
        selections[qi] = [label]
        advance(q: q, qi: qi, isLast: isLast)
    }

    private func commitOther(q: AskQuestion, qi: Int, isLast: Bool) {
        let text = qi < otherTexts.count ? otherTexts[qi] : ""
        guard !text.isEmpty else { return }
        if qi < selections.count { selections[qi] = [text] }
        if qi < showOther.count { showOther[qi] = false }
        advance(q: q, qi: qi, isLast: isLast)
    }

    private func advance(q: AskQuestion, qi: Int, isLast: Bool) {
        if isLast {
            HookServer.shared.sendQuestionAnswers(AskQuestion.buildAnswers(questions: q.questions, selections: selections))
        } else {
            withAnimation(SeedInk.spring) { index = qi + 1 }
        }
    }
}

/// One answer: a quiet chip with its number key; selected ones take Seed's gold.
private struct SeedOptionChip: View {
    let number: Int?
    let label: String
    let detail: String
    let selected: Bool
    let multi: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if multi {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11))
                        .foregroundColor(selected ? SeedInk.gold : SeedInk.faint)
                } else if let number {
                    Text("\(number)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(SeedInk.faint)
                        .frame(width: 14, height: 14)
                        .background(RoundedRectangle(cornerRadius: 4).strokeBorder(SeedInk.line))
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(selected ? SeedInk.text : SeedInk.second)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(selected ? SeedInk.gold.opacity(0.14) : Color.white.opacity(hover ? 0.1 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected ? SeedInk.gold.opacity(0.55) : (hover ? SeedInk.gold.opacity(0.35) : SeedInk.line)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(detail)
        .accessibilityLabel(detail.isEmpty ? label : "\(label), \(detail)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Finished

struct SeedFinishedCard: View {
    @ObservedObject var state: AppState

    private var line: String {
        if let fl = state.focusTask?.finalLine, !fl.isEmpty { return fl }
        if let s = state.focusTask?.steps.last(where: { !$0.isDiffStep }) { return s }
        return "Session finished"
    }

    var body: some View {
        SeedAlertCard(tone: SeedInk.green) {
            VStack(alignment: .leading, spacing: 8) {
                SeedWho(task: state.focusTask, label: "is done")
                Text(line)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SeedInk.text)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .help(line)
                HStack(spacing: 8) {
                    Button("Open terminal") { openTerminal() }
                        .buttonStyle(SeedButtonStyle(primary: true))
                    Button("OK") { NotificationCenter.default.post(name: .islandCollapse, object: nil) }
                        .buttonStyle(SeedButtonStyle())
                }
            }
        }
    }

    private func openTerminal() {
        let ids = ["com.apple.Terminal", "com.googlecode.iterm2", "net.kovidgoyal.kitty", "com.mitchellh.ghostty"]
        if let app = ids.lazy.compactMap({ id in NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id } }).first {
            app.activate()
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
        }
        NotificationCenter.default.post(name: .islandCollapse, object: nil)
    }
}
#endif

#if COUCOU_HUB
// MARK: Busy

/// Too many hook events at once: Seed asks for a moment instead of a red error.
struct SeedBusyCard: View {
    var body: some View {
        SeedAlertCard(tone: SeedInk.muted) {
            VStack(alignment: .leading, spacing: 4) {
                Text("A lot is happening at once").font(.system(size: 13, weight: .semibold)).foregroundColor(SeedInk.text)
                Text("Seed will catch up in a few seconds.").font(.system(size: 12)).foregroundColor(SeedInk.muted)
            }
        }
    }
}
#endif
