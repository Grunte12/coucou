import AppKit
import Foundation

@MainActor
@main
enum CoucouWorkspaceStoreTests {
    private static var failures = 0
    private static var clipboardTestsSkipped = false

    @MainActor
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("coucou-workspace-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try testFileShelf(root: root)
        try testClipboardCapture(root: root)

        if failures == 0 {
            if clipboardTestsSkipped {
                print("Coucou workspace store: file shelf tests passed; clipboard tests skipped (named pasteboard service unavailable)")
            } else {
                print("Coucou workspace store: all focused tests passed")
            }
        } else {
            print("Coucou workspace store: \(failures) test(s) failed")
            exit(1)
        }
    }

    private static func testFileShelf(root: URL) throws {
        let store = CoucouWorkspaceStore()
        let original = root.appendingPathComponent("reference.txt")
        try Data("keep this original".utf8).write(to: original)

        let first = try store.addFile(at: original)
        check("first file is added", first.wasAdded)
        check("file reference is canonical", first.file.url == original.resolvingSymlinksInPath().standardizedFileURL)

        let alias = root.appendingPathComponent("alias.txt")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original)
        let duplicate = try store.addFile(at: alias)
        check("symlink alias is de-duplicated", !duplicate.wasAdded)
        check("duplicate points at existing shelf row", duplicate.file.id == first.file.id)
        check("duplicate leaves one shelf entry", store.files.count == 1)

        var localhostComponents = URLComponents(url: original, resolvingAgainstBaseURL: false)!
        localhostComponents.host = "localhost"
        let localhostAlias = try store.addFile(at: localhostComponents.url!)
        check("localhost file URL is normalized to its local path", !localhostAlias.wasAdded && localhostAlias.file.id == first.file.id)

        var remoteComponents = URLComponents(url: original, resolvingAgainstBaseURL: false)!
        remoteComponents.host = "remote.example.invalid"
        do {
            _ = try store.addFile(at: remoteComponents.url!)
            check("remote file URL authority is rejected", false)
        } catch let error as CoucouWorkspaceError {
            check("remote file URL authority is rejected", error == .fileIsNotOnLocalVolume)
        }

        do {
            _ = try store.addFile(at: root.appendingPathComponent("missing.txt"))
            check("missing file is rejected", false)
        } catch let error as CoucouWorkspaceError {
            check("missing file is rejected", error == .fileMissing)
            check("file rejection is observable", store.lastError == .fileMissing)
        }

        do {
            _ = try store.addFile(at: root)
            check("directory is rejected", false)
        } catch let error as CoucouWorkspaceError {
            check("directory is rejected", error == .notRegularFile)
        }

        do {
            _ = try store.addFile(at: URL(string: "https://example.com/file.txt")!)
            check("non-file URL is rejected", false)
        } catch let error as CoucouWorkspaceError {
            check("non-file URL is rejected", error == .invalidFileURL)
        }

        store.clear()
        check("clear removes shelf metadata", store.files.isEmpty)
        check("clear preserves original bytes", try Data(contentsOf: original) == Data("keep this original".utf8))
        check("successful clear resets stale error", store.lastError == nil)

        let atomicStore = CoucouWorkspaceStore()
        let validForBatch = root.appendingPathComponent("batch-valid.txt")
        try Data("valid".utf8).write(to: validForBatch)
        do {
            _ = try atomicStore.addFiles(at: [validForBatch, root.appendingPathComponent("batch-missing.txt")])
            check("batch validates before adding anything", false)
        } catch let error as CoucouWorkspaceError {
            check("batch validates before adding anything", error == .fileMissing && atomicStore.files.isEmpty)
            check("batch failure is observable", atomicStore.lastError == .fileMissing)
        }

        for index in 0..<CoucouWorkspaceStore.maximumFileCount {
            let file = root.appendingPathComponent("bounded-\(index).txt")
            try Data([UInt8(index % 251)]).write(to: file)
            _ = try store.addFile(at: file)
        }
        check("shelf accepts its documented cap", store.files.count == CoucouWorkspaceStore.maximumFileCount)

