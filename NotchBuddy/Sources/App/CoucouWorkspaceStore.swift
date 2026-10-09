import AppKit
import Combine
import Foundation

// MARK: - Session-only file shelf

/// A reference to a local file. The shelf keeps only this metadata; it never
/// takes ownership of, copies, moves, uploads, or deletes the referenced file.
struct CoucouWorkspaceFile: Identifiable, Equatable, Sendable {
    /// The standardized, symlink-resolved local path used for de-duplication.
    let id: String
    let url: URL
    let displayName: String
    let addedAt: Date
}

enum CoucouWorkspaceFileAddResult: Equatable, Sendable {
    case added(CoucouWorkspaceFile)
    case alreadyPresent(CoucouWorkspaceFile)

    var file: CoucouWorkspaceFile {
        switch self {
        case .added(let file), .alreadyPresent(let file): file
        }
    }

    var wasAdded: Bool {
        if case .added = self { return true }
        return false
    }
}

enum CoucouWorkspaceError: Error, Equatable, LocalizedError {
    case invalidFileURL
    case fileMissing
    case notRegularFile
    case fileIsNotOnLocalVolume
    case shelfFull(limit: Int)
    case clipboardMonitoringDisabled
    case noSupportedClipboardContent
    case sensitiveClipboardTypeDetected
    case clipboardPayloadTooLarge(limitBytes: Int)
    case tooManyClipboardItems(limit: Int)
    case clipboardWriteFailed

    var errorDescription: String? {
        switch self {
        case .invalidFileURL:
            return "Choose a local file URL."
        case .fileMissing:
            return "The file no longer exists."
        case .notRegularFile:
            return "Only existing regular files can be added."
        case .fileIsNotOnLocalVolume:
            return "Only files on a local volume can be added."
        case .shelfFull(let limit):
            return "The session shelf is full (maximum \(limit) files)."
        case .clipboardMonitoringDisabled:
            return "Clipboard change monitoring is not enabled."
        case .noSupportedClipboardContent:
            return "The clipboard contains no supported content."
        case .sensitiveClipboardTypeDetected:
            return "Clipboard capture was skipped because a concealed, transient, generated, or password-manager marker was present."
        case .clipboardPayloadTooLarge(let limitBytes):
            return "Clipboard content exceeds the \(limitBytes)-byte capture limit."
        case .tooManyClipboardItems(let limit):
            return "Clipboard content exceeds the \(limit)-item capture limit."
        case .clipboardWriteFailed:
            return "The captured clipboard content could not be written to the destination."
        }
    }
}

/// In-memory list of references to validated local files. It is deliberately
/// bounded to 50 entries and is not persisted between app launches.
@MainActor
final class CoucouWorkspaceStore: ObservableObject {
    static let maximumFileCount = 50

    @Published private(set) var files: [CoucouWorkspaceFile] = []
    @Published private(set) var lastError: CoucouWorkspaceError?

    @discardableResult
    func addFile(at inputURL: URL) throws -> CoucouWorkspaceFileAddResult {
        try addFiles(at: [inputURL])[0]
    }

