#if COUCOU_HUB
import SwiftUI
import CoreImage

// The rice mascot, drawn in code exactly as brand/rice/motion-lab.html (v4) draws
// it: white grain, glowing golden rim, breathing aura, eyes inside the body that
// follow the pointer, soft cheeks, happy ^ ^ eyes and round props only.
// Coordinates follow the lab: a 320-unit view box, the character's origin at
// (160, 168) and its parts in "rice units" scaled by 1.4.

/// Seed's parts that never change shape (the glows, the aura, the light pool,
/// the white body and its gold rim line) are drawn once into bitmaps at the
/// size they appear on screen, in the screen's pixel format. Each frame then
/// only places them with a transform and an opacity, which is a cheap copy,
/// and draws the small live parts (eyes, cheeks, props) on top.
///
/// Sprites are keyed by part and by a pixel-density bucket (steps of about 19%),
/// so a squash or a hop reuses them; a new size builds its set once.
enum RiceSprites {
    /// Body-unit rectangle the glow sprites cover (body is about 116 x 174, plus blur margin).
    static let glowRect = CGRect(x: -120, y: -160, width: 240, height: 320)

    // Drawn only from the main thread (the layer view and the lab).
    nonisolated(unsafe) private static var cache: [String: CGImage] = [:]
    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!
    static let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

    /// Rounds pixels-per-unit up to a bucket, so sprites are never upscaled much.
    static func bucket(_ scale: CGFloat) -> CGFloat {
        let s = min(max(scale, 0.05), 6)
        return pow(2, (log2(s) * 4).rounded(.up) / 4)
    }

    /// The sprite for `key`, drawn by `build` over `rect` (body units) at `scale` pixels per unit.
    static func image(_ key: String, rect: CGRect, scale: CGFloat, blur sigma: CGFloat = 0, clip: Path? = nil,
                      build: (RiceCanvas) -> Void) -> CGImage? {
        let b = bucket(scale)
        let name = "\(key)@\(b)"
        if let hit = cache[name] { return hit }
        let w = Int((rect.width * b).rounded(.up)), h = Int((rect.height * b).rounded(.up))
        guard w > 0, h > 0, let cg = bitmap(w, h) else { return nil }
        build(RiceCanvas(cg, rect: rect, pixelsPerUnit: b))
        guard var image = cg.makeImage() else { return nil }
        if sigma > 0, let blurred = blur(image, sigma: sigma * b) { image = blurred }
        if let clip, let clipped = bitmap(w, h) {
            // Clip after the blur, in the sprite's own space: exact wherever the sprite is drawn.
            var t = CGAffineTransform(a: b, b: 0, c: 0, d: -b, tx: -b * rect.minX, ty: b * rect.maxY)
            if let p = clip.cgPath.copy(using: &t) { clipped.addPath(p); clipped.clip() }
            clipped.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            if let out = clipped.makeImage() { image = out }
        }
        cache[name] = image
        return image
    }

    private static func bitmap(_ w: Int, _ h: Int) -> CGContext? {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo)
    }

    /// A Gaussian blur, returned in the screen's pixel format so drawing it needs no conversion.
    private static func blur(_ image: CGImage, sigma: CGFloat) -> CGImage? {
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        let input = CIImage(cgImage: image)
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(sigma, forKey: kCIInputRadiusKey)
        guard let out = filter.outputImage?.cropped(to: input.extent),
              let raw = CIContext(options: [.workingColorSpace: space]).createCGImage(out, from: input.extent),
              let cg = bitmap(image.width, image.height) else { return nil }
        cg.draw(raw, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return cg.makeImage()
    }
}

enum RicePainter {
    static let G: CGFloat = 80   // squash anchor: the bottom of the grain