        let extraFile = root.appendingPathComponent("over-cap.txt")
        try Data("overflow".utf8).write(to: extraFile)
        do {
            _ = try store.addFile(at: extraFile)
            check("shelf rejects overflow", false)
        } catch let error as CoucouWorkspaceError {
            check("shelf rejects overflow", error == .shelfFull(limit: CoucouWorkspaceStore.maximumFileCount))
        }

        let removedID = store.files[0].id
        check("remove reports a removed row", store.removeFile(id: removedID))
        check("remove preserves the referenced original", FileManager.default.fileExists(atPath: store.files[0].url.path))
        check("remove is metadata-only", FileManager.default.fileExists(atPath: root.appendingPathComponent("bounded-0.txt").path))
    }

    private static func testClipboardCapture(root: URL) throws {
        // All pasteboard interaction in tests uses private named boards. Never
        // use NSPasteboard.general here.
        let sourceBoard = NSPasteboard(name: NSPasteboard.Name("CoucouWorkspaceTests.Source.\(UUID().uuidString)"))
        let destinationBoard = NSPasteboard(name: NSPasteboard.Name("CoucouWorkspaceTests.Destination.\(UUID().uuidString)"))
        defer {
            sourceBoard.releaseGlobally()
            destinationBoard.releaseGlobally()
        }
        guard !sourceBoard.name.rawValue.isEmpty && !destinationBoard.name.rawValue.isEmpty else {
            clipboardTestsSkipped = true
            print("  ↷ clipboard tests skipped: this process cannot create named NSPasteboard instances")
            return
        }
        let service = CoucouClipboardAccessService(pasteboard: sourceBoard)

        check("change monitoring starts disabled", !service.isChangeMonitoringEnabled)
        sourceBoard.clearContents()
        sourceBoard.setString("test text", forType: .string)
        do {
            _ = try service.captureIfChanged()
            check("change polling is blocked while disabled", false)
        } catch let error as CoucouWorkspaceError {
            check("change polling is blocked while disabled", error == .clipboardMonitoringDisabled)
        }
        check("disabled poll did not capture history", service.history.isEmpty)

        // Manual capture is a separate explicit authorization and is allowed
        // while monitoring is off.
        let manual = try service.captureManually()
        check("manual capture reads supported text while monitoring is off", manual.items.count == 1)
        check("manual capture is session history", service.history.last?.id == manual.id)
        check("manual capture reports bounded byte size", manual.byteCount == Data("test text".utf8).count)

        let providers = manual.makeItemProviders()
        check("item provider preserves plain text type", providers.first?.registeredTypeIdentifiers.contains(NSPasteboard.PasteboardType.string.rawValue) == true)
        try manual.recopy(to: destinationBoard)
        check("explicit recopy preserves plain text", destinationBoard.string(forType: .string) == "test text")

        // Capture every supported representation while proving HTML and other
        // custom types are not retained by this allow-list.
        let referenceFile = root.appendingPathComponent("clipboard-file.txt")
        try Data("original".utf8).write(to: referenceFile)
        sourceBoard.clearContents()
        let mixedItem = NSPasteboardItem()
        mixedItem.setString("visible text", forType: .string)
        mixedItem.setString("https://example.com/path", forType: .URL)
        mixedItem.setString(referenceFile.absoluteString, forType: .fileURL)
        mixedItem.setData(Data([0x89, 0x50, 0x4e, 0x47]), forType: .png)
        mixedItem.setString("<script>not copied</script>", forType: NSPasteboard.PasteboardType(rawValue: "public.html"))
        check("mixed test item writes", sourceBoard.writeObjects([mixedItem]))
        let mixed = try service.captureManually()
        let capturedKinds = Set(mixed.items.flatMap(\.representations).map(\.kind))
        check("capture supports text, URLs, images, and local file references", capturedKinds == Set([.text, .url, .image, .fileReference]))
        check("unsupported HTML type is not captured", mixed.items.flatMap(\.representations).allSatisfy { $0.typeIdentifier != "public.html" })
        let mixedProviderTypes = Set(mixed.makeItemProviders().flatMap(\.registeredTypeIdentifiers))
        check("drag providers preserve allow-listed native types", mixedProviderTypes.contains(NSPasteboard.PasteboardType.fileURL.rawValue) && mixedProviderTypes.contains(NSPasteboard.PasteboardType.png.rawValue))

        sourceBoard.clearContents()
        sourceBoard.setString("excluded", forType: .string)
        do {
            _ = try service.captureManually(excludingTypeIdentifiers: [NSPasteboard.PasteboardType.string.rawValue])
            check("caller exclusion prevents text capture", false)
        } catch let error as CoucouWorkspaceError {
            check("caller exclusion prevents text capture", error == .noSupportedClipboardContent)
        }

        for marker in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType", "com.1password.1password"] {
            sourceBoard.clearContents()
            let markedItem = NSPasteboardItem()
            markedItem.setString("do not capture", forType: .string)
            markedItem.setString("marker", forType: NSPasteboard.PasteboardType(rawValue: marker))
            check("marker test item writes (\(marker))", sourceBoard.writeObjects([markedItem]))
            do {
                _ = try service.captureManually()
                check("sensitive marker \(marker) rejects capture", false)
            } catch let error as CoucouWorkspaceError {
                check("sensitive marker \(marker) rejects capture", error == .sensitiveClipboardTypeDetected)
            }
        }

        sourceBoard.clearContents()
        sourceBoard.setString(String(repeating: "x", count: CoucouClipboardAccessService.maximumCaptureBytes + 1), forType: .string)
        do {
            _ = try service.captureManually()
            check("oversized payload is rejected", false)
        } catch let error as CoucouWorkspaceError {
            check("oversized payload is rejected", error == .clipboardPayloadTooLarge(limitBytes: CoucouClipboardAccessService.maximumCaptureBytes))
        }

        sourceBoard.clearContents()
        sourceBoard.setString("baseline", forType: .string)
        service.enableChangeMonitoring()
        check("explicit enable turns monitoring on", service.isChangeMonitoringEnabled)
        do {
            let noChange = try service.captureIfChanged()
            check("unchanged count does not read/capture content", noChange == nil)
        }
        sourceBoard.clearContents()
        sourceBoard.setString("changed", forType: .string)
        let changed = try service.captureIfChanged()
        check("enabled change polling captures a new pasteboard change", changed?.items.first?.representations.first?.data == Data("changed".utf8))
        check("same change is captured once", try service.captureIfChanged() == nil)
        service.disableChangeMonitoring()
        check("explicit disable turns monitoring off", !service.isChangeMonitoringEnabled)
        do {
            _ = try service.captureIfChanged()
            check("disabled polling stays blocked after opt-out", false)
        } catch let error as CoucouWorkspaceError {
            check("disabled polling stays blocked after opt-out", error == .clipboardMonitoringDisabled)
        }

        for index in 0...CoucouClipboardAccessService.maximumHistoryEntries {
            sourceBoard.clearContents()
            sourceBoard.setString("history-\(index)", forType: .string)
            _ = try service.captureManually()
        }
        check("history count is bounded", service.history.count == CoucouClipboardAccessService.maximumHistoryEntries)
        check("history byte count is bounded", service.history.reduce(0) { $0 + $1.byteCount } <= CoucouClipboardAccessService.maximumHistoryBytes)
        let remembered = service.history.last
        if let remembered {
            check("snapshot remove affects history", service.removeSnapshot(id: remembered.id))
        }
        service.clearHistory()
        check("history clear releases session snapshots", service.history.isEmpty)
        check("history clear does not clear system clipboard", sourceBoard.string(forType: .string) == "history-\(CoucouClipboardAccessService.maximumHistoryEntries)")
    }

    private static func check(_ label: String, _ passed: @autoclosure () throws -> Bool) {
        do {
            if try passed() {
                print("  ✓ \(label)")
            } else {
                print("  ✗ \(label)")
                failures += 1
            }
        } catch {
            print("  ✗ \(label) threw \(error)")
            failures += 1
        }
    }
}