    /// Validates a whole drop before mutating the shelf, then adds references
    /// atomically. Duplicate URLs in the batch or shelf are reported as
    /// `.alreadyPresent`; any invalid URL or capacity error leaves the shelf
    /// unchanged and is exposed in `lastError` as well as thrown to the caller.
    @discardableResult
    func addFiles(at inputURLs: [URL]) throws -> [CoucouWorkspaceFileAddResult] {
        let canonicalURLs: [URL]
        do {
            canonicalURLs = try inputURLs.map(Self.validatedCanonicalLocalFileURL)
        } catch let error as CoucouWorkspaceError {
            lastError = error
            throw error
        } catch {
            lastError = .notRegularFile
            throw CoucouWorkspaceError.notRegularFile
        }

        var knownIDs = Set(files.map(\.id))
        var uniqueNewCount = 0
        for url in canonicalURLs where knownIDs.insert(url.path).inserted {
            uniqueNewCount += 1
        }
        guard files.count + uniqueNewCount <= Self.maximumFileCount else {
            let error = CoucouWorkspaceError.shelfFull(limit: Self.maximumFileCount)
            lastError = error
            throw error
        }

        var batchEntries: [String: CoucouWorkspaceFile] = [:]
        var addedEntries: [CoucouWorkspaceFile] = []
        let results = canonicalURLs.map { url -> CoucouWorkspaceFileAddResult in
            let id = url.path
            if let existing = files.first(where: { $0.id == id }) ?? batchEntries[id] {
                return .alreadyPresent(existing)
            }
            let file = CoucouWorkspaceFile(id: id, url: url, displayName: url.lastPathComponent, addedAt: Date())
            batchEntries[id] = file
            addedEntries.append(file)
            return .added(file)
        }
        files.append(contentsOf: addedEntries)
        lastError = nil
        return results
    }

    /// Removes a shelf entry only. The referenced original file is untouched.
    @discardableResult
    func removeFile(id: String) -> Bool {
        guard let index = files.firstIndex(where: { $0.id == id }) else { return false }
        files.remove(at: index)
        lastError = nil
        return true
    }

    /// Clears shelf metadata only. No filesystem operation is performed.
    func clear() {
        files.removeAll(keepingCapacity: false)
        lastError = nil
    }

    /// Shared validation for shelf additions and clipboard file references.
    /// Symlinks and `..` are resolved before the canonical path is returned.
    static func validatedCanonicalLocalFileURL(_ inputURL: URL) throws -> URL {
        guard inputURL.isFileURL else { throw CoucouWorkspaceError.invalidFileURL }

        // `file://host/path` can expose a path that looks local when read only
        // through URL.path. Never let a remote authority be treated as local.
        if let host = inputURL.host, !host.isEmpty,
           host.caseInsensitiveCompare("localhost") != .orderedSame {
            throw CoucouWorkspaceError.fileIsNotOnLocalVolume
        }
        let localInputURL = inputURL.host?.caseInsensitiveCompare("localhost") == .orderedSame
            ? URL(fileURLWithPath: inputURL.path)
            : inputURL

        let canonicalURL = localInputURL.resolvingSymlinksInPath().standardizedFileURL
        guard FileManager.default.fileExists(atPath: canonicalURL.path) else {
            throw CoucouWorkspaceError.fileMissing
        }

        let values: URLResourceValues
        do {
            values = try canonicalURL.resourceValues(forKeys: [.isRegularFileKey, .volumeIsLocalKey])
        } catch {
            guard FileManager.default.fileExists(atPath: canonicalURL.path) else {
                throw CoucouWorkspaceError.fileMissing
            }
            throw CoucouWorkspaceError.notRegularFile
        }
        guard values.isRegularFile == true else { throw CoucouWorkspaceError.notRegularFile }
        guard values.volumeIsLocal == true else { throw CoucouWorkspaceError.fileIsNotOnLocalVolume }
        return canonicalURL
    }
}

// MARK: - Session-only clipboard history

enum CoucouClipboardContentKind: String, Equatable, Sendable {
    case text
    case url
    case image
    case fileReference
}

/// A byte-for-byte representation of a narrowly allow-listed pasteboard type.
/// Unsupported/active types (HTML, RTF, arbitrary custom types, etc.) are not
/// read or retained. `data` is bounded by the capture service quotas.
struct CoucouClipboardRepresentation: Equatable, Sendable {
    let typeIdentifier: String
    let kind: CoucouClipboardContentKind
    let data: Data

    var byteCount: Int { data.count }
}

struct CoucouClipboardCapturedItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let representations: [CoucouClipboardRepresentation]

    init(id: UUID = UUID(), representations: [CoucouClipboardRepresentation]) {
        self.id = id
        self.representations = representations
    }
}

