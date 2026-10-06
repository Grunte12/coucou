import SwiftUI

/// Concave notch ears adapted from Louis Raillé's MIT-licensed Coucou IslandShape.
/// This contains no reserved character, artwork or audio assets.
struct HubIslandShape: Shape {
    var compact: Bool

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let radius = min(14.0, height / 2)
        var path = Path()
        if compact {
            path.move(to: .zero)
            path.addArc(center: CGPoint(x: 0, y: radius), radius: radius,
                        startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: width - radius, y: radius))
            path.addArc(center: CGPoint(x: width, y: radius), radius: radius,
                        startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        } else {
            // The screen edge is the top boundary, not a detached floating card.
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: width, y: 0))
        }
        path.addLine(to: CGPoint(x: width, y: height - radius))
        path.addArc(center: CGPoint(x: width - radius, y: height - radius), radius: radius,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: radius, y: height))
        path.addArc(center: CGPoint(x: radius, y: height - radius), radius: radius,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: .zero)
        path.closeSubpath()
        return path
    }
}
