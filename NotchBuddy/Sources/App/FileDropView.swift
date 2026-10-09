import AppKit
import SwiftUI

// MARK: - NSView drag destination
// Wired at the AppKit level in IslandWindowController (not via SwiftUI NSViewRepresentable)
// so it never interferes with SwiftUI hit-testing.

final class FileDropNSView: NSView {
    var onDragEntered: ((CGPoint) -> Void)?
    var onDragUpdated: ((CGPoint) -> Void)?
    var onDragExited:  (() -> Void)?
    var onFilesDropped: (([URL]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        #if COUCOU_HUB
        // Seed also takes text, links, images and file promises from agent apps.
        registerForDraggedTypes([.fileURL] + SeedDropMaterializer.extraTypes)
        #else
        registerForDraggedTypes([.fileURL])
        #endif
    }
    required init?(coder: NSCoder) { fatalError() }

    // Pass all mouse events through — drag-drop uses NSDraggingDestination, not hitTest
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEntered?(sender.draggingLocation)
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragUpdated?(sender.draggingLocation)
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { onDragExited?() }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        #if COUCOU_HUB
        let pending = MainActor.assumeIsolated { SeedDropMaterializer.begin(from: sender.draggingPasteboard) }
        let deliver = onFilesDropped
        Task { @MainActor in
            let urls = await pending()
            if urls.isEmpty {
                AppState.shared.fileDragOver = false
                NotificationCenter.default.post(name: .coucouShelfRejected, object: nil)
            } else {
                deliver?(urls)
            }
        }
        return true
        #else
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else { return false }
        onFilesDropped?(urls)
        return true
        #endif
    }
}

// MARK: - File drop handler

enum FileDropHandler {
    @MainActor
    static func handle(urls: [URL], state: AppState) async {
        #if COUCOU_HUB
        // Folders section open: a dropped folder is pinned, files still go to the shelf.
        var urls = urls
        if SeedFolderStore.shared.acceptsPins {
            let folders = urls.filter { url in
                var dir: ObjCBool = false
                let isDir = FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
                return isDir && !NSWorkspace.shared.isFilePackage(atPath: url.path)
            }
            folders.forEach { SeedFolderStore.shared.pin($0) }
            urls.removeAll { u in folders.contains(u) }
            if !folders.isEmpty { SoundEngine.shared.play("pop") }
        }
        if !urls.isEmpty { CoucouHubIntegration.shared.stageFiles(urls) }
        state.fileDragOver = false
        // The Shelf section shows the parked files and any rejection.
        // Do not use the upstream simulated upload animation for local staging.
        return
        #else
        guard let url = urls.first else { return }
        let name = url.lastPathComponent

        // Start animation immediately — do NOT block on file copy.
        // Use original URL first; swap to inbox copy once background copy finishes.
        state.droppedFile = DroppedFile(url: url, name: name)
        state.uploadProgress = 0
        state.fileDragOver = false
        state.promptContext = .file(name: name, fileURL: url)

        let dur = 2.4
        UploadSequenceEngine.shared.performDrop(uploadDuration: dur)

        // Copy to inbox in background — update state when done
        let inbox = HookServer.supportDir.appendingPathComponent("inbox")
        Task.detached {
            try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            let dest = inbox.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.copyItem(at: url, to: dest)) != nil {
                await MainActor.run {
                    state.droppedFile = DroppedFile(url: dest, name: name)
                    state.promptContext = .file(name: name, fileURL: dest)
                }
            }
        }

        // Drop feedback
        NotificationCenter.default.post(name: .botGulp, object: nil)
        SoundEngine.shared.play("approve")
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        NotificationCenter.default.post(name: .botMorphTo, object: CGFloat(0))

        state.uploadDuration = dur
        state.uploadStartTime = Date()
        state.view = .uploading  // canvas stays active: uploadActive covers .uploading

        // Canvas timeline from drop:
        //   T_DROP → T_PROG_START : ≈1.30s  gulp + shrink + bar reveal
        //   T_PROG_START → progEnd: dur      progress bar fills
        //   progEnd → growEnd     : 0.70s    Mochi grows back to choose position
        let preProgress = USC.T_PROG_START - USC.T_DROP  // ≈1.30s

        // Tick sounds — delayed to sync with canvas progress start
        Task { @MainActor in
            var lastTens = 0
            let progStart = Date().addingTimeInterval(preProgress)
            while lastTens < 9 {
                try? await Task.sleep(nanoseconds: 80_000_000)
                let approxP = min(1.0, max(0, Date().timeIntervalSince(progStart) / dur))
                let tens = Int(approxP * 10)
                if tens > lastTens {
                    SoundEngine.shared.play("tick")
                    lastTens = tens
                }
            }
        }

        // Wait for canvas progress to complete (gulp/shrink phase + upload duration)
        try? await Task.sleep(nanoseconds: UInt64((preProgress + dur) * 1_000_000_000))

        // Canvas shows checkmark at this point
        SoundEngine.shared.play("approve")
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)

        // Wait for grow-back animation + choose overlay settle
        try? await Task.sleep(nanoseconds: UInt64(1_000_000_000))

        // Clean up upload state
        state.uploadProgress = 0
        state.uploadStartTime = nil

        // Switch to choose — canvas stays active (uploadActive covers .choose).
        // Engine deactivates when user clicks a canvas choose button or navigates away.
        state.view = .choose
        #endif
    }
}