struct CoucouClipboardSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let capturedAt: Date
    let items: [CoucouClipboardCapturedItem]
    let byteCount: Int

    init(id: UUID = UUID(), capturedAt: Date = Date(), items: [CoucouClipboardCapturedItem]) {
        self.id = id
        self.capturedAt = capturedAt
        self.items = items
        self.byteCount = items.reduce(0) { total, item in
            total + item.representations.reduce(0) { $0 + $1.byteCount }
        }
    }

    /// Makes drag providers with the original, allow-listed pasteboard type
    /// identifiers. A destination can request its preferred representation.
    @MainActor
    func makeItemProviders() -> [NSItemProvider] {
        items.map { item in
            let provider = NSItemProvider()
            for representation in item.representations {
                let payload = representation.data
                if representation.kind == .fileReference,
                   let urlString = String(data: payload, encoding: .utf8),
                   let fileURL = URL(string: urlString), fileURL.isFileURL {
                    provider.registerFileRepresentation(
                        forTypeIdentifier: representation.typeIdentifier,
                        fileOptions: .openInPlace,
                        visibility: .all
                    ) { completion in
                        guard FileManager.default.fileExists(atPath: fileURL.path) else {
                            completion(nil, false, CoucouWorkspaceError.fileMissing as NSError)
                            return nil
                        }
                        completion(fileURL, false, nil)
                        return nil
                    }
                    continue
                }
                provider.registerDataRepresentation(
                    forTypeIdentifier: representation.typeIdentifier,
                    visibility: .all
                ) { completion in
                    completion(payload, nil)
                    return nil
                }
            }
            return provider
        }
    }

    /// Explicit button fallback for destinations that do not accept item
    /// providers. Calling this replaces only the supplied destination board.
    @MainActor
    func recopy(to destination: NSPasteboard) throws {
        let pasteboardItems = items.map { item -> NSPasteboardItem in
            let pasteboardItem = NSPasteboardItem()
            for representation in item.representations {
                pasteboardItem.setData(
                    representation.data,
                    forType: NSPasteboard.PasteboardType(rawValue: representation.typeIdentifier)
                )
            }
            return pasteboardItem
        }
        destination.clearContents()
        guard destination.writeObjects(pasteboardItems) else {
            throw CoucouWorkspaceError.clipboardWriteFailed
        }
    }
}

/// Explicitly authorized, in-memory clipboard capture. Monitoring is off by
/// default and this service creates no timers. A caller may call
/// `captureManually` only in response to a user action, or opt in with
/// `enableChangeMonitoring` and call `captureIfChanged` while enabled.
///
/// Capture is intentionally not a safety classifier: content with recognized
/// concealed/transient/generated/password-manager type markers is rejected,
/// but ordinary text is not inspected to decide whether it is secret. AppKit
/// exposes pasteboard payloads as materialized values, so quotas bound retained
/// history but cannot prevent a single oversized representation from being
/// temporarily materialized before its size is checked.
@MainActor
final class CoucouClipboardAccessService: ObservableObject {
    static let maximumCaptureBytes = 4 * 1_024 * 1_024
    static let maximumClipboardItems = 64
    static let maximumHistoryEntries = 20
    static let maximumHistoryBytes = 16 * 1_024 * 1_024

    @Published private(set) var isChangeMonitoringEnabled = false
    @Published private(set) var history: [CoucouClipboardSnapshot] = []
    @Published private(set) var lastError: CoucouWorkspaceError?

    private let pasteboard: NSPasteboard
    private var lastObservedChangeCount: Int?
    private var historyByteCount = 0

    /// Defaults to the app's clipboard for production use, but no clipboard
    /// properties or content are read by initialization. Tests should inject a
    /// separate named pasteboard.
    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Opts in to change-driven capture. This samples only `changeCount` to
    /// establish a baseline; it does not read clipboard content or start a timer.
    func enableChangeMonitoring() {
        lastObservedChangeCount = pasteboard.changeCount
        isChangeMonitoringEnabled = true
    }

