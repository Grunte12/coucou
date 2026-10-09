import Foundation
import AppKit

@main
struct SeedFoldersAndDropsTests {
    static var failures = 0
    static func check(_ ok: Bool, _ name: String) {
        if !ok { failures += 1; print("FAIL: \(name)") }
    }

    @MainActor static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("seed-folders-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root.appendingPathComponent("Sub"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Tool.app/Contents"), withIntermediateDirectories: true)
        let now = Date()
        for (i, name) in ["new.txt", "old.txt", ".hidden"].enumerated() {
            let url = root.appendingPathComponent(name)
            try "x".write(to: url, atomically: true, encoding: .utf8)
            try fm.setAttributes([.modificationDate: now.addingTimeInterval(Double(-i) * 3600)], ofItemAtPath: url.path)
        }
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-7200 * 3)], ofItemAtPath: root.appendingPathComponent("Sub").path)

        // Listing: newest first, hidden files skipped, a package is one item, capped.
        let list = SeedFolderListing.entries(in: root)
        check(!list.contains { $0.name == ".hidden" }, "hidden files are left out")
        check(list.first?.name == "new.txt", "newest first")
        check(list.firstIndex { $0.name == "old.txt" }! < list.firstIndex { $0.name == "Sub" }!, "older items come later")
        check(list.first { $0.name == "Sub" }?.isDirectory == true, "a folder opens in place")
        check(list.first { $0.name == "Tool.app" }?.isDirectory == false, "an .app is one draggable item, not a folder")
        check(SeedFolderListing.entries(in: root, limit: 2).count == 2, "the listing is capped")
        check(SeedFolderListing.entries(in: root.appendingPathComponent("missing")).isEmpty, "a missing folder lists nothing")

        // Pins: existing directories only, no duplicates, capped, persisted.
        let decoded = SeedFolderStore.decode([root.path, root.path, "/nope", root.appendingPathComponent("new.txt").path])
        check(decoded.map(\.path) == [root.path], "pins keep existing folders once")
        let suite = "seed.folders.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SeedFolderStore(store: defaults)
        check(store.pins.isEmpty && store.current == nil, "a fresh store has no pins")
        check(!store.pin(root.appendingPathComponent("new.txt")), "a file cannot be pinned")
        check(store.pin(root) && store.selected?.path == root.path, "pinning selects the folder")
        check(store.pin(root) && store.pins.count == 1, "pinning twice keeps one pin")
        store.open(root.appendingPathComponent("Sub"))
        check(store.current?.lastPathComponent == "Sub", "opening a subfolder lists it")
        store.back()
        check(store.current?.path == root.path, "back returns to the pin")
        check(SeedFolderStore(store: defaults).pins.map(\.path) == [root.path], "pins survive a relaunch")
        store.unpin(root)
        check(store.pins.isEmpty && store.selected == nil, "unpinning the selected folder clears the selection")

        // Drops: Finder-safe, short names; no clobbering.
        check(SeedDropMaterializer.safeName("a/b:c\\d", fallback: "x") == "a b c d", "path separators are replaced")
        check(SeedDropMaterializer.safeName("   ", fallback: "Snippet") == "Snippet", "blank names fall back")
        check(SeedDropMaterializer.safeName(String(repeating: "word ", count: 20), fallback: "x").count <= 40, "names stay short")
        check(!SeedDropMaterializer.safeName("ends with dots....", fallback: "x").hasSuffix("."), "no trailing dots before the extension")
        check(SeedDropMaterializer.safeName("line\u{0007}bell", fallback: "x") == "line bell", "control characters are removed")
        let first = SeedDropMaterializer.unique(root, "new", "txt")
        check(first.lastPathComponent == "new 2.txt", "an existing name gets a number")

        // Text dropped from an agent app becomes a snippet file in Seed's folder.
        SeedDropMaterializer.folderOverride = root.appendingPathComponent("drops")
        let pb = NSPasteboard(name: NSPasteboard.Name("seed.tests.\(UUID().uuidString)"))
        pb.clearContents()
        pb.setString("let seed = Seed()\nprint(seed)", forType: .string)
        let urls = await SeedDropMaterializer.begin(from: pb)()
        check(urls.count == 1 && urls[0].lastPathComponent == "let seed = Seed().txt", "text becomes a snippet named after its first line")
        check((try? String(contentsOf: urls[0], encoding: .utf8)) == "let seed = Seed()\nprint(seed)", "the snippet keeps the full text")
        pb.releaseGlobally()

        if failures == 0 { print("SeedFoldersAndDropsTests: all passed") } else { exit(1) }
    }
}
