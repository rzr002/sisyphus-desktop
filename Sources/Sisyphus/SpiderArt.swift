import AppKit
import ClimbCore

/// A jointed, Retina vector character. The hanging pose shares its wrist
/// coordinate with the simulation, so the web stays attached on every frame.
enum SpiderArt {
    private static let ink = NSColor.rgb(0x17243B).cgColor
    private static let blue = NSColor.rgb(0x225085).cgColor
    private static let blueLight = NSColor.rgb(0x3884B6).cgColor
    private static let red = NSColor.rgb(0xE34645).cgColor
    private static let redDark = NSColor.rgb(0xAB3349).cgColor
    private static let silk = NSColor.rgb(0x843449).cgColor

    static func draw(in c: CGContext, phase: Phase, time: Double, facing: CGFloat, angle: CGFloat) {
        let walking = phase == .searching || phase == .walking
        let climbing = [.climbing, .reaching, .traversing].contains(phase)
        let tethered = phase.usesWeb
        let wave = CGFloat(sin(time * (walking ? 8.5 : 6.2)))
        let pivot = CharacterPanel.pivot
        c.saveGState()
        defer { c.restoreGState() }
        c.translateBy(x: pivot.x, y: pivot.y)
        if tethered {
            c.translateBy(x: 0, y: 37); c.rotate(by: max(-0.26, min(0.26, angle * 0.32))); c.translateBy(x: 0, y: -37)
        } else if walking {
            c.translateBy(x: 0, y: -5 + 1.5 * abs(wave))
        } else if phase == .recovering {
            c.translateBy(x: 0, y: -13); c.scaleBy(x: 1.03, y: 0.76)
        }
        c.scaleBy(x: facing, y: 1)
        c.setLineCap(.round); c.setLineJoin(.round)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        func stroke(_ points: [CGPoint], _ color: CGColor, _ width: CGFloat) {
            c.beginPath(); c.addLines(between: points); c.setStrokeColor(color); c.setLineWidth(width); c.strokePath()
        }
        func shape(_ path: CGPath, _ fill: CGColor, _ outline: CGFloat = 1.6) {
            c.addPath(path); c.setFillColor(fill); c.setStrokeColor(ink); c.setLineWidth(outline); c.drawPath(using: .fillStroke)
        }
        func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: CGColor) {
            shape(CGPath(ellipseIn: CGRect(x: x, y: y, width: w, height: h), transform: nil), color, 1.3)
        }
        func limb(_ root: CGPoint, _ joint: CGPoint, _ tip: CGPoint, _ width: CGFloat, _ boot: Bool) {
            stroke([root, joint, tip], ink, width + 2.6)
            stroke([root, joint, tip], boot ? blue : redDark, width)
            let cuff = p(joint.x * 0.55 + tip.x * 0.45, joint.y * 0.55 + tip.y * 0.45)
            stroke([cuff, tip], red, width + 0.2)
        }
        let leftHand: CGPoint, rightHand: CGPoint, leftKnee: CGPoint, rightKnee: CGPoint
        let leftFoot: CGPoint, rightFoot: CGPoint
        if tethered {
            leftHand = p(0, 37)
            rightHand = phase == .webCasting ? p(21, 12) : p(18, 8 + wave * 1.4)
            leftKnee = p(-12, -19); rightKnee = p(17, -13)
            leftFoot = p(-6, -32); rightFoot = p(20, -23)
        } else if climbing {
            leftHand = p(-19, 25 + wave * 6); rightHand = p(19, 25 - wave * 6)
            leftKnee = p(-14, -18 - wave * 4); rightKnee = p(14, -18 + wave * 4)
            leftFoot = p(-12, -27 - wave * 4); rightFoot = p(12, -27 + wave * 4)
        } else if [.falling, .jumping, .dragging].contains(phase) {
            leftHand = p(-23, 17 - wave * 2); rightHand = p(22, 21 + wave * 2)
            leftKnee = p(-13, -19); rightKnee = p(11, -17)
            leftFoot = p(-18, -27); rightFoot = p(8, -32)
        } else {
            let stride = walking ? wave : 0
            leftHand = p(-13 - stride * 4, -9); rightHand = p(13 + stride * 4, -8)
            leftKnee = p(-6 + stride * 5, -21); rightKnee = p(6 - stride * 5, -21)
            leftFoot = p(-7 + stride * 9, -31 + max(0, stride) * 4)
            rightFoot = p(8 - stride * 9, -31 + max(0, -stride) * 4)
        }
        limb(p(-4,-9), leftKnee, leftFoot, 6.2, true)
        limb(p(4,-9), rightKnee, rightFoot, 6.8, true)
        stroke([leftFoot, p(leftFoot.x - 3, leftFoot.y - 1)], ink, 8)
        stroke([leftFoot, p(leftFoot.x - 3, leftFoot.y - 1)], redDark, 5.8)
        stroke([rightFoot, p(rightFoot.x + 3, rightFoot.y - 1)], ink, 8)
        stroke([rightFoot, p(rightFoot.x + 3, rightFoot.y - 1)], red, 5.8)
        let torso = CGMutablePath()
        torso.move(to: p(-9, 5)); torso.addQuadCurve(to: p(9,5), control: p(0,10))
        torso.addQuadCurve(to: p(6,-13), control: p(12,-3))
        torso.addQuadCurve(to: p(-6,-13), control: p(0,-17))
        torso.addQuadCurve(to: p(-9,5), control: p(-11,-3)); torso.closeSubpath()
        shape(torso, climbing ? blue : red)
        stroke([p(-7,-6),p(-6,-11),p(4,-12)], climbing ? blueLight : blue, 2)
        // Eight legs surrounding the tiny emblem keep it legible in the back view.
        let emblem = climbing ? red : ink
        for side: CGFloat in [-1, 1] {
            for k in 0..<4 {
                let dy = CGFloat(k)
                stroke([p(0,-1-dy),p(side * 3,-dy),p(side * (4 + dy * 0.55),2 - dy * 2.7)], emblem, 0.85)
            }
        }
        stroke([p(0,-1),p(0,-5)], emblem, 2.6)
        let raised = tethered || climbing
        limb(p(-7,2), p(raised ? -22 : -14, raised ? 19 : 0), leftHand, 5.1, false)
        limb(p(7,2), p(raised ? 21 : 14, raised ? 13 : 0), rightHand, 5.3, false)
        let head = CGMutablePath()
        head.move(to: p(0,4))
        head.addCurve(to: p(-16.5,20), control1: p(-5,4), control2: p(-15,11))
        head.addCurve(to: p(0,34), control1: p(-19,30), control2: p(-10,35))
        head.addCurve(to: p(16.5,20), control1: p(10,35), control2: p(19,30))
        head.addCurve(to: p(0,4), control1: p(15,11), control2: p(5,4)); head.closeSubpath()
        shape(head, red, 2)
        c.saveGState(); c.addPath(head); c.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor.rgb(0xFF7060).cgColor, red, redDark] as CFArray, locations: [0,0.52,1])!
        c.drawLinearGradient(gradient, start: p(-13,34), end: p(13,6), options: [.drawsBeforeStartLocation,.drawsAfterEndLocation])
        let hub = p(climbing ? 0 : 1, climbing ? 21 : 16)
        for outer in [p(-10,3),p(0,1),p(11,4),p(-19,16),p(19,16),p(-19,27),p(19,27),p(-11,37),p(0,37),p(11,37)] {
            stroke([hub,outer], silk, 0.66)
        }
        for y: CGFloat in [10, 17, 24, 30] {
            let curve = CGMutablePath(); curve.move(to: p(-18,y + 2))
            for j in 0..<4 {
                let x = CGFloat(j) * 9 - 18
                curve.addQuadCurve(to: p(x + 9,y + 2), control: p(x + 4.5,y - 1))
            }
            c.addPath(curve); c.setStrokeColor(silk); c.setLineWidth(0.65); c.strokePath()
        }
        if !climbing {
            for side: CGFloat in [-1,1] {
                c.saveGState(); c.scaleBy(x: side, y: 1)
                let eye = CGMutablePath()
                eye.move(to: p(2.4,18.7)); eye.addQuadCurve(to: p(14.5,25), control: p(8,20))
                eye.addQuadCurve(to: p(10.2,13.2), control: p(13.8,17))
                eye.addQuadCurve(to: p(2.4,18.7), control: p(4,11)); eye.closeSubpath()
                shape(eye, NSColor.rgb(0xF3FAFF).cgColor, 1.8)
                c.restoreGState()
            }
        }
        c.restoreGState()
        c.addPath(head); c.setStrokeColor(ink); c.setLineWidth(1.8); c.strokePath()
        oval(leftHand.x - 2.8, leftHand.y - 2.7, 5.7, 5.5, red)
        oval(rightHand.x - 2.8, rightHand.y - 2.7, 5.7, 5.5, red)
    }
}