    /// Stops change-driven access immediately; it does not clear captured
    /// history or alter the system pasteboard.
    func disableChangeMonitoring() {
        isChangeMonitoringEnabled = false
        lastObservedChangeCount = nil
    }

    /// Reads the pasteboard for this explicit/manual capture request, even if
    /// change monitoring is off. Call only as the result of a user action.
    @discardableResult
    func captureManually(excludingTypeIdentifiers exclusions: Set<String> = []) throws -> CoucouClipboardSnapshot {
        do {
            let snapshot = try readSupportedSnapshot(excludingTypeIdentifiers: exclusions)
            appendToHistory(snapshot)
            lastError = nil
            return snapshot
        } catch let error as CoucouWorkspaceError {
            lastError = error
            throw error
        } catch {
            lastError = .noSupportedClipboardContent
            throw CoucouWorkspaceError.noSupportedClipboardContent
        }
    }

    /// Pasteboard change counter. Reading it does not read clipboard content.
    var currentChangeCount: Int { pasteboard.changeCount }

    /// Reads whatever is on the system pasteboard right now, for display only.
    /// Nothing is retained: it does not touch `history` or `lastError`, and it
    /// applies the same allow-list, size quotas and sensitive-marker rejection
    /// as a capture. Call only while the user is looking at the Clipboard pane.
    func currentSnapshot(excludingTypeIdentifiers exclusions: Set<String> = []) throws -> CoucouClipboardSnapshot {
        do {
            return try readSupportedSnapshot(excludingTypeIdentifiers: exclusions)
        } catch let error as CoucouWorkspaceError {
            throw error
        } catch {
            throw CoucouWorkspaceError.noSupportedClipboardContent
        }
    }

    /// Polling is caller-driven (there is no internal timer). It reads
    /// `changeCount` only after opt-in. A changed board is captured once; a
    /// failed capture still consumes that change so sensitive/oversized content
    /// is not repeatedly read on every caller poll.
    @discardableResult
    func captureIfChanged(excludingTypeIdentifiers exclusions: Set<String> = []) throws -> CoucouClipboardSnapshot? {
        guard isChangeMonitoringEnabled else {
            lastError = .clipboardMonitoringDisabled
            throw CoucouWorkspaceError.clipboardMonitoringDisabled
        }
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastObservedChangeCount else { return nil }
        lastObservedChangeCount = currentChangeCount
        return try captureManually(excludingTypeIdentifiers: exclusions)
    }

    /// Clears in-memory captured snapshots only. The system pasteboard is not
    /// changed, and no external data is deleted.
    func clearHistory() {
        history.removeAll(keepingCapacity: false)
        historyByteCount = 0
    }

