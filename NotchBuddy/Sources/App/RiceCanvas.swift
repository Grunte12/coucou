#if COUCOU_HUB
import SwiftUI
import CoreGraphics

// MARK: - A small Core Graphics canvas for Seed
//
// Seed is drawn every frame, so it is drawn without SwiftUI: straight into a
// bitmap with Core Graphics, which the layer view then shows. RiceCanvas keeps
// the same shape as SwiftUI's GraphicsContext (value copies, translate/scale/
// rotate, replace-style opacity, clip, fill/stroke with colours and gradients)
// so the painter reads the same as before. Blur, the one thing Core Graphics
// lacks, is made with a shadow cast from a copy drawn out of view.

/// An sRGB colour with alpha, resolved once (no SwiftUI environment per frame).
struct RiceRGBA: Sendable {
    var r, g, b, a: CGFloat
    static let white = RiceRGBA(r: 1, g: 1, b: 1, a: 1)
    func opacity(_ o: Double) -> RiceRGBA { RiceRGBA(r: r, g: g, b: b, a: a * CGFloat(o)) }
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

/// Colour stops, turned into a CGGradient once.
final class RiceGradient: @unchecked Sendable {
    let cg: CGGradient

    init(_ stops: [(RiceRGBA, CGFloat)]) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        cg = CGGradient(colorsSpace: space, colors: stops.map(\.0.cg) as CFArray,
                        locations: stops.map(\.1))!
    }

    convenience init(colors: [RiceRGBA]) {
        let n = max(1, colors.count - 1)
        self.init(colors.enumerated().map { ($0.element, CGFloat($0.offset) / CGFloat(n)) })
    }
}

enum RiceShading {
    case color(RiceRGBA)
    case linearGradient(RiceGradient, startPoint: CGPoint, endPoint: CGPoint)
    case radialGradient(RiceGradient, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat)
}

/// Where a canvas draws: one bitmap, or a recorder that splits the frame into
/// live bitmaps and sprites for Core Animation to composite.
protocol RiceSink: AnyObject {
    var context: CGContext { get }
}

final class RiceBitmapSink: RiceSink {
    let context: CGContext
    init(_ context: CGContext) { self.context = context }
}

/// Records a frame as layers. Live drawing goes into a bitmap; a sprite closes
/// that bitmap and is kept as an image with a transform and an opacity, so the
/// render server, not this process, scales, rotates and blends it.
final class RiceRecorder: RiceSink {
    enum Item {
        case live(CGImage)
        /// `transform` maps the sprite's own rect (origin at 0,0, in units) to points, y down.
        case sprite(CGImage, size: CGSize, transform: CGAffineTransform, opacity: Float)
    }

    private let width: Int, height: Int
    private var live: CGContext?
    private(set) var items: [Item] = []

    init(width: Int, height: Int) { self.width = width; self.height = height }

    var context: CGContext {
        if let live { return live }
        let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: RiceSprites.bitmapInfo)!
        c.setShouldAntialias(true)
        c.interpolationQuality = .medium
        live = c
        return c
    }

    func sprite(_ image: CGImage, rect: CGRect, toPoints: CGAffineTransform, opacity: Double) {
        guard opacity > 0.001 else { return }
        closeLive()
        let t = CGAffineTransform(translationX: rect.minX, y: rect.minY).concatenating(toPoints)
        items.append(.sprite(image, size: rect.size, transform: t, opacity: Float(opacity)))
    }

    func finish() -> [Item] {
        closeLive()
        return items
    }

    private func closeLive() {
        if let live, let image = live.makeImage() { items.append(.live(image)) }
        live = nil
    }
}

struct RiceCanvas {
    private let sink: RiceSink
    var cg: CGContext { sink.context }
    /// User space (y down, points) to the bitmap's pixels.
    private(set) var ctm: CGAffineTransform
    /// Points (y down) to the bitmap's pixels: the canvas' starting transform.
    private let base: CGAffineTransform
    var opacity: Double = 1
    var blendMode: CGBlendMode = .normal
    /// Clips already in pixel space.
    private var clips: [CGPath] = []
    /// Inside `blurred`: the Gaussian radius, in user units, applied to everything drawn.
    private var blur: CGFloat?

    /// A canvas over a sprite bitmap that covers `rect` (user units) at `pixelsPerUnit`.
    init(_ cg: CGContext, rect: CGRect, pixelsPerUnit s: CGFloat) {
        sink = RiceBitmapSink(cg)
        ctm = CGAffineTransform(a: s, b: 0, c: 0, d: -s, tx: -s * rect.minX, ty: s * rect.maxY)
        base = ctm
    }

    /// A canvas over a bitmap context whose pixels are `scale` times the points.
    init(_ cg: CGContext, height: CGFloat, scale: CGFloat) {
        self.init(sink: RiceBitmapSink(cg), height: height, scale: scale)
    }

