import AppKit
import ClimbCore

extension NSColor {
    static func rgb(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: alpha)
    }
}

enum Ink {
    static let night = NSColor.rgb(0x202925)
    static let orange = NSColor.rgb(0xED8353)
    static let chalk = NSColor.rgb(0xF8E8C6)
    static let moss = NSColor.rgb(0xA7BFA5)
    static let muted = NSColor.rgb(0xA9ADA2)
}

func drawText(_ text: String, at point: CGPoint, font: NSFont, color: NSColor, width: CGFloat? = nil) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    if let width {
        (text as NSString).draw(in: CGRect(x: point.x, y: point.y, width: width, height: 70), withAttributes: attributes)
    } else { (text as NSString).draw(at: point, withAttributes: attributes) }
}

/// Vector artwork. A small, jointed climber drawn in points at any Retina scale.
enum ClimberArt {
    static func draw(in c: CGContext, at point: CGPoint, phase: Phase, time: Double,
                     phaseTime: Double = 0, facing: CGFloat = 1, grip: CGFloat = 22, scale: CGFloat = 1.2, handholds: Bool = false) {
        c.saveGState()
        c.translateBy(x: point.x, y: point.y)
        c.scaleBy(x: scale * facing, y: scale)
        if phase == .falling { c.rotate(by: CGFloat(phaseTime) * 5.2) }
        if phase == .recovering {
            let recovery = max(0, min(1, (phaseTime - 0.8) / 0.65))
            c.translateBy(x: 0, y: -13 * (1 - recovery))
            c.rotate(by: -CGFloat.pi / 2 * (1 - recovery))
        }
        let climbing = phase == .climbing || phase == .reaching || (handholds && phase == .traversing)
        let walking = phase == .walking || phase == .searching || (!handholds && phase == .traversing)
        let falling = phase == .falling || phase == .jumping || phase == .dragging
        let wave = CGFloat(sin(time * (walking ? 10 : 7.5)))
        let breath = CGFloat(sin(time * 2.3)) * 0.7
        let bob = climbing ? wave * 0.9 : (walking ? abs(wave) * 2 : breath)
        c.translateBy(x: 0, y: bob)
        c.setLineCap(.round); c.setLineJoin(.round)

        func line(_ points: [CGPoint], color: NSColor, width: CGFloat) {
            c.beginPath(); c.move(to: points[0]); points.dropFirst().forEach { c.addLine(to: $0) }
            c.setStrokeColor(color.cgColor); c.setLineWidth(width); c.strokePath()
        }
        func limb(_ points: [CGPoint], color: NSColor, width: CGFloat = 6) {
            line(points, color: Ink.night, width: width + 2.6)
            line(points, color: color, width: width)
        }
        func oval(_ rect: CGRect, _ color: NSColor, outline: Bool = false) {
            c.setFillColor(color.cgColor); c.fillEllipse(in: rect)
            if outline { c.setStrokeColor(Ink.night.cgColor); c.setLineWidth(1.5); c.strokeEllipse(in: rect) }
        }
        func roundRect(_ rect: CGRect, _ color: NSColor, radius: CGFloat) {
            let p = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            c.addPath(p); c.setFillColor(color.cgColor); c.fillPath()
            c.addPath(p); c.setStrokeColor(Ink.night.cgColor); c.setLineWidth(1.6); c.strokePath()
        }
        let wall = min(28, max(13, abs(grip / scale)))
        let farHand: CGPoint, nearHand: CGPoint, farFoot: CGPoint, nearFoot: CGPoint
        if climbing && handholds {
            farHand = CGPoint(x: -11, y: 29 - (phase == .reaching ? wave * 8 : 0))
            nearHand = CGPoint(x: 13, y: 30 + (phase == .reaching ? wave * 8 : 0))
            farFoot = CGPoint(x: -11, y: -24 + wave * 2)
            nearFoot = CGPoint(x: 12, y: -26 - wave * 2)
        } else if climbing {
            farHand = CGPoint(x: wall - max(0, wave) * 8, y: 18 - wave * 14)
            nearHand = CGPoint(x: wall - max(0, -wave) * 8, y: 18 + wave * 14)
            farFoot = CGPoint(x: wall - 3, y: -24 + wave * 8)
            nearFoot = CGPoint(x: wall - 2, y: -24 - wave * 8)
        } else if falling {
            farHand = CGPoint(x: -20, y: 23 + wave * 5); nearHand = CGPoint(x: 22, y: 23 - wave * 5)
            farFoot = CGPoint(x: -18, y: -24); nearFoot = CGPoint(x: 19, y: -22)
        } else if phase == .summit {
            farHand = CGPoint(x: -14, y: 30); nearHand = CGPoint(x: 19, y: 32)
            farFoot = CGPoint(x: -9, y: -28); nearFoot = CGPoint(x: 10, y: -28)
        } else {
            farHand = CGPoint(x: -7 - (walking ? wave * 12 : 0), y: -6)
            nearHand = CGPoint(x: 8 + (walking ? wave * 12 : 0), y: -5)
            farFoot = CGPoint(x: -5 + (walking ? wave * 13 : 0), y: -28 + (walking ? max(0, wave) * 8 : 0))
            nearFoot = CGPoint(x: 7 - (walking ? wave * 13 : 0), y: -28 + (walking ? max(0, -wave) * 8 : 0))
        }

        // Far limbs, rucksack, then body and near limbs establish a clear silhouette.
        limb([CGPoint(x: -3, y: 8), CGPoint(x: climbing ? 3 : -13, y: 8), farHand], color: .rgb(0xB86444), width: 5)
        oval(CGRect(x: farHand.x - 3, y: farHand.y - 3, width: 6, height: 6), Ink.chalk)
        limb([CGPoint(x: -4, y: -5), CGPoint(x: climbing ? -4 : farFoot.x * 0.7, y: -16), farFoot], color: .rgb(0x49564B), width: 6)
        line([farFoot, CGPoint(x: farFoot.x + 5, y: farFoot.y - 1)], color: Ink.night, width: 7)
        roundRect(CGRect(x: -20, y: -7, width: 15, height: 29), .rgb(0x607B70), radius: 5)
        line([CGPoint(x: -17, y: 14), CGPoint(x: -8, y: 14)], color: .rgb(0x97AC98), width: 2)
        roundRect(CGRect(x: -11, y: -9, width: 22, height: 29), Ink.orange, radius: 9)
        line([CGPoint(x: -7, y: 14), CGPoint(x: -1, y: -6)], color: .rgb(0xF8B679), width: 2.6)
        line([CGPoint(x: -10, y: -4), CGPoint(x: 10, y: -4)], color: .rgb(0x354B43), width: 4)
        oval(CGRect(x: -2, y: -6, width: 5, height: 5), Ink.chalk)
        roundRect(CGRect(x: -17, y: -13, width: 7, height: 10), Ink.chalk, radius: 2)
        limb([CGPoint(x: 3, y: -7), CGPoint(x: climbing ? 6 : nearFoot.x * 0.7, y: -17), nearFoot], color: .rgb(0x71806A), width: 6.5)
        line([nearFoot, CGPoint(x: nearFoot.x + 5, y: nearFoot.y - 1)], color: Ink.night, width: 7)
        limb([CGPoint(x: 6, y: 11), CGPoint(x: climbing ? 7 : 14, y: climbing ? 17 : 3), nearHand], color: .rgb(0xF1A06A), width: 6)
        oval(CGRect(x: nearHand.x - 3.6, y: nearHand.y - 3.6, width: 7.2, height: 7.2), Ink.chalk, outline: true)

        // Scarf, face and a cream climbing helmet.
        line([CGPoint(x: -3, y: 20), CGPoint(x: -20, y: 18 + wave * 2), CGPoint(x: -27, y: 22 + wave * 3)], color: .rgb(0xC65340), width: 4)
        oval(CGRect(x: -9, y: 17, width: 22, height: 21), .rgb(0xF2CCA3), outline: true)
        oval(CGRect(x: -12, y: 27, width: 26, height: 16), Ink.chalk, outline: true)
        roundRect(CGRect(x: -12, y: 27, width: 28, height: 5), .rgb(0xD4AB65), radius: 2)
        line([CGPoint(x: -5, y: 37), CGPoint(x: -1, y: 38)], color: .rgb(0xFFFAEB), width: 2)
        oval(CGRect(x: 6, y: 23, width: 2.8, height: 3.3), Ink.night)
        if phase == .falling { oval(CGRect(x: 6, y: 18, width: 3.5, height: 4), Ink.night) }
        else { line([CGPoint(x: 6, y: 18), CGPoint(x: 9, y: 19)], color: .rgb(0x915C40), width: 1.2) }
        c.restoreGState()
    }
}
