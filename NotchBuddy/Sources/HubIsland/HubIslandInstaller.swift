import Foundation

/// Install-time handoff only. Secrets travel over stdin, never arguments or logs.
enum HubIslandInstaller {
    static func run(arguments: [String]) -> Int32? {
        guard arguments.contains("--check-hub-credential") || arguments.contains("--import-hub-credential") else {
            return nil
        }
        do {
            if arguments == ["--check-hub-credential"] {
                emit(["present": try HubIslandCredentialStore.load() != nil])
                return 0
            }
            guard arguments == ["--import-hub-credential"] || arguments == ["--import-hub-credential", "--replace"] else {
                emit(["error": "invalid_arguments"])
                return 2
            }
            if try HubIslandCredentialStore.load() != nil && !arguments.contains("--replace") {
                emit(["error": "credential_exists"])
                return 3
            }
            let data = FileHandle.standardInput.readData(ofLength: 4097)
            guard data.count <= 4096,
                  let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(payload.keys) == ["credential"],
                  let credential = payload["credential"] as? String,
                  credential.utf8.count == 43,
                  credential.unicodeScalars.allSatisfy({
                      (65...90).contains($0.value) || (97...122).contains($0.value)
                      || (48...57).contains($0.value) || $0 == "-" || $0 == "_"
                  }) else {
                emit(["error": "invalid_payload"])
                return 2
            }
            try HubIslandCredentialStore.save(credential)
            guard try HubIslandCredentialStore.load() == credential else {
                emit(["error": "keychain_verification_failed"])
                return 4
            }
            emit(["saved": true])
            return 0
        } catch {
            emit(["error": "keychain_or_payload_failed"])
            return 4
        }
    }

    private static func emit(_ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }
}
