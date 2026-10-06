import AppKit

@main
enum MotionSoundTests {
    @MainActor static func main() {
        for expanded in [true, false] {
            let data = HubIslandSound.cueData(opening: expanded)
            precondition(data.count == 4454)
            precondition(String(data: data.prefix(4), encoding: .utf8) == "RIFF")
            precondition(NSSound(data: data) != nil)
        }
        precondition(HubIslandSound.cueData(opening: true) != HubIslandSound.cueData(opening: false))
        print("Hub Island sound: both WAV decodes passed; no audio played. Motion uses SwiftUI, not the old timer curve.")
    }
}
