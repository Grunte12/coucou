#if COUCOU_HUB
import SwiftUI
import AppKit

// MARK: - File shelf
//
// A session-only list of references. Nothing here moves, copies, overwrites or
// deletes an original file, and nothing is sent anywhere.

struct CoucouShelfPane: View {
    @ObservedObject var integration: CoucouHubIntegration
    @ObservedObject var workspace: CoucouWorkspaceStore
    @ObservedObject var state: AppState
    let onClose: () -> Void

    @State private var missing: Set<String> = []
    @State private var hoveredID: String?
    @State private var sizes: [String: Int64] = [:]

    init(integration: CoucouHubIntegration, state: AppState, onClose: @escaping () -> Void) {
        self.integration = integration
        self.workspace = integration.workspace
        self.state = state
        self.onClose = onClose
    }

    private var files: [CoucouWorkspaceFile] { workspace.files }

    var body: some View {
        VStack(alignment: .leading, spacing: CoucouWorkspaceStyle.sectionGap) {
            CoucouSectionHeader(title: "Shelf",
                                subtitle: files.isEmpty ? "" : "\(files.count)",
                                onClose: onClose) {
                if !files.isEmpty {
                    CoucouHeaderAction("Clear") {
                        SoundEngine.shared.play("tick")
                        SeedReaction.notice(dx: 1, dy: -0.3)
                        workspace.clear()
                    }
                    .help("Remove every entry from the shelf. The original files stay where they are.")
                }
            }
            banner
            Group {
                if files.isEmpty {
                    CoucouWorkspaceStyle.emptyNotice("Nothing parked",
                                                     "Drop files on the notch to keep them handy. Originals stay where they are, and nothing is sent.",
                                                     symbol: "tray")
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 6) {
                            ForEach(files) { file in row(file) }
                        }
                        .padding(.vertical, 2)
                        .padding(.bottom, 10)
                    }
                    .mask(CoucouWorkspaceStyle.scrollFade)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .overlay(dropHint)
        .onAppear(perform: refreshFileInfo)
        .onChange(of: files) { _, _ in refreshFileInfo() }
    }

    // MARK: Pieces

    @ViewBuilder private var banner: some View {
        if let error = integration.fileShelfError {
            let isFull: Bool = { if case .shelfFull = workspace.lastError { return true }; return false }()
            CoucouWorkspaceStyle.banner(error, hex: isFull ? "#F5A524" : "#F4505E")
        }
    }

    @ViewBuilder private var dropHint: some View {
        if state.fileDragOver {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(hex: "#F5A524"), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.55)))
                .overlay(Text("Release to park").font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "#F5F6F8")))
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    private func row(_ file: CoucouWorkspaceFile) -> some View {
        let gone = missing.contains(file.id)
        // Actions stay out of the way until the row is hovered (always shown for a missing file).
        let showActions = gone || hoveredID == file.id
        return HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                .resizable().frame(width: 20, height: 20)
                .opacity(gone ? 0.4 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.displayName)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(Color(hex: gone ? "#6B7079" : "#F5F6F8"))
                    .lineLimit(1).truncationMode(.middle)
                Text(detail(file, gone: gone))
                    .font(.system(size: 9.5)).foregroundColor(Color(hex: gone ? "#F5A524" : "#6B7079")).lineLimit(1)
            }
            Spacer(minLength: 4)
            HStack(spacing: 2) {
                if !gone {
                    rowButton("folder", label: "Reveal \(file.displayName) in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([file.url])
                    }
                }
                rowButton("xmark", label: "Remove \(file.displayName) from the shelf",
                          help: "Remove from shelf. The original file stays where it is.") {
                    SoundEngine.shared.play("tick")
                    SeedReaction.notice(dx: 1, dy: 0.4)
                    workspace.removeFile(id: file.id)
                }
            }
            .opacity(showActions ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: showActions)
        }
        .padding(.leading, 12).padding(.trailing, 6).frame(height: 38)
        .onHover { inside in hoveredID = inside ? file.id : (hoveredID == file.id ? nil : hoveredID) }
        .help("\(file.url.path) · added \(CoucouWorkspaceFormat.ago(file.addedAt))")
        .background(CoucouWorkspaceStyle.rowBackground())
        .contentShape(Capsule())
        .onDrag {
            // A missing file offers nothing to drop. The original is shared in place.
            gone ? NSItemProvider()
                 : (NSItemProvider(contentsOf: file.url) ?? NSItemProvider(object: file.url as NSURL))
        }
        .accessibilityElement(children: .contain)
    }

    private func detail(_ file: CoucouWorkspaceFile, gone: Bool) -> String {
        if gone { return "Missing · moved or deleted" }
        return sizes[file.id].map(CoucouWorkspaceFormat.fileSize) ?? "File"
    }

    private func rowButton(_ symbol: String, label: String, help: String? = nil,
                           disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(Color(hex: "#8E939C"))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled).opacity(disabled ? 0.35 : 1)
        .accessibilityLabel(label)
        .help(help ?? label)
    }

    /// Checked when the pane appears or the list changes, not on every redraw.
    private func refreshFileInfo() {
        var gone = Set<String>()
        var fileSizes: [String: Int64] = [:]
        for file in files {
            guard FileManager.default.fileExists(atPath: file.url.path) else { gone.insert(file.id); continue }
            if let size = try? file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize { fileSizes[file.id] = Int64(size) }
        }
        missing = gone
        sizes = fileSizes
    }
}
#endif