    static let body: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -94))
        p.addCurve(to: CGPoint(x: 54, y: -6), control1: CGPoint(x: 18, y: -94), control2: CGPoint(x: 49, y: -54))
        p.addCurve(to: CGPoint(x: 0, y: 80), control1: CGPoint(x: 58, y: 42), control2: CGPoint(x: 34, y: 80))
        p.addCurve(to: CGPoint(x: -54, y: -6), control1: CGPoint(x: -34, y: 80), control2: CGPoint(x: -58, y: 42))
        p.addCurve(to: CGPoint(x: 0, y: -94), control1: CGPoint(x: -49, y: -54), control2: CGPoint(x: -18, y: -94))
        p.closeSubpath()
        return p
    }()
    static let bodyBox = CGRect(x: -55.3, y: -94, width: 110.6, height: 174)
    static let bodyLength: CGFloat = curveLength([
        (CGPoint(x: 0, y: -94), CGPoint(x: 18, y: -94), CGPoint(x: 49, y: -54), CGPoint(x: 54, y: -6)),
        (CGPoint(x: 54, y: -6), CGPoint(x: 58, y: 42), CGPoint(x: 34, y: 80), CGPoint(x: 0, y: 80)),
        (CGPoint(x: 0, y: 80), CGPoint(x: -34, y: 80), CGPoint(x: -58, y: 42), CGPoint(x: -54, y: -6)),
        (CGPoint(x: -54, y: -6), CGPoint(x: -49, y: -54), CGPoint(x: -18, y: -94), CGPoint(x: 0, y: -94)),
    ])

    // Sending trail: M0 0 C26 -2 46 -18 62 -46, with an arc-length table for the orb.
    static let trailCurve = (CGPoint(x: 0, y: 0), CGPoint(x: 26, y: -2), CGPoint(x: 46, y: -18), CGPoint(x: 62, y: -46))
    static let trail: Path = {
        var p = Path()
        p.move(to: trailCurve.0)
        p.addCurve(to: trailCurve.3, control1: trailCurve.1, control2: trailCurve.2)
        return p
    }()
    static let trailTable: [(len: CGFloat, pt: CGPoint)] = {
        var out: [(CGFloat, CGPoint)] = [(0, trailCurve.0)]
        var acc: CGFloat = 0, prev = trailCurve.0
        for i in 1...64 {
            let p = bez(trailCurve, CGFloat(i) / 64)
            acc += hypot(p.x - prev.x, p.y - prev.y); prev = p
            out.append((acc, p))
        }
        return out
    }()
    static let zee: Path = {
        var p = Path()
        p.move(to: CGPoint(x: -5, y: -5)); p.addLine(to: CGPoint(x: 5, y: -5))
        p.addLine(to: CGPoint(x: -5, y: 5)); p.addLine(to: CGPoint(x: 5, y: 5))
        return p
    }()
    static let workCircle = Path(ellipseIn: CGRect(x: -102, y: -108, width: 204, height: 204))
    static let workLength: CGFloat = 2 * .pi * 102

    // MARK: colours
    static func rgb(_ hex: UInt32, _ a: Double = 1) -> RiceRGBA {
        RiceRGBA(r: CGFloat((hex >> 16) & 0xFF) / 255, g: CGFloat((hex >> 8) & 0xFF) / 255,
                 b: CGFloat(hex & 0xFF) / 255, a: CGFloat(a))
    }
    static let ink = rgb(0x2B1D05)
    // v3: the grain is pure white; all the colour lives in the rim and the light around it.
    static let fill = RiceGradient([(rgb(0xFFFFFF), 0), (rgb(0xFFFFFF), 0.9),
                                       (rgb(0xFFFCF4), 1)])
    /// Pearl shade: a whisper of warm grey low on the far side, so white still reads as round.
    static let pearl = RiceGradient([(rgb(0xE9E2D2, 0), 0), (rgb(0xE9E2D2, 0), 0.55),
                                        (rgb(0xE6DCC6, 0.55), 1)])
    static let rimGrad = RiceGradient([(rgb(0xFFF2A8), 0), (rgb(0xFFD23C), 0.35),
                                          (rgb(0xF2A900), 1)])
    static let halo = RiceGradient([(rgb(0xFFE94D, 0.9), 0), (rgb(0xFFDD33, 0.55), 0.5),
                                       (rgb(0xFFD400, 0.18), 0.74), (rgb(0xFFD400, 0), 1)])
    static let pool = RiceGradient([(rgb(0xFFD84A, 0.55), 0), (rgb(0xFFCC22, 0.18), 0.55),
                                       (rgb(0xFFCC22, 0), 1)])
    static let moteGrad = RiceGradient([(rgb(0xFFF3B0, 1), 0), (rgb(0xFFF3B0, 0.55), 0.45),
                                           (rgb(0xFFF3B0, 0), 1)])

    /// A blurred glow of the grain's outline (a fill, or a stroke of `stroke` width), as a sprite.
    private static func glow(_ ctx: RiceCanvas, _ key: String, sigma: CGFloat, color: RiceRGBA,
                             stroke: CGFloat? = nil, insideBody: Bool = false) {
        let image = RiceSprites.image(key, rect: RiceSprites.glowRect, scale: ctx.pixelScale, blur: sigma,
                                      clip: insideBody ? body : nil) { c in
            if let stroke { c.stroke(body, with: .color(color), style: StrokeStyle(lineWidth: stroke, lineJoin: .round)) }
            else { c.fill(body, with: .color(color)) }
        }
        guard let image else { return }
        ctx.draw(image, in: RiceSprites.glowRect)
    }

    /// An SVG-style radial gradient on an ellipse, drawn once as a sprite.
    private static func ellipseSprite(_ ctx: RiceCanvas, _ key: String, center: CGPoint, rx: CGFloat, ry: CGFloat,
                                      gradient: RiceGradient) {
        let rect = CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2)
        guard let image = RiceSprites.image(key, rect: rect, scale: ctx.pixelScale, build: { c in
            ellipseGradient(c, center: center, rx: rx, ry: ry, gradient: gradient)
        }) else { return }
        ctx.draw(image, in: rect)
    }

    /// The white grain with its pearl shade, and the gold rim line, as sprites.
    private static let grainRect = bodyBox.insetBy(dx: -4, dy: -4)
    private static func grain(_ ctx: RiceCanvas) {
        guard let image = RiceSprites.image("grain", rect: grainRect, scale: ctx.pixelScale, build: { c in
            ellipseGradient(c, clip: body, center: CGPoint(x: bodyBox.minX + 0.42 * bodyBox.width, y: bodyBox.minY + 0.36 * bodyBox.height),
                            rx: 0.78 * bodyBox.width, ry: 0.78 * bodyBox.height, gradient: fill)
            ellipseGradient(c, clip: body, center: CGPoint(x: -14, y: -30),
                            rx: 0.86 * bodyBox.width, ry: 0.78 * bodyBox.height, gradient: pearl)
        }) else { return }
        ctx.draw(image, in: grainRect)
    }
    private static func rimLine(_ ctx: RiceCanvas) {
        guard let image = RiceSprites.image("rimline", rect: grainRect, scale: ctx.pixelScale, build: { c in
            c.stroke(body, with: .linearGradient(rimGrad, startPoint: CGPoint(x: bodyBox.minX, y: bodyBox.minY),
                                                 endPoint: CGPoint(x: bodyBox.maxX, y: bodyBox.maxY)), lineWidth: 4.6)
        }) else { return }
        ctx.draw(image, in: grainRect)
    }

    static func rippleColor(_ c: RiceRippleColor) -> RiceRGBA {
        switch c { case .gold: return rgb(0xFFD85C); case .amber: return rgb(0xFFB938); case .white: return rgb(0xFFFFFF) }
    }

    // MARK: draw

    /// `box` is the lab's square size in points (the lab's "52 px"); the canvas may be larger
    /// so the aura fades out instead of being cut at the box edge.
    static func draw(_ ctx: RiceCanvas, size: CGSize, box: CGFloat, motion m: RiceMotion, frame v: RiceFrame) {
        let k = box / 320
        var base = ctx
        base.translateBy(x: size.width / 2 - 160 * k, y: size.height / 2 - 160 * k)
        base.scaleBy(x: k, y: k)

        let r = v.reduced, M: Double = r ? 0 : 1, Lf = m.settings.light, t = v.t
        let g = min(1.25, v.glow), ab = sin(t * 1.1) * M          // aura breath, ~5.7 s
        let tx = 160 + v.x * 3, ty = 168 + v.y * 3

        // Light pool on the ground: stays put when the grain rises, dims with height.
        let lift = max(0, -m.v(.hop))
        let gy0 = 168 + m.v(.poseY) * 3 + 116
        do {
            var c = base
            c.translateBy(x: 160 + m.v(.poseX) * 3, y: gy0)
            let s = 1.4 * (1 - lift * 0.03)
            c.scaleBy(x: s, y: s)
            c.opacity = RiceMotion.clamp01(g * 0.85 * Lf * (1 - lift * 0.05))
            ellipseSprite(c, "pool", center: .zero, rx: 60, ry: 10, gradient: pool)
        }

        // Pose: the grain itself.
        var pose = base
        pose.translateBy(x: tx, y: ty)
        pose.rotate(by: .degrees(v.angle))
        pose.scaleBy(x: 1.4, y: 1.4)

        // Grain-shaped ripples.
        for rp in m.ripples {
            let kk = RiceMotion.clamp01((t - rp.t0) / rp.dur)
            let sc: Double, o: Double
            if rp.inward { sc = 1 + rp.size * (1 - RiceMotion.inOut(kk)); o = rp.str * RiceMotion.bump(kk) }
            else { sc = 1.04 + rp.size * 0.8 * RiceMotion.outC(kk); o = rp.str * pow(1 - kk, 2.6) * min(1, kk * 12) }
            guard o > 0.003 else { continue }
            var c = pose
            c.translateBy(x: 0, y: -7); c.scaleBy(x: sc, y: sc); c.translateBy(x: 0, y: 7)
            c.opacity = o * Lf
            c.blendMode = .plusLighter   // light only adds: a ripple never reads as a dark ring
            c.blurred(radius: 4) { l in
                l.stroke(body, with: .color(rippleColor(rp.col)), style: StrokeStyle(lineWidth: 9 / sc, lineJoin: .round))
            }
        }

        // Approval: amber grain-shaped ring that breathes (3.2 s).
        let pa = RiceMotion.clamp01(m.prop(.approval))
        if pa > 0.005 {
            var c = pose
            let s = 1.25 + (r ? 0 : 0.025 * sin(t * 1.95))
            c.translateBy(x: 0, y: -7); c.scaleBy(x: s, y: s); c.translateBy(x: 0, y: 7)
            c.opacity = pa * (r ? 0.6 : 0.45 + 0.25 * sin(t * 1.95))
            glow(c, "ring", sigma: 3.2, color: rgb(0xFFB21A), stroke: 8)
            if let line = RiceSprites.image("ringline", rect: grainRect, scale: c.pixelScale, build: { l in
                l.stroke(body, with: .color(rgb(0xFFCF4D)), lineWidth: 2.4)
            }) { c.draw(line, in: grainRect) }
        }

        // Aura.
        do {
            var c = pose; c.opacity = RiceMotion.clamp01(g * 0.75 * Lf * (1 - 0.08 * ab))
            ellipseSprite(c, "halo-outer", center: CGPoint(x: 0, y: -6), rx: 110, ry: 116, gradient: halo)
            var h = pose
            let hs = (0.9 + 0.1 * g) * (1 + 0.025 * ab)
            h.scaleBy(x: hs, y: hs)
            h.opacity = RiceMotion.clamp01(g * Lf * (1 + 0.1 * ab))
            ellipseSprite(h, "halo-inner", center: CGPoint(x: 0, y: -6), rx: 90, ry: 102, gradient: halo)
        }

        // Working: thin arc of light orbiting the grain, drawn over the aura so it reads.
        var back = base
        back.translateBy(x: tx, y: ty); back.scaleBy(x: 1.4, y: 1.4)
        let pw = RiceMotion.clamp01(m.prop(.working))
        if pw > 0.005 {
            let len = r ? 28 : 24 + 10 * sin(t * 1.3)
            let off = r ? -12 : -(t * 62).truncatingRemainder(dividingBy: 100)
            let L = workLength
            let dash = [CGFloat(len) / 100 * L, CGFloat(100 - len) / 100 * L]
            let phase = CGFloat(positiveMod(off, 100)) / 100 * L
            var a = back; a.opacity = pw * 0.08
            a.stroke(workCircle, with: .color(rgb(0xFFD21A)), lineWidth: 2.5)
            // Soft glow without a live blur: a wide faint stroke under a narrower one.
            var gl = back; gl.opacity = pw * 0.7 * Lf
            gl.stroke(workCircle, with: .color(rgb(0xFFD21A).opacity(0.35)), style: StrokeStyle(lineWidth: 13, lineCap: .round, dash: dash, dashPhase: phase))
            gl.stroke(workCircle, with: .color(rgb(0xFFD21A).opacity(0.7)), style: StrokeStyle(lineWidth: 8, lineCap: .round, dash: dash, dashPhase: phase))
            var cr = back; cr.opacity = pw * 0.95
            cr.stroke(workCircle, with: .color(rgb(0xFFF3B0)), style: StrokeStyle(lineWidth: 3.6, lineCap: .round, dash: dash, dashPhase: phase))
        }

        // Shape (squashed from the bottom of the grain).
        var shape = pose
        shape.translateBy(x: 0, y: G); shape.scaleBy(x: v.sx, y: v.sy); shape.translateBy(x: 0, y: -G)
        do {
            var bloom = shape; bloom.opacity = RiceMotion.clamp01((0.3 + g * 0.65) * Lf * (1 + 0.06 * ab))
            glow(bloom, "bloom", sigma: 14, color: rgb(0xFFC70D))
            var rg = shape; rg.opacity = RiceMotion.clamp01((0.55 + g * 0.45) * (0.7 + 0.3 * Lf))
            glow(rg, "rimglow", sigma: 5, color: rgb(0xFFC20F), stroke: 12)
            // Body fill: white, lit from the upper left, with a pearl shade.
            grain(shape)
            // A thin line of gold light just inside the rim, so the glow reads as coming from within.
            var inner = shape
            inner.opacity = 0.22 + min(g, 1) * 0.3
            glow(inner, "inner", sigma: 3, color: rgb(0xFFD64D), stroke: 7, insideBody: true)
            rimLine(shape)
            // Rim light pass: light sliding over glass.
            if let rim = m.rim {
                let kk = (t - rim.t0) / rim.dur
                let off = -(rim.p0 + rim.span * RiceMotion.inOut(kk))
                let o = rim.str * pow(RiceMotion.bump(kk), 0.7) * Lf
                if o > 0.003 {
                    let L = bodyLength
                    let dash = [CGFloat(rim.len) / 100 * L, CGFloat(100 - rim.len) / 100 * L]
                    let phase = CGFloat(positiveMod(off, 100)) / 100 * L
                    var gl = shape; gl.opacity = o * 0.9
                    gl.stroke(body, with: .color(rgb(0xFFF1B8).opacity(0.35)), style: StrokeStyle(lineWidth: 14, lineCap: .round, dash: dash, dashPhase: phase))
                    gl.stroke(body, with: .color(rgb(0xFFF1B8).opacity(0.7)), style: StrokeStyle(lineWidth: 9, lineCap: .round, dash: dash, dashPhase: phase))
                    var cr = shape; cr.opacity = o
                    cr.stroke(body, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: dash, dashPhase: phase))
                }
            }
            // Glass highlight (follows the gaze a little, the other way) and a small sparkle dot.
            var hl = shape
            hl.translateBy(x: -v.ex * 0.18, y: -v.ey * 0.18)
            hl.translateBy(x: -22, y: -52); hl.rotate(by: .degrees(-30))
            hl.opacity = 0.9
            hl.fill(Path(ellipseIn: CGRect(x: -12, y: -7, width: 24, height: 14)),
                    with: .radialGradient(RiceGradient(colors: [.white, rgb(0xFFFFFF, 0)]), center: .zero, startRadius: 2, endRadius: 13))
        }

        // Eyes, cheeks, happy and sleeping lids (not squashed; positioned with sx/sy like the lab).
        let shut = max(v.smile, v.sleep)
        let wide = min(1.12, 0.9 + v.eyeOpen * 0.1)
        // On a white grain a cross-fade shows grey eyes, so the eye closes by height
        // and the curved lines only appear once it is nearly shut.
        let ery = max(1.6, 11 * v.eyeOpen * max(0.14, 1 - shut))
        let lineIn = RiceMotion.clamp01((shut - 0.45) / 0.4)
        let eyeOut = shut < 0.8 ? 1 : RiceMotion.clamp01((1 - shut) / 0.2)
        let ey0 = Double(G) + (6 - Double(G)) * v.sy
        for cx in [-17.0, 17.0] {
            let x = cx * v.sx + v.ex, y = ey0 + v.ey
            // cheek
            var ch = pose; ch.opacity = min(0.8, v.blush)
            let chx = cx * 2 * v.sx + v.ex * 0.4, chy = Double(G) + (26 - Double(G)) * v.sy + v.ey * 0.3
            ch.fill(Path(ellipseIn: CGRect(x: chx - 9.5, y: chy - 5.5, width: 19, height: 11)), with: .color(rgb(0xFF9F45)))
            // happy ^ ^
            if v.smile > 0.005 && lineIn > 0.005 {
                var a = pose; a.opacity = lineIn * v.smile / max(shut, 0.001)
                var p = Path(); p.move(to: CGPoint(x: x - 8, y: y + 3)); p.addQuadCurve(to: CGPoint(x: x + 8, y: y + 3), control: CGPoint(x: x, y: y - 9))
                a.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
            // sleeping lid
            let lidO = lineIn * v.sleep * (1 - v.smile) / max(shut, 0.001)
            if lidO > 0.005 {
                var a = pose; a.opacity = lidO
                var p = Path(); p.move(to: CGPoint(x: x - 7.5, y: y + 1)); p.addQuadCurve(to: CGPoint(x: x + 7.5, y: y + 1), control: CGPoint(x: x, y: y + 4.5))
                a.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
            }
            // eye + catchlight
            if eyeOut > 0.005 {
                var e = pose; e.opacity = eyeOut
                let rx = 7.5 * wide
                let eye = Path(ellipseIn: CGRect(x: x - rx, y: y - ery, width: rx * 2, height: ery * 2))
                e.fill(eye, with: .color(ink))
                if v.eyeOpen > 0.3 {
                    // Kept inside the eye so a half-closed blink never shows a white blob.
                    let cy = y - ery * 0.38
                    var cl = e; cl.clip(to: eye)
                    cl.fill(Path(ellipseIn: CGRect(x: x - 2.4 - 2.6, y: cy - 2.6, width: 5.2, height: 5.2)), with: .color(.white))
                }
            }
        }

        // Front props (not rotated with the body).
        var front = base
        front.translateBy(x: tx, y: ty); front.scaleBy(x: 1.4, y: 1.4)

        // Glow motes: few, slow, long-lived.
        for mo in m.motes {
            let age = t - mo.t0, kk = age / mo.life
            let o = pow(RiceMotion.bump(kk), 0.8) * 0.85 * Lf
            guard o > 0.003 else { continue }
            let cx = mo.x + sin(age * 1.1 + mo.ph) * 3, cy = mo.y + mo.vy * age, rr = mo.r * (1 - 0.25 * kk)
            var c = front; c.opacity = o
            let R = rr + 3.2   // the lab blurs each mote by 1.6
            c.fill(Path(ellipseIn: CGRect(x: cx - R, y: cy - R, width: R * 2, height: R * 2)),
                   with: .radialGradient(moteGrad, center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: R))
        }

        // Thinking: one round bubble, the dot trio breathing in turn.
        let pt = m.prop(.thinking)
        if pt > 0.01 {
            var c = front; popTransform(&c, ax: -58, ay: -75, s: pt)
            softCircle(c, CGPoint(x: -80, y: -92), 22, rgb(0xFFD21A), 0.22)
            c.fill(circle(-58, -75, 4.5), with: .color(.white)); c.stroke(circle(-58, -75, 4.5), with: .color(rgb(0xFFD21A)), lineWidth: 1.6)
            c.fill(circle(-80, -92, 17), with: .color(.white)); c.stroke(circle(-80, -92, 17), with: .color(rgb(0xFFD21A)), lineWidth: 1.8)
            for i in 0..<3 {
                let kk = positiveMod(t * 0.42 - Double(i) * 0.16, 1)
                let b = r ? 0.6 : RiceMotion.bump(RiceMotion.clamp01(kk * 2.4))
                let dx = -87.5 + Double(i) * 7.5
                var d = c; d.opacity = 0.3 + 0.7 * b
                d.fill(circle(dx, -92, 2.7 * (1 + 0.22 * b)), with: .color(rgb(0xD29A12)))
            }
        }
        // Approval: round "!" ring at the shoulder.
        let pab = m.prop(.approval) * (1 + 0.12 * m.v(.tip))
        if pab > 0.01 {
            var c = front; popTransform(&c, ax: 60, ay: -80, s: pab)
            softCircle(c, CGPoint(x: 60, y: -80), 17, rgb(0xFFB21A), 0.35)
            c.fill(circle(60, -80, 12), with: .color(rgb(0xFFC22E)))
            var p = Path(); p.move(to: CGPoint(x: 60, y: -86)); p.addLine(to: CGPoint(x: 60, y: -79.5))
            c.stroke(p, with: .color(rgb(0x4A3200)), style: StrokeStyle(lineWidth: 3.8, lineCap: .round))
            c.fill(circle(60, -73.6, 2.1), with: .color(rgb(0x4A3200)))
        }
        // Done: soft round check.
        let pd = m.v(.check)
        if pd > 0.01 {
            var c = front; popTransform(&c, ax: 60, ay: -80, s: pd)
            softCircle(c, CGPoint(x: 60, y: -80), 17, rgb(0xFFD21A), 0.3)
            c.fill(circle(60, -80, 12), with: .color(rgb(0xFFD84A)))
            var p = Path(); p.move(to: CGPoint(x: 54.5, y: -80)); p.addLine(to: CGPoint(x: 58.3, y: -76)); p.addLine(to: CGPoint(x: 65.3, y: -84))
            c.stroke(p, with: .color(rgb(0x4A3200)), style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
        }
        // Resting: one soft z at a time.
        let prr = RiceMotion.clamp01(m.prop(.resting))
        if r && prr > 0.5 {
            var c = front; c.translateBy(x: 36, y: -54); c.scaleBy(x: 1.2, y: 1.2); c.opacity = 0.8
            c.stroke(zee, with: .color(rgb(0xFFF1B0)), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
        } else if !r {
            for z in m.zs {
                let kk = (t - z.t0) / z.dur
                let o = pow(RiceMotion.bump(kk), 0.8) * 0.85 * prr
                guard o > 0.003 else { continue }
                var c = front
                c.translateBy(x: 30 + 4 * sin(kk * 3), y: -36 - 30 * RiceMotion.outC(kk))
                let s = (0.75 + 0.35 * kk) * 1.2
                c.scaleBy(x: s, y: s); c.opacity = o
                c.stroke(zee, with: .color(rgb(0xFFF1B0)), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
            }
        }

        // Sending trail and file tile live in the character's base frame (160, 168) x1.4.
        var world = base
        world.translateBy(x: 160, y: 168); world.scaleBy(x: 1.4, y: 1.4)
        if let T = m.trail, !r {
            let kk = (t - T.t0) / T.dur
            let head = RiceMotion.outC(min(1, kk / 0.8))
            let tail = max(head - 0.34, RiceMotion.inOut(RiceMotion.clamp01((kk - 0.12) / 0.88)))
            var c = world; c.translateBy(x: T.ox, y: T.oy); c.opacity = Lf
            drawTrail(c, head: head, tail: tail, orbOpacity: kk < 0.6 ? 1 : max(0, (1 - kk) / 0.4))
        } else if r && m.prop(.sending) > 0.5 {
            var c = world; c.translateBy(x: v.x * 3 / 1.4 + 46, y: v.y * 3 / 1.4 - 12); c.opacity = 0.5
            drawTrail(c, head: 1, tail: 0, orbOpacity: 1)
        }
        if let f = m.fileNow(), m.v(.fileA) > 0.01 {
            var c = world
            c.translateBy(x: f.x, y: f.y); c.rotate(by: .degrees(f.rot)); c.scaleBy(x: f.s, y: f.s)
            c.opacity = RiceMotion.clamp01(f.o * m.v(.fileA))
            softCircle(c, .zero, 22, rgb(0xFFD21A), 0.28)
            let tile = Path(roundedRect: CGRect(x: -11, y: -14, width: 22, height: 28), cornerRadius: 6)
            c.fill(tile, with: .color(rgb(0xFFFBE8)))
            c.stroke(tile, with: .color(rgb(0xFFC400)), lineWidth: 2.2)
            var p = Path()
            p.move(to: CGPoint(x: -5, y: -3)); p.addLine(to: CGPoint(x: 5, y: -3))
            p.move(to: CGPoint(x: -5, y: 4)); p.addLine(to: CGPoint(x: 2, y: 4))
            c.stroke(p, with: .color(rgb(0xE0A800)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        }
    }

    // MARK: helpers

    /// An SVG objectBoundingBox radial gradient on an ellipse: a circle gradient stretched to rx/ry.
    private static func ellipseGradient(_ ctx: RiceCanvas, clip: Path? = nil, center: CGPoint, rx: CGFloat, ry: CGFloat, gradient: RiceGradient) {
        var c = ctx
        if let clip { c.clip(to: clip) }
        c.translateBy(x: center.x, y: center.y)
        c.scaleBy(x: 1, y: ry / rx)
        let rect = CGRect(x: -rx, y: -rx, width: rx * 2, height: rx * 2)
        c.fill(Path(ellipseIn: rect), with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: rx))
    }

    /// The lab's soft halos behind props (a circle blurred by 3.2), as a cheap radial gradient.
    private static func softCircle(_ ctx: RiceCanvas, _ c: CGPoint, _ radius: CGFloat, _ color: RiceRGBA, _ opacity: Double) {
        let R = radius + 6.4
        let edge = radius / R
        let gr = RiceGradient([(color.opacity(opacity), 0),
                                  (color.opacity(opacity * 0.85), max(0, edge - 0.25)),
                                  (color.opacity(opacity * 0.5), edge),
                                  (color.opacity(0), 1)])
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2)),
                 with: .radialGradient(gr, center: c, startRadius: 0, endRadius: R))
    }

    private static func drawTrail(_ c: RiceCanvas, head: Double, tail: Double, orbOpacity: Double) {
        let L = trailTable.last!.len
        let dashLen = max(0, CGFloat(head - tail)) * L
        let dash = [dashLen, 2 * L]
        let phase = dashLen + 2 * L - CGFloat(tail) * L   // the dash starts at `tail`
        c.blurred(radius: 3.2) { l in
            l.stroke(trail, with: .color(rgb(0xFFD21A)), style: StrokeStyle(lineWidth: 8, lineCap: .round, dash: dash, dashPhase: phase))
        }
        c.stroke(trail, with: .color(rgb(0xFFF5CC)), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, dash: dash, dashPhase: phase))
        let p = trailPoint(CGFloat(head) * L)
        var o = c; o.opacity = orbOpacity
        softCircle(o, p, 13, rgb(0xFFD84A), 0.55)
        o.fill(circle(p.x, p.y, 5.2), with: .color(.white))
    }

    private static func trailPoint(_ len: CGFloat) -> CGPoint {
        let tbl = trailTable
        guard len > 0 else { return tbl[0].pt }
        for i in 1..<tbl.count where tbl[i].len >= len {
            let a = tbl[i - 1], b = tbl[i]
            let f = (len - a.len) / max(0.0001, b.len - a.len)
            return CGPoint(x: a.pt.x + (b.pt.x - a.pt.x) * f, y: a.pt.y + (b.pt.y - a.pt.y) * f)
        }
        return tbl.last!.pt
    }

    private static func popTransform(_ c: inout RiceCanvas, ax: CGFloat, ay: CGFloat, s: Double) {
        c.translateBy(x: ax, y: ay); c.scaleBy(x: s, y: s); c.translateBy(x: -ax, y: -ay)
        c.opacity = RiceMotion.clamp01(s)
    }

    private static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    private static func positiveMod(_ a: Double, _ b: Double) -> Double {
        let m = a.truncatingRemainder(dividingBy: b)
        return m < 0 ? m + b : m
    }

    private static func bez(_ c: (CGPoint, CGPoint, CGPoint, CGPoint), _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, d = 3 * u * t * t, e = t * t * t
        return CGPoint(x: a * c.0.x + b * c.1.x + d * c.2.x + e * c.3.x,
                       y: a * c.0.y + b * c.1.y + d * c.2.y + e * c.3.y)
    }

    private static func curveLength(_ curves: [(CGPoint, CGPoint, CGPoint, CGPoint)]) -> CGFloat {
        var total: CGFloat = 0
        for c in curves {
            var prev = c.0
            for i in 1...64 {
                let p = bez(c, CGFloat(i) / 64)
                total += hypot(p.x - prev.x, p.y - prev.y); prev = p
            }
        }
        return total
    }
}

