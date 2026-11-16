import CoreGraphics

/// One shot per descent. Only the first real, reachable edge spends the shot.
struct WebRescue {
    static let flight = WebMotion.handoffTime
    static let gravity: CGFloat = 980
    private static let reach: CGFloat = 335
    private var nextLook: Double = 0.12
    private var spent = false
    var lostGrip: UInt32?
    var lostWindow: UInt32?

    static func fallingPoint(_ body: CGPoint, _ velocity: CGVector, after t: Double, in bounds: CGRect) -> CGPoint {
        CGPoint(x: min(bounds.maxX - 30, max(bounds.minX + 30, body.x + velocity.dx * t)),
                y: body.y + velocity.dy * t - 0.5 * gravity * t * t)
    }

    mutating func shot(age: Double, body: CGPoint, velocity: CGVector, facing: CGFloat,
                       bounds: CGRect, floor: CGFloat, surfaces: [Surface], field: PixelTerrain,
                       length: (CGPoint) -> CGFloat?) -> SwingTarget? {
        guard !spent, age >= nextLook, velocity.dy < -85 else { return nil }
        nextLook = age + 0.10
        let catchPoint = Self.fallingPoint(body, velocity, after: Self.flight, in: bounds)
        guard catchPoint.y >= floor + WebMotion.groundClearance + 10,
              catchPoint.x >= bounds.minX + 43, catchPoint.x <= bounds.maxX - 43 else { return nil }
        let heading: CGFloat = abs(velocity.dx) > 40 ? (velocity.dx > 0 ? 1 : -1) : facing
        let preferredX = catchPoint.x + 115 * heading
        let origin = CGPoint(x: body.x, y: body.y + 12)
        let safe = bounds.insetBy(dx: 42, dy: 38)
        let ranked = surfaces.compactMap { s -> (Surface, CGPoint, CGFloat)? in
            guard s.id != lostGrip, lostWindow == nil || s.windowID != lostWindow else { return nil }
            let r = s.frame.intersection(safe)
            guard r.width >= 4, r.height >= 2, r.maxY >= origin.y + 25, r.minY < origin.y + Self.reach else { return nil }
            let p = CGPoint(x: min(r.maxX - 1, max(r.minX + 1, preferredX)), y: r.midY)
            let nearX = max(0, max(r.minX - origin.x, origin.x - r.maxX))
            guard hypot(nearX, max(0, r.minY - origin.y)) <= Self.reach else { return nil }
            // Prefer a diagonal on the travel side so the arrest leads into an arc.
            let score = abs(p.x - preferredX) + 0.65 * abs(p.y - origin.y - 100)
            return (s, p, score)
        }.sorted { $0.2 < $1.2 }
        for (surface, aim, _) in ranked {
            guard let tip = field.nearestEdge(in: surface.frame.intersection(safe), to: aim),
                  tip.y >= origin.y + 25, hypot(tip.x - origin.x, tip.y - origin.y) <= Self.reach,
                  hypot(tip.x - catchPoint.x, tip.y - catchPoint.y - 12) <= Self.reach,
                  let radius = length(tip) else { continue }
            spent = true
            return SwingTarget(surface: surface, anchor: tip, length: radius)
        }
        return nil
    }
}
