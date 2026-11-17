import CoreGraphics

/// Remember completed catches by position. A text row can get a new surface ID
/// between captures while its ink is still in the same place.
struct WebRoute {
    static let preferredStep: CGFloat = 215
    private var visits: [CGPoint] = []
    private var course: CGFloat?

    mutating func landed(at point: CGPoint) {
        if let last = visits.last {
            let dx = point.x - last.x
            if abs(dx) < 44 && abs(point.y - last.y) < 48 { return }
            if abs(dx) >= 64 { course = dx > 0 ? 1 : -1 }
        }
        visits.append(point)
        if visits.count > 6 { visits.removeFirst() }
    }

    func inward(from x: CGFloat, in bounds: CGRect) -> CGFloat? {
        let margin = min(250, bounds.width * 0.20)
        if x < bounds.minX + margin { return 1 }
        if x > bounds.maxX - margin { return -1 }
        return nil
    }

    func preferredHeading(from x: CGFloat, in bounds: CGRect) -> CGFloat? {
        // Let the first actual swing establish its course after the approach.
        inward(from: x, in: bounds) ?? (visits.count >= 3 ? course : nil)
    }

    func revisitCost(at point: CGPoint) -> CGFloat {
        var cost: CGFloat = 0
        for (age, visit) in visits.reversed().enumerated() {
            let distance = abs(point.x - visit.x) + 0.65 * abs(point.y - visit.y)
            cost = max(cost, (195 - distance * 1.6) * (1 - 0.11 * CGFloat(age)))
        }
        return cost
    }
}