/// The mascot view. Costs nothing while `paused` (island hidden) and nothing
/// with Reduce Motion: frames only run while the mascot is alive.
///
/// Seed draws outside SwiftUI's update loop (measured in Seed Lab, Release):
/// - A TimelineView inside the notch re-laid out and re-diffed the whole notch
///   every frame; a layer-backed view on its own display link does not.
/// - Parts that never change shape are sprites in their own layers, so the
///   GPU, not this process, scales, rotates and blends them (RiceStage).
/// - The frame rate follows what moves (RiceMotion.pace): 60, 30 or 12 fps.
/// Workspace idle went from about 25% of a core to about 3%, the closed notch
/// from about 6% to under 1%.
struct RiceMascotView: NSViewRepresentable {
    let motion: RiceMotion
    /// Lab "px" size of the character's square.
    var box: CGFloat = 52
    var paused: Bool
    /// Bumped by the owner whenever an event or state change must be drawn
    /// while frames are stopped (Reduce Motion, paused).
    var revision: Int = 0

    func makeNSView(context: Context) -> RiceLayerView {
        RiceLayerView(motion: motion)
    }

    func updateNSView(_ view: RiceLayerView, context: Context) {
        view.configure(box: box, paused: paused, revision: revision)
    }
}

/// Draws Seed into its own layer. A display link ticks only while the motion
/// needs frames, at the rate the motion asks for; otherwise nothing runs.
final class RiceLayerView: NSView {
    private let motion: RiceMotion
    private var box: CGFloat = 52
    private var paused = true
    private var revision = -1
    private var link: CADisplayLink?
    /// Frames drawn since launch, read by the lab to check the frame rate.
    static var framesDrawn = 0

