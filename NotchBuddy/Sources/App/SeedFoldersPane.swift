#if COUCOU_HUB
import SwiftUI
import AppKit

// MARK: - Folders section
//
// Pinned folders, browsed from the notch. Every row drags straight into an
// agent app (or anywhere). A click never launches a file: hover actions add
// it to the shelf or reveal it in Finder; a folder opens in place.

struct SeedFoldersPane: View {
    @ObservedObject var state: AppState
    let onClose: () -> Void

    @ObservedObject private var store = SeedFolderStore.shared
    @State private var entries: [SeedFolderEntry] = []
    @State private var hoveredID: String?
    @State private var loading = false

    private static let gold = Color(hex: "#F5C542")

    var body: some View {
        VStack(alignment: .leading, spacing: CoucouWorkspaceStyle.sectionGap) {
            CoucouSectionHeader(title: "Folders",
                                subtitle: store.pins.isEmpty ? "" : "\(store.pins.count)",
                                onClose: onClose) {
                CoucouHeaderAction("Add") { addFolder() }
                    .disabled(store.pins.count >= SeedFolderStore.capacity)
                    .help(store.pins.count >= SeedFolderStore.capacity
                          ? "Up to \(SeedFolderStore.capacity) pinned folders."
                          : "Pin a folder. You can also drop one on the notch while this section is open.")
            }
            if store.pins.isEmpty {
                CoucouWorkspaceStyle.emptyNotice("No pinned folders",
                                                 "Pin a project folder to browse it here and drag files straight into your agents. Drop a folder on the notch, or use Add.",
                                                 symbol: "folder")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                pinsRow
                if !store.path.isEmpty { breadcrumb }
                listing
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .overlay(dropHint)
        .onAppear {
            store.acceptsPins = true
            store.reload()
            reload()
        }
        .onDisappear { store.acceptsPins = false }
        .onChange(of: store.current) { _, _ in reload() }
    }

    // MARK: Pins

    private var pinsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CoucouWorkspaceStyle.gap) {
                ForEach(store.pins, id: \.path) { pin in
                    let on = store.selected?.path == pin.path
                    Button {
                        guard !on || !store.path.isEmpty else { return }
                        SoundEngine.shared.play("tick")
                        SeedReaction.notice(dx: 1, dy: -0.2)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { store.select(pin) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: on ? "folder.fill" : "folder").font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(on ? Self.gold : Color(hex: "#8E939C"))
                            Text(pin.lastPathComponent).font(.system(size: 11, weight: .medium))
                                .foregroundColor(on ? Color(hex: "#F5F6F8") : Color(hex: "#8E939C"))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(Capsule().fill(on ? Color(hex: "#1C1A12") : Color(hex: "#0E0F11")))
                        .overlay(Capsule().strokeBorder(on ? Self.gold.opacity(0.5) : Color.white.opacity(0.05), lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(pin.path)
                    .contextMenu {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([pin]) }
                        Button("Unpin") {
                            SoundEngine.shared.play("close")
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { store.unpin(pin) }
                        }
                    }
                    .accessibilityLabel("\(pin.lastPathComponent) folder")
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityAction(named: "Unpin") { store.unpin(pin) }
                }
            }
            // Room for the chips' borders, or the scroll edge clips their round ends.
            .padding(.horizontal, 1).padding(.vertical, 1)
        }
        .scrollIndicators(.never)
        .frame(height: 28)
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Button {
                SoundEngine.shared.play("tick")
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { store.back() }
            } label: {
                Label("Back", systemImage: "chevron.left").font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "#C5C8CD"))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            Text(store.path.map(\.lastPathComponent).joined(separator: " / "))
                .font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
                .lineLimit(1).truncationMode(.head)
        }
    }

    // MARK: Listing

    @ViewBuilder private var listing: some View {
        if entries.isEmpty {
            Text(loading ? "Reading…" : "This folder is empty.")
                .font(.system(size: 11)).foregroundColor(Color(hex: "#6B7079"))
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(entries) { row($0) }
                    if entries.count >= SeedFolderListing.limit {
                        Text("Showing the \(SeedFolderListing.limit) most recent items.")
                            .font(.system(size: 10)).foregroundColor(Color(hex: "#6B7079"))
                    }
                }
                .padding(.vertical, 2)
                .padding(.bottom, 10)
            }
            .mask(CoucouWorkspaceStyle.scrollFade)
        }
    }

    private func row(_ entry: SeedFolderEntry) -> some View {
        let showActions = hoveredID == entry.id
        return HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                .resizable().frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 11.5, weight: .medium)).foregroundColor(Color(hex: "#F5F6F8"))
                    .lineLimit(1).truncationMode(.middle)
                Text(detail(entry))
                    .font(.system(size: 9.5).monospacedDigit()).foregroundColor(Color(hex: "#6B7079")).lineLimit(1)
            }
            Spacer(minLength: 4)
            HStack(spacing: 2) {
                if !entry.isDirectory {
                    rowButton("tray.and.arrow.down", label: "Add \(entry.name) to the shelf") {
                        SoundEngine.shared.play("pop")
                        CoucouHubIntegration.shared.stageFiles([entry.url])
                    }
                }
                rowButton("magnifyingglass", label: "Reveal \(entry.name) in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                }
            }
            .opacity(showActions ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: showActions)
            if entry.isDirectory {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color(hex: "#6B7079"))
            }
        }
        .padding(.leading, 12).padding(.trailing, entry.isDirectory ? 12 : 6).frame(height: 38)
        .background(CoucouWorkspaceStyle.rowBackground())
        .overlay(Capsule().strokeBorder(Self.gold.opacity(showActions ? 0.18 : 0), lineWidth: 1))
        .contentShape(Capsule())
        .onHover { inside in hoveredID = inside ? entry.id : (hoveredID == entry.id ? nil : hoveredID) }
        .onTapGesture {
            guard entry.isDirectory else { return }
            SoundEngine.shared.play("tick")
            SeedReaction.notice(dx: 1, dy: 0.4)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { store.open(entry.url) }
        }
        .onDrag { NSItemProvider(contentsOf: entry.url) ?? NSItemProvider(object: entry.url as NSURL) }
        .help(entry.url.path)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(entry.isDirectory ? "\(entry.name), folder" : entry.name)
        .accessibilityAddTraits(entry.isDirectory ? .isButton : [])
    }

    private func detail(_ entry: SeedFolderEntry) -> String {
        let when = CoucouWorkspaceFormat.ago(entry.modified)
        return entry.isDirectory ? "Folder · \(when)" : "\(CoucouWorkspaceFormat.fileSize(entry.size)) · \(when)"
    }

    private func rowButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .medium)).foregroundColor(Color(hex: "#8E939C"))
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    @ViewBuilder private var dropHint: some View {
        if state.fileDragOver {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Self.gold, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.55)))
                .overlay(Text("Drop a folder to pin it · files go to the shelf")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(Color(hex: "#F5F6F8")))
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    // MARK: Actions

    /// Lists off the main thread; a large folder never stalls the notch.
    private func reload() {
        guard let dir = store.current else { entries = []; return }
        loading = true
        Task.detached(priority: .userInitiated) {
            let list = SeedFolderListing.entries(in: dir)
            await MainActor.run {
                guard store.current == dir else { return }
                entries = list
                loading = false
            }
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Pin"
        panel.message = "Pin a folder to browse it from the notch."
        // The notch sits above normal windows; keep the picker above it.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if store.pin(url) {
            SoundEngine.shared.play("pop")
            SeedReaction.notice(dx: 1, dy: -0.2)
        }
    }
}
#endif
