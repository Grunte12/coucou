import Foundation

// MARK: - Inviting an agent into the user's Tincan team (from Settings)
//
// Seed never joins agents itself. It asks the local `tincan` CLI for a one-time
// invite through the relay's admin socket on this Mac, and shows the join
// message for the user to paste into that agent. Nothing leaves this Mac.

enum SeedAgentInvite {
    /// Runtimes worth offering in Settings, in the CLI's own kind ids.
    static let kinds: [(id: String, title: String)] = [
        ("codex", "Codex"),
        ("claude-code", "Claude Code"),
        ("gemini-cli", "Gemini CLI"),
        ("grok-cli", "Grok CLI"),
        ("hermes", "Hermes"),
        ("generic", "Other"),
    ]

    /// Tincan agent names: lowercase letters, digits and hyphens, 1–24 characters, not starting with a hyphen.
    static func validName(_ raw: String) -> Bool {
        raw.range(of: "^[a-z0-9][a-z0-9-]{0,23}$", options: .regularExpression) != nil
    }

    /// The relay admin socket, read from running command lines: the Hub's
    /// `--tincan-admin-socket` first, else a relay's `--state-dir` + `/admin.sock`.
    static func adminSocket(in commandLines: [String]) -> String? {
        func value(_ flag: String, in line: String) -> String? {
            let parts = line.split(separator: " ").map(String.init)
            for (i, part) in parts.enumerated() {
                if part == flag, i + 1 < parts.count { return parts[i + 1] }
                if part.hasPrefix(flag + "=") { return String(part.dropFirst(flag.count + 1)) }
            }
            return nil
        }
        for line in commandLines where line.contains("agent_hub") {
            if let socket = value("--tincan-admin-socket", in: line) { return socket }
        }
        for line in commandLines where line.contains("tincan relay") {
            if let dir = value("--state-dir", in: line) { return dir + "/admin.sock" }
        }
        return nil
    }

    static func tincanBinary(exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [home + "/.local/bin/tincan", "/opt/homebrew/bin/tincan", "/usr/local/bin/tincan"].first(where: exists)
    }

    /// Creates the invite and returns the CLI's join message, or a short reason it failed.
    static func create(name: String, kind: String) async -> Result<String, InviteError> {
        guard validName(name) else { return .failure(.badName) }
        guard kinds.contains(where: { $0.id == kind }) else { return .failure(.badKind) }
        guard let binary = tincanBinary() else { return .failure(.noTincan) }
        let lines = (try? await run("/bin/ps", ["-axo", "command="]))?.out.split(separator: "\n").map(String.init) ?? []
        guard let socket = adminSocket(in: lines) else { return .failure(.noRelay) }
        do {
            let result = try await run(binary, ["invite", name, "--kind", kind, "--socket", socket])
            let text = result.out.trimmingCharacters(in: .whitespacesAndNewlines)
            guard result.status == 0, !text.isEmpty else {
                return .failure(.failed(result.err.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            return .success(text)
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
    }

    enum InviteError: Error, Equatable {
        case badName, badKind, noTincan, noRelay, failed(String)

        var message: String {
            switch self {
            case .badName:  return "Use lowercase letters, digits and hyphens (up to 24)."
            case .badKind:  return "Choose what kind of agent it is."
            case .noTincan: return "The tincan command is not installed on this Mac."
            case .noRelay:  return "No Tincan relay is running on this Mac. Start it, then try again."
            case .failed(let why): return why.isEmpty ? "tincan could not create the invite." : String(why.prefix(240))
            }
        }
    }

    private struct Output: Sendable { let status: Int32; let out: String; let err: String }

    /// Runs a command off the main thread with a 20 s limit.
    private static func run(_ path: String, _ args: [String]) async throws -> Output {
        try await Task.detached(priority: .userInitiated) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            p.standardInput = FileHandle.nullDevice
            try p.run()
            // A hung CLI is stopped, which also closes its pipes so the reads below return.
            DispatchQueue.global().asyncAfter(deadline: .now() + 20) { if p.isRunning { p.terminate() } }
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return Output(status: p.terminationStatus,
                          out: String(decoding: outData.prefix(16_384), as: UTF8.self),
                          err: String(decoding: errData.prefix(4_096), as: UTF8.self))
        }.value
    }
}