    /// A canvas that records layers (see RiceRecorder), `scale` pixels per point.
    init(sink: RiceSink, height: CGFloat, scale: CGFloat) {
        self.sink = sink
        ctm = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: 0, ty: height * scale)
        base = ctm
    }

    mutating func translateBy(x: CGFloat, y: CGFloat) { ctm = ctm.translatedBy(x: x, y: y) }
    mutating func scaleBy(x: CGFloat, y: CGFloat) { ctm = ctm.scaledBy(x: x, y: y) }
    mutating func rotate(by angle: Angle) { ctm = ctm.rotated(by: CGFloat(angle.radians)) }

    mutating func clip(to path: Path) {
        var t = ctm
        if let p = path.cgPath.copy(using: &t) { clips.append(p) }
    }

    // MARK: drawing

    func fill(_ path: Path, with shading: RiceShading) {
        draw(path.cgPath, shading: shading) { cg in
            cg.addPath(path.cgPath)
        } stroke: { _ in false }
    }

    func stroke(_ path: Path, with shading: RiceShading, lineWidth: CGFloat) {
        stroke(path, with: shading, style: StrokeStyle(lineWidth: lineWidth))
    }

    func stroke(_ path: Path, with shading: RiceShading, style: StrokeStyle) {
        draw(path.cgPath, shading: shading) { cg in
            cg.addPath(path.cgPath)
        } stroke: { cg in
            cg.setLineWidth(style.lineWidth)
            cg.setLineCap(style.lineCap)
            cg.setLineJoin(style.lineJoin)
            cg.setMiterLimit(style.miterLimit)
            if !style.dash.isEmpty { cg.setLineDash(phase: style.dashPhase, lengths: style.dash) }
            return true
        }
    }

    /// Draws an image into `rect` (user space, y down) the right way up.
    func draw(_ image: CGImage, in rect: CGRect) {
        guard opacity > 0.001 else { return }
        if let recorder = sink as? RiceRecorder, clips.isEmpty, blendMode == .normal {
            recorder.sprite(image, rect: rect, toPoints: ctm.concatenating(base.inverted()), opacity: opacity)
            return
        }
        cg.saveGState(); defer { cg.restoreGState() }
        applyClips()
        cg.concatenate(ctm)
        cg.setAlpha(CGFloat(opacity)); cg.setBlendMode(blendMode)
        cg.translateBy(x: rect.minX, y: rect.maxY)
        cg.scaleBy(x: 1, y: -1)
        cg.interpolationQuality = .medium
        cg.draw(image, in: CGRect(origin: .zero, size: rect.size))
    }

    /// Everything drawn inside is blurred by `radius` (user units).
    func blurred(radius: CGFloat, _ body: (RiceCanvas) -> Void) {
        var child = self
        child.blur = radius
        body(child)
    }

    // MARK: internals

    private func applyClips() {
        for c in clips { cg.addPath(c); cg.clip() }
    }

    /// The scale from user units to pixels (for blur radii, offsets and sprite sizes).
    var pixelScale: CGFloat { sqrt(abs(ctm.a * ctm.d - ctm.b * ctm.c)) }

    private func draw(_ path: CGPath, shading: RiceShading,
                      add: (CGContext) -> Void, stroke: (CGContext) -> Bool) {
        guard opacity > 0.001 else { return }
        cg.saveGState(); defer { cg.restoreGState() }
        applyClips()
        cg.setAlpha(CGFloat(opacity))
        cg.setBlendMode(blendMode)

        if let blur {
            // Blur as a shadow: draw the shape far off to the left and cast its
            // shadow back onto the right place. Shadows use pixel space.
            let away: CGFloat = 10_000
            let color: RiceRGBA
            if case .color(let c) = shading { color = c } else { color = .white }
            // Core Graphics' shadow blur is close to twice a Gaussian radius.
            cg.setShadow(offset: CGSize(width: away, height: 0), blur: blur * pixelScale * 2, color: color.cg)
            cg.concatenate(CGAffineTransform(translationX: -away, y: 0))
            cg.concatenate(ctm)
            add(cg)
            if stroke(cg) { cg.setStrokeColor(color.cg); cg.strokePath() } else { cg.setFillColor(color.cg); cg.fillPath() }
            return
        }

        cg.concatenate(ctm)
        add(cg)
        let isStroke = stroke(cg)
        switch shading {
        case .color(let c):
            if isStroke { cg.setStrokeColor(c.cg); cg.strokePath() } else { cg.setFillColor(c.cg); cg.fillPath() }
        case .linearGradient(let g, let a, let b):
            if isStroke { cg.replacePathWithStrokedPath() }
            cg.clip()
            cg.drawLinearGradient(g.cg, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        case .radialGradient(let g, let c, let r0, let r1):
            if isStroke { cg.replacePathWithStrokedPath() }
            cg.clip()
            cg.drawRadialGradient(g.cg, startCenter: c, startRadius: r0, endCenter: c, endRadius: r1,
                                  options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    }
}
#endif
