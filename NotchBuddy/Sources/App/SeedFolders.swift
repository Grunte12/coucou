import Foundation

// MARK: - Pinned folders (model)
//
// Folders the user pins to browse from the notch and drag files out of, into
// agent apps. Read-only: Seed lists folders, it never moves, renames or deletes
// anything in them. Pins are plain paths (the app is not sandboxed).

struct SeedFolderEntry: Identifiable, Equatable, Sendable {
    let url: URL
    let isDirectory: Bool
    let modified: Date
    let size: Int64
    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

enum SeedFolderListing {
    static let limit = 120

    /// Newest first, hidden files and packages' insides left out, at most `limit`.
    static func entries(in dir: URL, limit: Int = limit) -> [SeedFolderEntry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentModificationDateKey, .fileSizeKey]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        let list = items.compactMap { url -> SeedFolderEntry? in
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            // A package (an .app or a bundle) is one item to drag, not a folder to open.
            let isDir = (v.isDirectory ?? false) && !(v.isPackage ?? false)
            return SeedFolderEntry(url: url, isDirectory: isDir,
                                   modified: v.contentModificationDate ?? .distantPast,
                                   size: Int64(v.fileSize ?? 0))
        }
        return Array(list.sorted { ($0.modified, $1.name) > ($1.modified, $0.name) }.prefix(limit))
    }
}

@MainActor
final class SeedFolderStore: ObservableObject {
    static let shared = SeedFolderStore()
    static let capacity = 8
    private static let key = "seed.folders.pins"

    @Published private(set) var pins: [URL]
    /// The pinned folder being browsed, and the subfolder path opened inside it.
    @Published var selected: URL?
    @Published var path: [URL] = []
    /// True while the Folders section is on screen: a dropped folder is pinned instead of shelved.
    var acceptsPins = false

    private let store: UserDefaults

    init(store: UserDefaults = .standard) {
        self.store = store
        pins = Self.decode(store.stringArray(forKey: Self.key))
        selected = pins.first
    }

    /// Existing directories only, no duplicates, at most `capacity`.
    static func decode(_ raw: [String]?, exists: (String) -> Bool = { p in
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: p, isDirectory: &dir) && dir.boolValue
    }) -> [URL] {
        var seen = Set<String>()
        return Array((raw ?? []).filter { exists($0) && seen.insert($0).inserted }
            .prefix(capacity)).map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Picks up pins written outside the app (e.g. by the user's agent with `defaults write`).
    func reload() {
        let fresh = Self.decode(store.stringArray(forKey: Self.key))
        guard fresh.map(\.path) != pins.map(\.path) else { return }
        pins = fresh
        if selected.map({ s in !fresh.contains { $0.path == s.path } }) ?? true { selected = fresh.first; path = [] }
    }

    /// The folder currently listed: the deepest opened subfolder, else the selected pin.
    var current: URL? { path.last ?? selected }

    @discardableResult
    func pin(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &dir), dir.boolValue else { return false }
        let clean = url.standardizedFileURL
        if !pins.contains(where: { $0.path == clean.path }) {
            guard pins.count < Self.capacity else { return false }
            pins.append(clean)
            save()
        }
        select(clean)
        return true
    }

    func unpin(_ url: URL) {
        pins.removeAll { $0.path == url.path }
        if selected?.path == url.path { selected = pins.first; path = [] }
        save()
    }

    func select(_ url: URL) {
        selected = url
        path = []
    }

    func open(_ folder: URL) { path.append(folder) }
    func back() { if !path.isEmpty { path.removeLast() } }

    private func save() { store.set(pins.map(\.path), forKey: Self.key) }
}
