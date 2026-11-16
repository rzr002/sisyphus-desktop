import Foundation
import CoreGraphics

/// All coordinates are display-local points, with y increasing upwards.
struct WebMotion {
    static let wristHeight: CGFloat = 37
    static let castTime = 0.24
    let anchor: CGPoint
    var start: CGPoint
    let landing: CGPoint
    let swingLength: CGFloat?
    var angle: CGFloat = 0
    var angularVelocity: CGFloat
    var speed = CGVector.zero

    init(anchor: CGPoint, body: CGPoint, swingLength: CGFloat?, direction: CGFloat) {
        self.anchor = anchor
        self.start = body
        self.landing = CGPoint(x: anchor.x, y: anchor.y - 29)
        self.swingLength = swingLength
        self.angularVelocity = direction * 1.8
    }

    func pulledBody(time: Double) -> (CGPoint, Bool) {
        let distance = hypot(landing.x - start.x, landing.y - start.y)
        let t = min(1, time / max(0.48, min(1.15, distance / 325)))
        return (Self.blend(start, landing, t), t >= 1)
    }

    mutating func swingingBody(time: Double, dt: Double, length: CGFloat) -> CGPoint {
        // A small initial push supplies energy. Gravity reverses the swing;
        // damping lets it settle until he reels himself back onto the ledge.
        angularVelocity -= (760 / length * sin(angle) + 0.055 * angularVelocity) * dt
        angle += angularVelocity * dt
        let body = CGPoint(x: anchor.x + sin(angle) * length,
                           y: anchor.y - cos(angle) * length - Self.wristHeight)
        return Self.blend(start, body, min(1, time / 0.8))
    }

    static func blend(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        let s = t * t * (3 - 2 * t)
        return CGPoint(x: a.x + (b.x - a.x) * s, y: a.y + (b.y - a.y) * s)
    }
}