    /// Removes one in-memory snapshot without changing the system pasteboard.
    @discardableResult
    func removeSnapshot(id: UUID) -> Bool {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return false }
        historyByteCount -= history[index].byteCount
        history.remove(at: index)
        return true
    }

    private func appendToHistory(_ snapshot: CoucouClipboardSnapshot) {
        // Every accepted capture is <= maximumCaptureBytes, which is below the
        // history byte cap. Drop oldest entries to enforce both quotas.
        while !history.isEmpty && (history.count >= Self.maximumHistoryEntries ||
                                   historyByteCount + snapshot.byteCount > Self.maximumHistoryBytes) {
            historyByteCount -= history.removeFirst().byteCount
        }
        history.append(snapshot)
        historyByteCount += snapshot.byteCount
    }

    private func readSupportedSnapshot(excludingTypeIdentifiers exclusions: Set<String>) throws -> CoucouClipboardSnapshot {
        guard let pasteboardItems = pasteboard.pasteboardItems, !pasteboardItems.isEmpty else {
            throw CoucouWorkspaceError.noSupportedClipboardContent
        }
        guard pasteboardItems.count <= Self.maximumClipboardItems else {
            throw CoucouWorkspaceError.tooManyClipboardItems(limit: Self.maximumClipboardItems)
        }

        // Inspect only type metadata across the whole board first, so a marker
        // in a later item prevents payload reads from earlier items as well.
        let advertisedTypesByItem = pasteboardItems.map { $0.types.map(\.rawValue) }
        if advertisedTypesByItem.joined().contains(where: Self.isSensitiveTypeIdentifier) {
            throw CoucouWorkspaceError.sensitiveClipboardTypeDetected
        }

        var totalBytes = 0
        var capturedItems: [CoucouClipboardCapturedItem] = []
        capturedItems.reserveCapacity(pasteboardItems.count)

        for (pasteboardItem, advertisedTypeIdentifiers) in zip(pasteboardItems, advertisedTypesByItem) {
            var representations: [CoucouClipboardRepresentation] = []
            for descriptor in Self.supportedRepresentations {
                let typeIdentifier = descriptor.type.rawValue
                guard advertisedTypeIdentifiers.contains(typeIdentifier),
                      !exclusions.contains(typeIdentifier) else { continue }

                guard let representation = try Self.read(descriptor, from: pasteboardItem) else { continue }
                guard representation.byteCount <= Self.maximumCaptureBytes else {
                    throw CoucouWorkspaceError.clipboardPayloadTooLarge(limitBytes: Self.maximumCaptureBytes)
                }
                totalBytes += representation.byteCount
                guard totalBytes <= Self.maximumCaptureBytes else {
                    throw CoucouWorkspaceError.clipboardPayloadTooLarge(limitBytes: Self.maximumCaptureBytes)
                }
                representations.append(representation)
            }
            if !representations.isEmpty {
                capturedItems.append(CoucouClipboardCapturedItem(representations: representations))
            }
        }

        guard !capturedItems.isEmpty else { throw CoucouWorkspaceError.noSupportedClipboardContent }
        return CoucouClipboardSnapshot(items: capturedItems)
    }

    private struct SupportedRepresentation {
        let type: NSPasteboard.PasteboardType
        let kind: CoucouClipboardContentKind
    }

    private static let supportedRepresentations: [SupportedRepresentation] = [
        SupportedRepresentation(type: .string, kind: .text),
        SupportedRepresentation(type: .URL, kind: .url),
        SupportedRepresentation(type: .fileURL, kind: .fileReference),
        SupportedRepresentation(type: .png, kind: .image),
        SupportedRepresentation(type: .tiff, kind: .image)
    ]

    private static func read(
        _ descriptor: SupportedRepresentation,
        from item: NSPasteboardItem
    ) throws -> CoucouClipboardRepresentation? {
        let data: Data
        if descriptor.kind == .image {
            guard let imageData = item.data(forType: descriptor.type) else { return nil }
            data = imageData
        } else {
            guard let string = item.string(forType: descriptor.type) else { return nil }
            if descriptor.kind == .fileReference {
                guard let fileURL = URL(string: string), fileURL.isFileURL else {
                    throw CoucouWorkspaceError.invalidFileURL
                }
                let validatedURL = try CoucouWorkspaceStore.validatedCanonicalLocalFileURL(fileURL)
                data = Data(validatedURL.absoluteString.utf8)
            } else {
                data = Data(string.utf8)
            }
        }
        return CoucouClipboardRepresentation(
            typeIdentifier: descriptor.type.rawValue,
            kind: descriptor.kind,
            data: data
        )
    }

    private static func isSensitiveTypeIdentifier(_ identifier: String) -> Bool {
        let normalized = identifier.lowercased().filter(\.isLetterOrNumber)
        let markers = [
            "concealed", "transient", "autogenerated", "password", "passphrase",
            "credential", "secret", "onepassword", "1password", "lastpass",
            "bitwarden", "keepass", "dashlane", "protonpass", "keepersecurity"
        ]
        return markers.contains(where: normalized.contains)
    }
}

private extension Character {
    var isLetterOrNumber: Bool { isLetter || isNumber }
}
