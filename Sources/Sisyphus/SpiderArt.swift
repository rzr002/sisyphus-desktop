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
    private static func ramp(_ colors: [UInt32], _ stops: [CGFloat]) -> CGGradient {
        CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map { NSColor.rgb($0).cgColor } as CFArray, locations: stops)!
    }
    private static let maskLight = ramp([0xFFAA89, 0xFF6654, 0xD83240, 0x8D2947, 0x392B45], [0, 0.22, 0.54, 0.81, 1])
    private static let glass = ramp([0xFFFFFF, 0xF4FDFF, 0xBADFEA, 0x78A8C0], [0, 0.36, 0.73, 1])
    private static let chest = ramp([0x782947, 0xDB3442, 0xFF9174], [0, 0.57, 1])

    static func draw(in c: CGContext, phase: Phase, time: Double, facing: CGFloat, angle: CGFloat,
                     wristSide: CGFloat, grip: CGPoint, aim: CGPoint, progress: CGFloat, depth: CGFloat = 0) {
        let walking = phase == .searching || phase == .walking
        let climbing = [.climbing, .reaching, .traversing].contains(phase)
        let tethered = phase.usesWeb
        let wave = CGFloat(sin(time * (walking ? 8.5 : 6.2)))
        let pivot = CharacterPanel.pivot
        c.saveGState()
        defer { c.restoreGState() }
        c.translateBy(x: pivot.x, y: pivot.y)
        let inversion = phase == .webRappel ? facing * .pi * progress : 0
        let openForCatch = min(1, max(0, (progress - 0.26) / 0.33))
        let kick = sin(.pi * progress)
        let turn = tethered ? 0.45 * sin(angle) * facing + 0.5 * depth : 0
        let volume: CGFloat = tethered ? 0.47 + 0.36 * depth : 0
        if phase == .webRappel {
            c.rotate(by: inversion)
        } else if phase == .webLaunch {
            // Unfold into a headfirst arrow, level off, then turn the shooting
            // shoulder toward the next strand before it leaves the wrist.
            c.rotate(by: -facing * (0.79 + 0.38 * sin(.pi * min(1, progress / 0.45))) * (1 - openForCatch))
        } else if phase == .webVault {
            let eased = progress * progress * (3 - 2 * progress)
            c.rotate(by: -facing * 2 * .pi * eased)
        } else if phase == .webRescue {
            c.translateBy(x: aim.x, y: aim.y)
            c.rotate(by: -facing * (0.075 + 0.085 * (1 - progress)))
            c.translateBy(x: -aim.x, y: -aim.y)
        } else if phase == .webSwinging || phase == .webPulling || phase == .webKick {
            // Pivot around the moving, load-bearing wrist: the ink touches the line even in a hard lean.
            let lean = phase == .webPulling ? facing * 0.22 : max(-0.24, min(0.24, angle * 0.34 - (phase == .webKick ? facing * kick * 0.18 : 0)))
            c.translateBy(x: grip.x, y: grip.y); c.rotate(by: lean); c.translateBy(x: -grip.x, y: -grip.y)
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
            if tethered {
                // A narrow lit ridge against the shaded tube, rather than a flat stick.
                let dx = joint.x-root.x, dy = joint.y-root.y, len = max(1, hypot(dx,dy))
                let n = p(-dy/len * width * 0.19, dx/len * width * 0.19)
                stroke([p(root.x+dx*0.2+n.x,root.y+dy*0.2+n.y),p(joint.x+n.x,joint.y+n.y)],
                       boot ? NSColor.rgb(0x527FA9).cgColor : NSColor.rgb(0xF27466).cgColor, width * 0.20)
            }
        }
        let leftHand: CGPoint, rightHand: CGPoint, leftKnee: CGPoint, rightKnee: CGPoint
        let leftFoot: CGPoint, rightFoot: CGPoint
        var leftElbow = p(-14, 0), rightElbow = p(14, 0)
        if tethered {
            // Inverse of the body rotation keeps a hanging wrist on the silk
            // while the mask and torso turn upside down beneath it.
            let active = p((grip.x * cos(inversion) + grip.y * sin(inversion)) * facing,
                           -grip.x * sin(inversion) + grip.y * cos(inversion))
            let shooting = p(aim.x * facing, aim.y)
            let freeSide = -wristSide
            let loaded: CGPoint, free: CGPoint
            let tilt = sin(angle) * facing
            switch phase {
            case .webWindup:
                loaded = active; free = shooting
                leftKnee = p(-14 - 8 * progress, -14 + 14 * progress)
                rightKnee = p(14 + 8 * progress, -12 + 14 * progress)
                leftFoot = p(-12 + 6 * progress, -28 + 17 * progress)
                rightFoot = p(14 - 8 * progress, -23 + 14 * progress)
            case .webLaunch:
                loaded = p(-14 - 6 * openForCatch, -10 + 4 * openForCatch)
                free = p(6 * (1 - openForCatch) + shooting.x * openForCatch, 39 * (1 - openForCatch) + shooting.y * openForCatch)
                leftKnee = p(-8 - 7 * openForCatch, -20 + 8 * openForCatch)
                rightKnee = p(10 + 8 * openForCatch, -17 + 11 * openForCatch)
                leftFoot = p(-10 - 8 * openForCatch, -34 + 12 * openForCatch)
                rightFoot = p(3 + 3 * openForCatch, -29 + 15 * openForCatch)
            case .webRappel:
                loaded = active
                free = p(freeSide * (18 + 7 * progress), 2 + 17 * progress)
                leftKnee = p(-16 - 2 * progress, -13 - 2 * progress)
                rightKnee = p(16 + 2 * progress, -12 - 4 * progress)
                leftFoot = p(-11 + 14 * progress, -24 - 8 * progress)
                rightFoot = p(13 - 17 * progress, -22 - 8 * progress)
            case .webKick:
                loaded = active; free = p(-19 - 9 * kick, 1 + 14 * kick)
                leftKnee = p(-12 - 9 * kick, -14 + 5 * kick)
                rightKnee = p(12 + 8 * kick, -12 + 16 * kick)
                leftFoot = p(-8 - 14 * kick, -26 + 6 * kick)
                rightFoot = p(11 + 23 * kick, -23 + 32 * kick)
            case .webVault:
                let open = max(0, min(1, (progress - 0.72) / 0.28))
                loaded = p(wristSide * (9 + 11 * open), -3 + 8 * open)
                free = p(freeSide * 10 * (1-open) + shooting.x * open, -4 * (1-open) + shooting.y * open)
                leftKnee = p(-13 - 4 * open, -3 - 9 * open); rightKnee = p(14, -1 - 10 * open)
                leftFoot = p(-4 - 16 * open, -11 - 10 * open); rightFoot = p(4 + 10 * open, -8 - 15 * open)
            case .webPulling:
                loaded = active; free = p(-23, -7)
                leftKnee = p(-16, -13); rightKnee = p(12, -8)
                leftFoot = p(-25, -22); rightFoot = p(2, -19)
            case .webCasting:
                loaded = active; free = p(freeSide * 22, -3)
                leftKnee = p(-18, -12); rightKnee = p(15, -9)
                leftFoot = p(-13, -23); rightFoot = p(20, -17)
            case .webRescue:
                // Counterbalance the shooting shoulder, then draw one knee up before impact.
                free = shooting; loaded = p(-24 + 5 * progress, -5 - 9 * progress)
                leftKnee = p(-12 - 9 * progress, -12 + 9 * progress)
                leftFoot = p(-7 - 7 * progress, -22 + 12 * progress)
                rightKnee = p(7 + 5 * progress, -20 + 6 * progress)
                rightFoot = p(2 + 12 * progress, -32 + 6 * progress)
            case .webHandoff:
                loaded = active; free = shooting
                leftKnee = p(-16, -17); rightKnee = p(17, -6)
                leftFoot = p(-21, -29); rightFoot = p(8, -15)
            default:
                loaded = active; free = p(freeSide * (21 + wave * 2), 2 + 8 * tilt + wave * 4)
                leftKnee = p(-13 - 4 * tilt, -16 + 5 * tilt); rightKnee = p(15 + 3 * tilt, -9 - 4 * tilt)
                leftFoot = p(-10 - 9 * tilt, -28 + 8 * tilt); rightFoot = p(8 + 6 * tilt, -19 - 5 * tilt)
            }
            let loadOnLeft = phase == .webWindup ? loaded.x < free.x : wristSide < 0
            leftHand = loadOnLeft ? loaded : free; rightHand = loadOnLeft ? free : loaded
            func elbow(_ hand: CGPoint, _ side: CGFloat) -> CGPoint {
                // A bent, outward elbow clearly separates the two arms on a 96-point sprite.
                let bend: CGFloat = phase == .webVault && progress < 0.8 ? 5 : 11
                let compression = phase == .webWindup ? 9 * progress : 0
                return p(0.55 * hand.x + side * (bend + compression * 0.35), 0.5 * hand.y + 2 - compression)
            }
            leftElbow = elbow(leftHand, -1); rightElbow = elbow(rightHand, 1)
        } else if climbing {
            leftElbow = p(-22, 19); rightElbow = p(21, 13)
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
        // Stage the far limbs behind the chest; the near boot and glove come forward as the body turns.
        let towardsLens = volume * max(0, depth)
        let boot = p(rightFoot.x + (rightKnee.x - rightFoot.x) * 0.28 * towardsLens + 1.7 * towardsLens,
                     rightFoot.y + (rightKnee.y - rightFoot.y) * 0.28 * towardsLens)
        limb(p(-4,-9), leftKnee, leftFoot, 6.2 - volume, true)
        limb(p(4,-9), rightKnee, boot, 6.8 + volume * 1.8, true)
        stroke([leftFoot, p(leftFoot.x - 3, leftFoot.y - 1)], ink, 8)
        stroke([leftFoot, p(leftFoot.x - 3, leftFoot.y - 1)], redDark, 5.8)
        stroke([boot, p(boot.x + 3 + volume, boot.y - 1)], ink, 8 + volume * 2)
        stroke([boot, p(boot.x + 3 + volume, boot.y - 1)], red, 5.8 + volume * 2)
        if towardsLens > 0.2 {
            stroke([p(boot.x - 1, boot.y - 1), p(boot.x + 3, boot.y - 2)], redDark, 1.5 + towardsLens)
        }
        if tethered { limb(p(-7,2), leftElbow, leftHand, 4.9 - 0.6 * volume, false) }
        let torso = CGMutablePath()
        torso.move(to: p(-9, 5)); torso.addQuadCurve(to: p(9,5), control: p(0,10))
        torso.addQuadCurve(to: p(6,-13), control: p(12,-3))
        torso.addQuadCurve(to: p(-6,-13), control: p(0,-17))
        torso.addQuadCurve(to: p(-9,5), control: p(-11,-3)); torso.closeSubpath()
        shape(torso, climbing ? blue : red)
        if tethered {
            c.saveGState(); c.addPath(torso); c.clip()
            c.drawLinearGradient(chest, start: p(-8,-8), end: p(7,5), options: [.drawsBeforeStartLocation,.drawsAfterEndLocation])
            c.restoreGState()
        }
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
        if !tethered { limb(p(-7,2), leftElbow, leftHand, 5.1, false) }
        limb(p(7,2), rightElbow, rightHand, 5.3 + volume * 1.2, false)
        let head = CGMutablePath()
        head.move(to: p(0,4))
        head.addCurve(to: p(-16.5,20), control1: p(-5,4), control2: p(-15,11))
        head.addCurve(to: p(0,34), control1: p(-19,30), control2: p(-10,35))
        head.addCurve(to: p(16.5,20), control1: p(10,35), control2: p(19,30))
        head.addCurve(to: p(0,4), control1: p(15,11), control2: p(5,4)); head.closeSubpath()
        shape(head, red, 2)
        c.saveGState(); c.addPath(head); c.clip()
        let light = p(-5 * facing, 27)
        c.drawRadialGradient(maskLight, startCenter: light, startRadius: 0, endCenter: light, endRadius: 27,
                             options: .drawsAfterEndLocation)
        // Wrap the web mask and both lenses around the same turning hemisphere.
        let yaw = 0.58 * turn, pitch = 0.13 * depth
        let cy = cos(yaw), sy = sin(yaw), cp = cos(pitch), sp = sin(pitch)
        func onMask(_ dot: CGPoint) -> CGPoint {
            guard tethered else { return dot }
            let u = dot.x / 17, v = (dot.y - 20) / 16
            let z = sqrt(max(0, 1 - u*u - v*v))
            return p(17 * (u*cy + z*sy), 20 + 16 * (v*cp + (z*cy - u*sy)*sp))
        }
        let hub = p(climbing ? 0 : 1, climbing ? 21 : 16)
        for outer in [p(-10,3),p(0,1),p(11,4),p(-19,16),p(19,16),p(-19,27),p(19,27),p(-11,37),p(0,37),p(11,37)] {
            stroke((0...6).map { i in let t = CGFloat(i)/6; return onMask(p(hub.x+(outer.x-hub.x)*t,hub.y+(outer.y-hub.y)*t)) }, silk, 0.66)
        }
        for y: CGFloat in [10, 17, 24, 30] {
            let curve = CGMutablePath(); curve.move(to: onMask(p(-18,y + 2)))
            for j in 0..<4 {
                let x = CGFloat(j) * 9 - 18
                curve.addQuadCurve(to: onMask(p(x + 9,y + 2)), control: onMask(p(x + 4.5,y - 1)))
            }
            c.addPath(curve); c.setStrokeColor(silk); c.setLineWidth(0.65); c.strokePath()
        }
        if !climbing {
            for side: CGFloat in [-1,1] {
                func eyePoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint { onMask(p(side * x, y)) }
                let eye = CGMutablePath()
                eye.move(to: eyePoint(2.4,18.7)); eye.addQuadCurve(to: eyePoint(14.5,25), control: eyePoint(8,20))
                eye.addQuadCurve(to: eyePoint(10.2,13.2), control: eyePoint(13.8,17))
                eye.addQuadCurve(to: eyePoint(2.4,18.7), control: eyePoint(4,11)); eye.closeSubpath()
                c.saveGState(); c.addPath(eye); c.clip()
                c.drawLinearGradient(glass,start: eyePoint(6,22),end: eyePoint(10,13),options: [.drawsBeforeStartLocation,.drawsAfterEndLocation])
                c.restoreGState()
                c.addPath(eye); c.setStrokeColor(ink); c.setLineWidth(1.8); c.strokePath()
            }
        }
        c.restoreGState()
        c.addPath(head); c.setStrokeColor(ink); c.setLineWidth(1.8); c.strokePath()
        oval(leftHand.x - 2.8, leftHand.y - 2.7, 5.7, 5.5, red)
        oval(rightHand.x - 2.8 - volume, rightHand.y - 2.7 - volume, 5.7 + 2 * volume, 5.5 + 2 * volume, red)
        if tethered {
            stroke([p(rightHand.x - 1.1,rightHand.y + 1.3),p(rightHand.x + 0.6,rightHand.y + 1.7)], NSColor.rgb(0xFFA58A).cgColor, 0.9)
        }
    }
}
