import Foundation

@main
struct SeedSettingsTests {
    static var failures = 0
    static func check(_ ok: Bool, _ name: String) {
        if !ok { failures += 1; print("FAIL: \(name)") }
    }

    @MainActor static func main() {
        // Agent names Tincan accepts.
        check(SeedAgentInvite.validName("codex"), "plain name")
        check(SeedAgentInvite.validName("codex-2"), "name with digit and hyphen")
        check(!SeedAgentInvite.validName(""), "empty name")
        check(!SeedAgentInvite.validName("-codex"), "leading hyphen")
        check(!SeedAgentInvite.validName("Codex"), "uppercase")
        check(!SeedAgentInvite.validName("codex 2"), "space")
        check(!SeedAgentInvite.validName("codex;rm"), "shell characters")
        check(!SeedAgentInvite.validName(String(repeating: "a", count: 25)), "too long")
        check(SeedAgentInvite.kinds.contains { $0.id == "codex" } && SeedAgentInvite.kinds.contains { $0.id == "claude-code" },
              "Codex and Claude Code are offered")

        // Admin socket: the Hub's flag wins, else the relay's state dir.
        let hub = "/venv/bin/python -m agent_hub.cli serve --port 8767 --tincan-admin-socket /r/admin.sock"
        let relay = "/Users/me/.local/bin/tincan relay --listen 100.1.2.3 --port 8790 --state-dir /s/relay"
        check(SeedAgentInvite.adminSocket(in: [relay, hub]) == "/r/admin.sock", "hub flag first")
        check(SeedAgentInvite.adminSocket(in: [relay]) == "/s/relay/admin.sock", "relay state dir")
        check(SeedAgentInvite.adminSocket(in: ["tincan relay --state-dir=/x"]) == "/x/admin.sock", "flag=value form")
        check(SeedAgentInvite.adminSocket(in: ["tincan mcp", "tincan listen --exec foo"]) == nil, "no relay, no socket")
        check(SeedAgentInvite.adminSocket(in: ["vim notes --state-dir /tmp"]) == nil, "unrelated processes ignored")

        // Binary lookup checks only known locations.
        check(SeedAgentInvite.tincanBinary(exists: { $0.hasSuffix("/opt/homebrew/bin/tincan") }) == "/opt/homebrew/bin/tincan", "homebrew tincan")
        check(SeedAgentInvite.tincanBinary(exists: { _ in false }) == nil, "no tincan")

        // Ring order from Settings.
        let defaults = UserDefaults(suiteName: "seed.settings.tests.\(UUID().uuidString)")!
        let ring = SeedRingStore(store: defaults)
        ring.move(.review, by: -1)
        check(ring.slots.prefix(2) == [.review, .timeline], "move up swaps with the one before")
        ring.move(.review, by: -1)
        check(ring.slots.first == .review, "moving past the top is ignored")
        ring.move(.settings, by: 1)
        check(ring.slots.last == .settings, "moving past the end is ignored")
        check(SeedRingStore.decode(defaults.stringArray(forKey: "seed.ring.slots")) == ring.slots, "order is saved")
        ring.move(.agents, by: 1)
        check(ring.slots.count == 6, "moving an action not in the ring changes nothing")

        print(failures == 0 ? "seed-settings: all passed" : "seed-settings: \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
