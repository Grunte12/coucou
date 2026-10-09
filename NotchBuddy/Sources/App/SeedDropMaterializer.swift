#if COUCOU_HUB
import AppKit
import UniformTypeIdentifiers

// MARK: - Drops that are not files
//
// Agent apps rarely hand over a file: a selection in Terminal, Claude or Cursor
// is text, a chat image is image data, a Mail or Photos attachment is a file
// promise. Seed turns each into a small file in its own folder, then stages it
// on the shelf like any other file. Originals are never touched; only Seed's
// folder is written, and files older than a week there are cleared.

enum SeedDropMaterializer {
    /// Pasteboard types the notch accepts in the Seed build, besides file URLs.
    static var extraTypes: [NSPasteboard.PasteboardType] {
        [.string, .URL, .png, .tiff] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    }

    static let keepFor: TimeInterval = 7 * 24 * 3600

    /// Seed Lab points this at its own output folder so it never writes to the user's.
    nonisolated(unsafe) static var folderOverride: URL?

    static var folder: URL {
        if let folderOverride { return folderOverride }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Seed/Drops", isDirectory: true)
    }

    /// Reads the drag right away (the pasteboard is only safe during the drop),
    /// writes text, links and images at once and starts receiving promised files.
    /// The returned closure waits for promises, then gives the files for the shelf.
    @MainActor
    static func begin(from pasteboard: NSPasteboard, now: Date = Date()) -> @Sendable () async -> [URL] {
        // 1. Real files: stage the originals themselves.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return { urls }
        }
        guard let dir = try? prepareFolder(now: now) else { return { [] } }
        // 2. File promises (Mail attachments, Photos, some chat apps).
        if let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver],
           !receivers.isEmpty {
            let collectors = receivers.map { receive($0, into: dir) }
            return {
                var out: [URL] = []
                for c in collectors { out += await c.wait() }
                return out
            }
        }
        // 3. Image data.
        if let image = NSImage(pasteboard: pasteboard), let png = pngData(image) {
            let url = unique(dir, "Image \(stamp(now))", "png")
            if (try? png.write(to: url)) != nil { return { [url] } }
        }
        // 4. A web link.
        if let link = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first, !link.isFileURL,
           let scheme = link.scheme, ["http", "https"].contains(scheme.lowercased()) {
            let url = unique(dir, safeName(link.host ?? "Link", fallback: "Link"), "webloc")
            let plist = ["URL": link.absoluteString]
            if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0),
               (try? data.write(to: url)) != nil { return { [url] } }
        }
        // 5. Text: a snippet named after its first line.
        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            let url = unique(dir, safeName(first, fallback: "Snippet \(stamp(now))"), "txt")
            if (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil { return { [url] } }
        }
        return { [] }
    }

    // MARK: Helpers (internal for tests)

    /// A short, Finder-safe name: no path separators or control characters, at most 40 characters.
    static func safeName(_ raw: String, fallback: String) -> String {
        let banned = CharacterSet(charactersIn: "/:\\\0").union(.controlCharacters)
        let cleaned = raw.unicodeScalars.map { banned.contains($0) ? " " : String($0) }.joined()
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let short = String(cleaned.prefix(40)).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return short.isEmpty ? fallback : short
    }

    static func unique(_ dir: URL, _ name: String, _ ext: String) -> URL {
        var url = dir.appendingPathComponent(name).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(name) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return url
    }

    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH.mm.ss"
        return f.string(from: date)
    }

    /// Creates the folder and clears files older than `keepFor`. Only this folder is touched.
    static func prepareFolder(now: Date) throws -> URL {
        let dir = folder
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for item in items {
            let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? now
            if now.timeIntervalSince(modified) > keepFor { try? fm.removeItem(at: item) }
        }
        return dir
    }

    private static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Starts receiving one promise now; waiting gives up after 15 s so a stalled sender never hangs.
    private static func receive(_ receiver: NSFilePromiseReceiver, into dir: URL) -> PromiseCollector {
        let collector = PromiseCollector(expected: max(1, receiver.fileNames.count))
        receiver.receivePromisedFiles(atDestination: dir, options: [:], operationQueue: OperationQueue()) { url, error in
            collector.add(error == nil ? url : nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { collector.finish() }
        return collector
    }
}

/// Gathers promised files across callbacks; `wait()` returns once all arrived or time ran out.
private final class PromiseCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    private var seen = 0
    private var finished = false
    private var waiter: CheckedContinuation<[URL], Never>?
    private let expected: Int

    init(expected: Int) { self.expected = expected }

    func add(_ url: URL?) {
        lock.lock()
        seen += 1
        if let url { urls.append(url) }
        let all = seen >= expected
        lock.unlock()
        if all { finish() }
    }

    func finish() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let result = urls, w = waiter
        waiter = nil
        lock.unlock()
        w?.resume(returning: result)
    }

    func wait() async -> [URL] {
        await withCheckedContinuation { c in
            lock.lock()
            if finished { let result = urls; lock.unlock(); c.resume(returning: result); return }
            waiter = c
            lock.unlock()
        }
    }
}
#endif
