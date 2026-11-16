import AppKit
import ClimbCore

/// Both the transparent desktop windows and the offscreen GIF use these drawing paths.
enum SpiderRenderer {
    static func body(_ hero: ClimbEngine, in c: CGContext) {
        let view = hero.projection
        c.saveGState(); defer { c.restoreGState() }
        c.scaleBy(x: view.scale, y: view.scale)
        let relief = max(0, view.depth)
        c.setShadow(offset: CGSize(width: 1 + 3.5 * relief, height: -1 - 3.8 * relief),
                    blur: 1.5 + 3.5 * relief, color: NSColor.black.withAlphaComponent(0.26 - 0.06 * relief).cgColor)
        c.beginTransparencyLayer(auxiliaryInfo: nil)
        SpiderArt.draw(in: c, phase: hero.phase, time: hero.elapsed, facing: hero.facing, angle: hero.swingAngle,
                       wristSide: hero.wristSide, grip: hero.gripOffset, aim: hero.throwOffset,
                       progress: hero.poseProgress, depth: view.depth)
        c.endTransparencyLayer()
    }

    static func silk(_ strand: WebStrand, scale: CGFloat, in c: CGContext) {
        let a = strand.hand, b = strand.tip
        let dx = b.x - a.x, dy = b.y - a.y, distance = hypot(dx, dy)
        guard distance > 0.3 else { return }
        let nx = -dy / distance, ny = dx / distance
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - (strand.attached ? 1 : min(5, distance / 9)))
        func shift(_ p: CGPoint, _ w: CGFloat) -> CGPoint { CGPoint(x: p.x + nx * w, y: p.y + ny * w) }
        func ribbon(_ near: CGFloat, _ far: CGFloat, _ color: NSColor) {
            let middle = (near + far) / 2
            c.beginPath(); c.move(to: shift(a, near))
            c.addQuadCurve(to: shift(b, far), control: shift(mid, middle))
            c.addLine(to: shift(b, -far)); c.addQuadCurve(to: shift(a, -near), control: shift(mid, -middle))
            c.closePath(); c.setFillColor(color.cgColor); c.fillPath()
        }
        ribbon(1.65 * scale, 0.86, .rgb(0x26364C, alpha: 0.8))
        ribbon(0.85 * scale, 0.40, .rgb(0xEDFAFF))
        if strand.attached {
            for (w, col) in [(2.4, NSColor.rgb(0x283B50, alpha: 0.75)), (1, NSColor.rgb(0xE8F7FF))] {
                c.beginPath()
                for (x, y) in [(-3,2), (3,2), (1,-3)] {
                    c.move(to: b); c.addLine(to: CGPoint(x: b.x + CGFloat(x), y: b.y + CGFloat(y)))
                }
                c.setStrokeColor(col.cgColor); c.setLineWidth(w); c.setLineCap(.round); c.strokePath()
            }
        }
    }
}
