import CoreGraphics
import Foundation

/// Screen-space body and scale. The document and the silk's loaded tips remain on z = 0.
public struct SpiderProjection: Equatable {
    public let body: CGPoint
    public let scale: CGFloat
    public let depth: CGFloat

    public func project(_ offset: CGPoint) -> CGPoint {
        CGPoint(x: body.x + scale * offset.x, y: body.y + scale * offset.y)
    }
}

/// A pendulum moving on a plane angled to the desktop. Like a pinhole camera,
/// scale = focal length / (focal length - distance towards the viewer).
struct SwingCamera {
    private var z: CGFloat = 0
    private var drift = CGPoint.zero
    private let focal: CGFloat = 400
    private var scale: CGFloat { focal / (focal - z) }

    mutating func follow(_ phase: Phase, angle: CGFloat, progress: CGFloat, body: CGPoint, anchor: CGPoint?, dt: Double) {
        let target: CGFloat
        switch phase {
        case .webSwinging, .webHandoff, .webRappel, .webKick:
            target = 130 * sin(angle * 1.35) + 14 * cos(angle)
        case .webWindup: target = 15 - 94 * progress
        case .webLaunch: target = -54 + 184 * sin(.pi * progress)
        case .webVault: target = 16 + 90 * sin(.pi * progress)
        case .webPulling: target = min(42, (anchor.map { hypot(body.x - $0.x, body.y - $0.y) } ?? 0) * 0.22)
        default: target = 0
        }
        let mix = 1 - exp(-11 * dt)
        z += (min(128, max(-120, target)) - z) * mix
        // Parallax is local to the swing, never relative to a monitor corner.
        let dx = anchor.map { max(-100, min(100, body.x - $0.x)) } ?? 0
        let dy = anchor.map { max(-68, min(68, body.y - $0.y)) } ?? 0
        drift.x += (dx * (scale - 1) - drift.x) * mix
        drift.y += (dy * (scale - 1) - drift.y) * mix
    }

    mutating func pinUnderPointer() { drift = .zero }

    func view(body: CGPoint, bounds: CGRect, floor: CGFloat) -> SpiderProjection {
        let xMargin = min(bounds.width / 2, scale * 38)
        let shown = CGPoint(x: max(bounds.minX + xMargin, min(bounds.maxX - xMargin, body.x + drift.x)),
                            y: max(floor + max(0, (scale - 1) * 38),
                                   min(bounds.maxY - scale * 44, body.y + drift.y)))
        return SpiderProjection(body: shown, scale: scale, depth: z / 128)
    }
}