    private let stage = RiceStage()

    init(motion: RiceMotion) {
        self.motion = motion
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(stage.root)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // Not flipped: the stage flips its own geometry once (y down, like the painter).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }   // SwiftUI owns presses
    override var wantsUpdateLayer: Bool { true }

    func configure(box: CGFloat, paused: Bool, revision: Int) {
        let changed = box != self.box || paused != self.paused || revision != self.revision
        self.box = box; self.paused = paused; self.revision = revision
        if changed { redraw(); schedule() }
    }

    /// While the link runs, a change waits for its next tick, so a SwiftUI
    /// animation of Seed's size and the link never draw twice in one frame.
    private func redraw() {
        if link != nil { dirty = true } else { render() }
    }
    private var dirty = false

    /// Leaving the window stops the link (it retains this view until invalidated).
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        render(); schedule()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { redraw() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        render()
    }

    /// Runs the link only while something moves; the rate follows the motion.
    private func schedule() {
        let live = window != nil && !paused && motion.needsFrames
        if live, link == nil {
            let l = displayLink(target: self, selector: #selector(tick(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        } else if !live, let l = link {
            l.invalidate(); link = nil
        }
        if let link {
            let fps = Float((1 / motion.frameInterval).rounded())
            // Set only on a change: re-setting it every tick can make the link fire more often.
            if fps != linkFPS {
                linkFPS = fps
                link.preferredFrameRateRange = CAFrameRateRange(minimum: min(fps, 15), maximum: fps, preferred: fps)
            }
        } else {
            linkFPS = 0
        }
    }
    private var linkFPS: Float = 0
    private var lastFrame: CFTimeInterval = 0

    @objc private func tick(_ link: CADisplayLink) {
        // The rate is only a hint (other animations can drive the display faster):
        // skip ticks that come sooner than the motion asks for.
        let now = link.timestamp
        if !dirty, now - lastFrame < motion.frameInterval * 0.9 { return }
        lastFrame = now
        dirty = false
        render()
        schedule()
    }

    private func render() {
        guard window != nil, bounds.width > 0, bounds.height > 0 else { return }
        if !paused { motion.advance(to: Date().timeIntervalSinceReferenceDate) }
        stage.show(motion: motion, box: box, size: bounds.size, scale: window?.backingScaleFactor ?? 2)
        Self.framesDrawn += 1
    }
}

/// Seed as a small stack of layers. Each frame the painter runs against a
/// recorder: the parts that never change shape come back as sprites, which
/// only get a new transform and opacity here; everything else is one or two
/// small live bitmaps. Core Animation composites the stack on the GPU.
@MainActor
final class RiceStage {
    let root = CALayer()
    private var parts: [CALayer] = []

    init() {
        root.anchorPoint = .zero
        root.isGeometryFlipped = true
        root.masksToBounds = false
    }

    func show(motion: RiceMotion, box: CGFloat, size: CGSize, scale: CGFloat) {
        let w = Int((size.width * scale).rounded(.up)), h = Int((size.height * scale).rounded(.up))
        guard w > 0, h > 0 else { return }
        let recorder = RiceRecorder(width: w, height: h)
        RicePainter.draw(RiceCanvas(sink: recorder, height: size.height, scale: scale),
                         size: size, box: box, motion: motion, frame: motion.values())
        apply(recorder.finish(), size: size)
    }

    private func apply(_ items: [RiceRecorder.Item], size: CGSize) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.bounds = CGRect(origin: .zero, size: size)
        root.position = .zero
        while parts.count < items.count {
            let l = CALayer()
            l.anchorPoint = .zero
            l.contentsGravity = .resize
            l.actions = ["contents": NSNull(), "transform": NSNull(), "opacity": NSNull(), "bounds": NSNull(),
                         "position": NSNull(), "hidden": NSNull()]
            root.addSublayer(l)
            parts.append(l)
        }
        for (i, item) in items.enumerated() {
            let l = parts[i]
            l.isHidden = false
            switch item {
            case .live(let image):
                if l.contents as! CGImage? !== image { l.contents = image }
                l.bounds = CGRect(origin: .zero, size: size)
                l.setAffineTransform(.identity)
                l.opacity = 1
            case .sprite(let image, let spriteSize, let t, let o):
                if l.contents as! CGImage? !== image { l.contents = image }
                l.bounds = CGRect(origin: .zero, size: spriteSize)
                l.setAffineTransform(t)
                l.opacity = o
            }
            l.position = .zero
        }
        for l in parts.dropFirst(items.count) where !l.isHidden { l.isHidden = true }
        CATransaction.commit()
    }
}

/// Renders one frame of Seed to an image with Core Graphics, off screen. The
/// layer view and the lab's reference frames share it. No SwiftUI per frame.
@MainActor
enum RiceRender {
    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    static func image(motion: RiceMotion, box: CGFloat, size: CGSize, scale: CGFloat) -> CGImage? {
        let w = Int((size.width * scale).rounded(.up)), h = Int((size.height * scale).rounded(.up))
        guard w > 0, h > 0,
              let cg = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        cg.setShouldAntialias(true)
        cg.interpolationQuality = .medium
        let canvas = RiceCanvas(cg, height: size.height, scale: scale)
        RicePainter.draw(canvas, size: size, box: box, motion: motion, frame: motion.values())
        return cg.makeImage()
    }

    /// The same frame through the layer stack, flattened, so the lab can check it matches.
    static func layeredImage(motion: RiceMotion, box: CGFloat, size: CGSize, scale: CGFloat) -> CGImage? {
        let stage = RiceStage()
        stage.show(motion: motion, box: box, size: size, scale: scale)
        let w = Int((size.width * scale).rounded(.up)), h = Int((size.height * scale).rounded(.up))
        guard let cg = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                 bitmapInfo: RiceSprites.bitmapInfo) else { return nil }
        // render(in:) draws the stack upside down compared with the screen; flip it back.
        cg.translateBy(x: 0, y: CGFloat(h))
        cg.scaleBy(x: scale, y: -scale)
        stage.root.render(in: cg)
        return cg.makeImage()
    }
}
#endif
