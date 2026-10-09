#if COUCOU_HUB
import SwiftUI
import AppKit

// MARK: - Clipboard
//
// Points at the Mac's clipboard instead of keeping a separate one: the card at
// the top is whatever is on the system pasteboard now, read only while this
// pane is on screen and the notch is open, and never stored. The optional
// history is opt-in, in memory, and off every launch. No keystrokes are sent
// and no Accessibility permission is needed: drag an item out, or press Copy.

struct CoucouClipboardPane: View {
    @ObservedObject var state: AppState
    @ObservedObject var clipboard: CoucouClipboardAccessService
    let onClose: () -> Void

    @State private var current: CoucouClipboardSnapshot?
    @State private var note: String?
    @State private var lastChangeCount: Int?
    @State private var copiedID: UUID?

    init(state: AppState, clipboard: CoucouClipboardAccessService, onClose: @escaping () -> Void) {
        self.state = state
        self.clipboard = clipboard
        self.onClose = onClose
    }

    @State private var showInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: CoucouWorkspaceStyle.sectionGap) {
            CoucouSectionHeader(title: "Clipboard", subtitle: "", onClose: onClose) {
                if clipboard.isChangeMonitoringEnabled {
                    if !clipboard.history.isEmpty {
                        CoucouHeaderAction("Clear") { SoundEngine.shared.play("tick"); clipboard.clearHistory() }
                            .help("Forget the history kept in memory. The Mac's clipboard is not changed.")
                    }
                    CoucouHeaderAction("Stop history") { SoundEngine.shared.play("tick"); clipboard.disableChangeMonitoring() }
                } else {
                    CoucouHeaderAction("Keep history") { SoundEngine.shared.play("blip"); clipboard.enableChangeMonitoring() }
                        .help("Keep the last \(CoucouClipboardAccessService.maximumHistoryEntries) copies in memory until \(CoucouBrand.name) quits.")
                }
                CoucouInfoToggle(isOn: $showInfo)
            }
            if let note { CoucouWorkspaceStyle.banner(note, symbol: "info.circle", hex: "#8E939C") }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: CoucouWorkspaceStyle.gap) {
                    if showInfo { CoucouWorkspaceStyle.finePrint(finePrint) }
                    CoucouWorkspaceStyle.label("Now")
                    if let current {
                        CoucouClipboardRow(snapshot: current, trailing: { EmptyView() })
                    } else {
                        Text("Nothing to show yet. Text, links, images and files appear here.")
                            .font(.system(size: 11)).foregroundColor(Color(hex: "#6B7079"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    historySection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.bottom, 12)
            }
            .mask(CoucouWorkspaceStyle.scrollFade)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { refresh(force: true) }
        // Cheap counter check once a second, only while this pane exists and
        // the notch is open. Content is read only when the counter changed.
        .background(
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Color.clear.onChange(of: context.date) { _, _ in refresh(force: false) }
            }
        )
    }

    // MARK: History

    @ViewBuilder private var historySection: some View {
        if clipboard.isChangeMonitoringEnabled {
            CoucouWorkspaceStyle.label("Earlier")
                .padding(.top, 4)
            if historyBelowCurrent.isEmpty {
                Text("Copies you make while history is on appear here.")
                    .font(.system(size: 11)).foregroundColor(Color(hex: "#6B7079"))
            } else {
                ForEach(historyBelowCurrent) { snapshot in
                    CoucouClipboardRow(snapshot: snapshot) {
                        rowButton(copiedID == snapshot.id ? "checkmark" : "doc.on.doc",
                                  label: "Copy again",
                                  help: "Put this back on the Mac's clipboard, for apps that don't accept a drag.") {
                            copyAgain(snapshot)
                        }
                        rowButton("xmark", label: "Remove from history") { clipboard.removeSnapshot(id: snapshot.id) }
                    }
                }
            }
        }
    }

    /// Newest first, without the entry that is already shown as "now".
    private var historyBelowCurrent: [CoucouClipboardSnapshot] {
        let shown = current.map { $0.items.map(\.representations) }
        var entries = Array(clipboard.history.reversed())
        if let first = entries.first, first.items.map(\.representations) == shown { entries.removeFirst() }
        return entries
    }

    private var finePrint: [String] {
        [
            "Shows what is on your Mac's clipboard now. macOS keeps its own clipboard history (⌘Space), which apps cannot read.",
            "Items an app marks as private are skipped, but \(CoucouBrand.name) can't tell a password in ordinary text.",
            clipboard.isChangeMonitoringEnabled
                ? "History keeps the latest \(CoucouClipboardAccessService.maximumHistoryEntries) copies in memory and is cleared when \(CoucouBrand.name) quits."
                : "History is off: nothing is kept.",
        ]
    }

    private func rowButton(_ symbol: String, label: String, help: String? = nil,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10.5, weight: .medium))
                .foregroundColor(Color(hex: "#8E939C")).frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(help ?? label)
    }

    // MARK: Actions

    private func copyAgain(_ snapshot: CoucouClipboardSnapshot) {
        do {
            #if COUCOU_LAB
            try snapshot.recopy(to: SeedLab.pasteboard)
            #else
            try snapshot.recopy(to: .general)
            #endif
            SoundEngine.shared.play("pop")
            NotificationCenter.default.post(name: .coucouRiceCopied, object: nil)
            if clipboard.isChangeMonitoringEnabled { clipboard.enableChangeMonitoring() } // do not re-capture our own copy
            copiedID = snapshot.id
            refresh(force: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if copiedID == snapshot.id { copiedID = nil } }
        } catch {
            note = error.localizedDescription
        }
    }

    private func refresh(force: Bool) {
        guard state.mode == .expanded else { return }
        let count = clipboard.currentChangeCount
        guard force || count != lastChangeCount else { return }
        lastChangeCount = count
        note = nil
        if clipboard.isChangeMonitoringEnabled {
            do { _ = try clipboard.captureIfChanged() } catch let error as CoucouWorkspaceError {
                if error != .noSupportedClipboardContent { note = message(for: error) }
            } catch {}
        }
        do {
            current = try clipboard.currentSnapshot()
        } catch let error as CoucouWorkspaceError {
            current = nil
            if error != .noSupportedClipboardContent { note = message(for: error) }
        } catch {
            current = nil
        }
    }

    private func message(for error: CoucouWorkspaceError) -> String {
        if case .sensitiveClipboardTypeDetected = error { return "Skipped: the app that copied this marked it as private." }
        return error.localizedDescription
    }
}

