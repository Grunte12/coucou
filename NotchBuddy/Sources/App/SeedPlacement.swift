#if COUCOU_HUB
import SwiftUI

// MARK: - Seed in the notch
//
// Seed replaces Mochi everywhere in the notch: the closed strip and every
// expanded view. Same spot Mochi used (botPosition), same shared motion as the
// workspace companion, so Seed keeps its pose when the notch opens or closes.
// In the expanded agent workspace the pane draws Seed in its gutter instead.

struct SeedPlacement: View {
    @ObservedObject var state: AppState
    let islandW: CGFloat
    let islandH: CGFloat

    var body: some View {
        let (cx, cy, diameter, opacity) = botPosition(mode: state.mode, view: state.view, islandW: islandW, islandH: islandH,
                                                      uploadProgress: state.uploadProgress, hasNotch: state.hasNotch)
        // The grain is about 0.76 of the box tall; match Mochi's body diameter.
        let box = max(16, diameter * 1.3)
        let side = box * 1.62
        // The workspace draws its own Seed; this copy stays quiet meanwhile.
        let inWorkspace = state.mode == .expanded && state.view == .linkHub
        CoucouRiceCompanion(holder: .shared, state: state, box: box, side: side, reacts: !inWorkspace)
            .frame(width: side, height: side)
            .opacity(opacity)
            .position(x: cx, y: cy)
            .animation(.spring(response: 0.5, dampingFraction: 0.78), value: cx)
            .animation(.spring(response: 0.5, dampingFraction: 0.78), value: cy)
            .animation(.spring(response: 0.5, dampingFraction: 0.78), value: box)
            // Clicks in the closed notch open it; Seed's own presses live in the workspace.
            .allowsHitTesting(false)
    }
}
#endif
