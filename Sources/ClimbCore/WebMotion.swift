import Foundation
import CoreGraphics

/// A single piece of load-bearing silk. Coordinates are display-local points.
struct WebMotion {
    static let wristHeight: CGFloat = 37
    static let groundClearance: CGFloat = 18
    static let castTime = 0.20
    static let handoffTime = 0.19
    static let flipTime = 0.38
    static let vaultTime = flipTime + handoffTime
    static let kickTime = 0.58
    static let rappelTime = 1.95
    let anchor: CGPoint
    let wristX: CGFloat
    var start: CGPoint
    let landing: CGPoint
    let swingLength: CGFloat?
    var angle: CGFloat = 0
    var angularVelocity: CGFloat
    var speed = CGVector.zero
    var age: Double = 0
    private var catchLength: CGFloat?
    private var catchingWrist: CGPoint?
    private var lastRadius: CGFloat?
    var wristOffset: CGPoint {
        let raised = CGPoint(x: wristX, y: Self.wristHeight)
        return catchingWrist.map { Self.blend($0, raised, min(1, age / 0.18)) } ?? raised
    }

    init(anchor: CGPoint, body: CGPoint, swingLength: CGFloat?, direction: CGFloat, wristX: CGFloat) {
        self.anchor = anchor
        self.start = body
        self.wristX = wristX
        self.landing = CGPoint(x: anchor.x, y: anchor.y - 29)
        self.swingLength = swingLength
        self.angularVelocity = direction * 1.8
    }

    /// At the catch the stretched strand passes through the actual wrist.
    /// Keep the tangential part of the incoming velocity as the silk reels in.
    mutating func catchMovingBody(_ body: CGPoint, velocity: CGVector, from wrist: CGPoint) {
        catchingWrist = wrist
        let dx = body.x + wrist.x - anchor.x
        let height = anchor.y - body.y - wrist.y
        let distance = max(1, hypot(dx, height))
        catchLength = distance; lastRadius = distance
        angle = atan2(dx, height)
        angularVelocity = max(-3.5, min(3.5, (velocity.dx * cos(angle) + velocity.dy * sin(angle)) / distance))
        speed = velocity
    }

    func pulledBody(time: Double) -> (CGPoint, Bool) {
        let distance = hypot(landing.x - start.x, landing.y - start.y)
        let t = min(1, time / max(0.34, min(0.72, distance / 540)))
        return (Self.blend(start, landing, t), t >= 1)
    }

    mutating func swingingBody(dt: Double, length: CGFloat, floor: CGFloat) -> CGPoint {
        age += dt
        let takeup = min(1, age / 0.67)
        let smooth = takeup * takeup * (3 - 2 * takeup)
        let requested: CGFloat = catchLength.map { $0 + (length - $0) * CGFloat(smooth) } ?? length
        angularVelocity -= (760 / max(1, lastRadius ?? requested) * sin(angle) + 0.055 * angularVelocity) * dt
        angle += angularVelocity * dt
        // A wide new strand can be much longer than its eventual swing length.
        // Reel in on the approach to the low point, accounting for the moving wrist.
        let headroom = anchor.y - wristOffset.y - floor - Self.groundClearance
        let ahead = angle + angularVelocity * 0.17
        let steepest = angle * ahead <= 0 ? 1 : max(cos(angle), cos(ahead))
        let nowLimit = headroom / max(0.015, cos(angle))
        let aheadLimit = headroom / max(0.015, steepest)
        let takeIn: CGFloat = max((lastRadius ?? requested) - 510 * CGFloat(dt), aheadLimit)
        let radius: CGFloat = max(1, min(requested, nowLimit, takeIn))
        lastRadius = radius
        let body = CGPoint(x: anchor.x + sin(angle) * radius - wristOffset.x,
                           y: anchor.y - cos(angle) * radius - wristOffset.y)
        return catchLength == nil ? Self.blend(start, body, min(1, age / 0.8)) : body
    }

    static func ease(_ fraction: CGFloat) -> CGFloat {
        let t = min(1, max(0, fraction))
        return t * t * (3 - 2 * t)
    }

    static func rappelExtension(at time: Double) -> CGFloat {
        min(ease(time / 0.78), ease((rappelTime - time) / 0.71))
    }

    static func blend(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        let s = ease(t)
        return CGPoint(x: a.x + (b.x - a.x) * s, y: a.y + (b.y - a.y) * s)
    }
}

struct SwingTarget {
    let surface: Surface
    let anchor: CGPoint
    let length: CGFloat
}

/// Geometry for the two strands currently visible to the renderer.
public struct WebStrand {
    public let hand: CGPoint
    public let tip: CGPoint
    public let attached: Bool
}