// MARK: - Row

struct CoucouClipboardRow<Trailing: View>: View {
    let snapshot: CoucouClipboardSnapshot
    @ViewBuilder let trailing: () -> Trailing

    @State private var thumbnail: NSImage?

    private struct Summary { let symbol: String; let title: String; let detail: String }

    private var summary: Summary {
        let representations = snapshot.items.flatMap(\.representations)
        let extra = snapshot.items.count > 1 ? " · \(snapshot.items.count) items" : ""
        func string(_ r: CoucouClipboardRepresentation) -> String { String(data: r.data, encoding: .utf8) ?? "" }
        if let file = representations.first(where: { $0.kind == .fileReference }) {
            let name = URL(string: string(file))?.lastPathComponent ?? "File"
            return Summary(symbol: "doc", title: name, detail: "File" + extra)
        }
        if representations.contains(where: { $0.kind == .image }) {
            return Summary(symbol: "photo", title: "Image", detail: CoucouWorkspaceFormat.fileSize(Int64(snapshot.byteCount)) + extra)
        }
        if let link = representations.first(where: { $0.kind == .url }) {
            let text = string(link)
            let url = URL(string: text)
            let title = [url?.host, url.map { $0.path == "/" ? "" : $0.path }].compactMap { $0 }.joined()
            return Summary(symbol: "link", title: CoucouWorkspaceFormat.preview(title.isEmpty ? text : title, limit: 80), detail: "Link" + extra)
        }
        let text = representations.first(where: { $0.kind == .text }).map(string) ?? ""
        return Summary(symbol: "text.alignleft", title: CoucouWorkspaceFormat.preview(text, limit: 160), detail: "Text" + extra)
    }

    var body: some View {
        let summary = summary
        HStack(spacing: 8) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFill()
                        .frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: summary.symbol).font(.system(size: 12)).foregroundColor(Color(hex: "#8E939C"))
                        .frame(width: 28, height: 28)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(summary.title).font(.system(size: 11.5, weight: .medium)).foregroundColor(Color(hex: "#F5F6F8"))
                    .lineLimit(2).truncationMode(.tail)
                Text("\(summary.detail) · \(CoucouWorkspaceFormat.ago(snapshot.capturedAt))")
                    .font(.system(size: 9.5)).foregroundColor(Color(hex: "#6B7079")).lineLimit(1)
            }
            Spacer(minLength: 4)
            trailing()
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .frame(minHeight: 38)
        .background(CoucouWorkspaceStyle.rowBackground(RoundedRectangle(cornerRadius: 12)))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onDrag { snapshot.makeItemProviders().first ?? NSItemProvider() }
        .task(id: snapshot.id) {
            guard let data = snapshot.items.flatMap(\.representations).first(where: { $0.kind == .image })?.data else {
                thumbnail = nil; return
            }
            thumbnail = NSImage(data: data)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(summary.detail): \(summary.title)")
    }
}
#endif
