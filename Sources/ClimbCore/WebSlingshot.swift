import CoreGraphics

/// A two-point sling brakes the incoming swing, draws both strands tight,
/// then accelerates under tension before the wrists release into free flight.
struct WebSlingshot {
    static let cast = WebMotion.handoffTime
    private static let draw = 0.44
    private static let hold = 0.12
    private static let recoil = 0.18
    static let windup = cast + draw + hold + recoil
    static let flight = 0.48
    private static let gravity: CGFloat = 760

    let start: CGPoint
    let braked: CGPoint
    let drawn: CGPoint
    let impulse: CGVector
    let initialWrist: CGPoint

    init?(from start: CGPoint, on rope: WebMotion, toward target: CGPoint, bounds: CGRect, floor: CGFloat) {
        self.start = start
        initialWrist = rope.wristOffset
        let heading: CGFloat = target.x > rope.anchor.x ? 1 : -1
        let coast = Self.cast * 0.5
        braked = CGPoint(x: start.x + max(-24, min(24, rope.speed.dx * coast)),
                         y: start.y + max(-13, min(13, rope.speed.dy * coast)))
        let left = min(rope.anchor.x, target.x), right = max(rope.anchor.x, target.x)
        let depth = min(56, braked.y - floor - WebMotion.groundClearance - 2)
        guard braked.x > left + 10, braked.x < right - 10, depth >= 29,
              min(rope.anchor.y, target.y) > braked.y + 52 else { return nil }
        drawn = CGPoint(x: braked.x - heading * min(8, depth * 0.15), y: braked.y - depth)
        let travelX = min(185, abs(target.x - drawn.x) * 0.82)
        let rise = min(126, target.y - braked.y - 53)
        guard travelX >= 48, rise >= 50 else { return nil }
        let catchPoint = CGPoint(x: drawn.x + heading * travelX, y: braked.y + rise)
        let flight = Self.flight, effectiveTime = flight + Self.recoil * 0.5
        impulse = CGVector(dx: (catchPoint.x - drawn.x) / effectiveTime,
                           dy: (catchPoint.y - drawn.y + 0.5 * Self.gravity * flight * flight) / effectiveTime)
        let peakTime = min(flight, max(0, impulse.dy / Self.gravity))
        let safe = CGRect(x: bounds.minX + 43, y: floor + WebMotion.groundClearance - 0.01,
                          width: bounds.width - 86, height: bounds.maxY - 48 - floor - WebMotion.groundClearance)
        guard [start, braked, drawn, catchPoint, airborne(at: peakTime)].allSatisfy(safe.contains) else { return nil }
    }

    static func tension(at time: Double) -> CGFloat {
        if time < cast { return 0 }
        if time < cast + draw { return WebMotion.ease((time - cast) / draw) }
        return 1 - WebMotion.ease((time - cast - draw - hold) / recoil)
    }

    func loading(at time: Double) -> CGPoint {
        if time <= Self.cast {
            let u = time / Self.cast, fraction = u * (2 - u)
            return CGPoint(x: start.x + (braked.x - start.x) * fraction, y: start.y + (braked.y - start.y) * fraction)
        }
        if time <= Self.cast + Self.draw { return WebMotion.blend(braked, drawn, (time - Self.cast) / Self.draw) }
        let t = min(Self.recoil, max(0, time - (Self.windup - Self.recoil)))
        let travel = 0.5 * t * t / Self.recoil
        return CGPoint(x: drawn.x + impulse.dx * travel, y: drawn.y + impulse.dy * travel)
    }

    func airborne(at time: Double) -> CGPoint {
        let t = min(Self.flight, max(0, time))
        let release = loading(at: Self.windup)
        return CGPoint(x: release.x + impulse.dx * t,
                       y: release.y + impulse.dy * t - 0.5 * Self.gravity * t * t)
    }

    func airborneVelocity(at time: Double) -> CGVector {
        CGVector(dx: impulse.dx, dy: impulse.dy - Self.gravity * min(time, Self.flight))
    }
}
