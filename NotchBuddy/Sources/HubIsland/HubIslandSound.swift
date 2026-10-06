import AppKit

/// Original two-tone interface cue, synthesized locally; no Coucou audio assets.
@MainActor
enum HubIslandSound {
    private static var active: NSSound?

    static func play(opening: Bool) {
        guard UserDefaults.standard.bool(forKey: "hubIsland.soundEnabled") else { return }
        active?.stop()
        active = NSSound(data: cueData(opening: opening))
        active?.volume = 0.35
        active?.play()
    }

    static func cueData(opening: Bool) -> Data {
        let rate = 22050
        let count = 2205
        var pcm = Data()
        for index in 0..<count {
            let t = Double(index) / Double(rate)
            let phase = Double(index) / Double(count)
            let frequency = opening ? 520 + 340 * phase : 720 - 260 * phase
            let envelope = sin(.pi * phase) * exp(-3 * phase)
            let sample = Int16(sin(2 * .pi * frequency * t) * envelope * 2400)
            append(UInt16(bitPattern: sample), to: &pcm)
        }
        var wav = Data("RIFF".utf8)
        append(UInt32(36 + pcm.count), to: &wav)
        wav.append(Data("WAVEfmt ".utf8))
        append(UInt32(16), to: &wav)
        append(UInt16(1), to: &wav)
        append(UInt16(1), to: &wav)
        append(UInt32(rate), to: &wav)
        append(UInt32(rate * 2), to: &wav)
        append(UInt16(2), to: &wav)
        append(UInt16(16), to: &wav)
        wav.append(Data("data".utf8))
        append(UInt32(pcm.count), to: &wav)
        wav.append(pcm)
        return wav
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
}
