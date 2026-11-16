import CoreGraphics
import Foundation

/// Immutable, application-agnostic geometry extracted from one visible image.
/// Pixel bytes are discarded; only a binary contact field and short ledges remain.
public struct PixelTerrain {
    public let logicalSize: CGSize
    public let origin: CGPoint
    public let holds: [CGRect]
    private let width: Int
    private let height: Int
    private let edges: [UInt8]

    fileprivate init(size: CGSize, origin: CGPoint = .zero, holds: [CGRect], width: Int, height: Int, edges: [UInt8]) {
        logicalSize = size; self.origin = origin; self.holds = holds
        self.width = width; self.height = height; self.edges = edges
    }
    public func translated(by delta: CGPoint) -> PixelTerrain {
        PixelTerrain(size: logicalSize, origin: CGPoint(x: origin.x + delta.x, y: origin.y + delta.y),
                     holds: holds.map { $0.offsetBy(dx: delta.x, dy: delta.y) }, width: width, height: height, edges: edges)
    }
    /// Select an actual edge pixel in the ledge, even when a segmented row spans spaces.
    func nearestEdge(in rect: CGRect, to point: CGPoint) -> CGPoint? {
        let area = rect.intersection(CGRect(origin: origin, size: logicalSize))
        guard !area.isNull, area.width > 0, area.height > 0, width > 0, height > 0 else { return nil }
        let sx = CGFloat(width) / logicalSize.width, sy = CGFloat(height) / logicalSize.height
        let x0 = max(0, Int(floor((area.minX - origin.x) * sx)))
        let x1 = min(width - 1, Int(ceil((area.maxX - origin.x) * sx)) - 1)
        let top = origin.y + logicalSize.height
        let y0 = max(0, Int(floor((top - area.maxY) * sy)))
        let y1 = min(height - 1, Int(ceil((top - area.minY) * sy)) - 1)
        guard x0 <= x1, y0 <= y1 else { return nil }
        var best: CGPoint?, squared = CGFloat.infinity
        for y in y0...y1 {
            for x in x0...x1 where edges[y * width + x] != 0 {
                let p = CGPoint(x: origin.x + (CGFloat(x) + 0.5) / sx, y: top - (CGFloat(y) + 0.5) / sy)
                let dx = p.x - point.x, dy = p.y - point.y
                let distance = dx * dx + dy * dy
                // A one-pixel speck can share a ledge with real ink. Do not fire
                // at a point that the very next unchanged frame would reject.
                if distance < squared, hasGrip(near: p, radius: 5) { squared = distance; best = p }
            }
        }
        return best
    }
    public func hasGrip(near point: CGPoint, radius: CGFloat = 9) -> Bool {
        guard width > 0, height > 0 else { return false }
        let sx = CGFloat(width) / logicalSize.width, sy = CGFloat(height) / logicalSize.height
        let x = Int((point.x - origin.x) * sx)
        let y = Int((logicalSize.height - point.y + origin.y) * sy)
        let r = max(2, Int(radius * min(sx, sy)))
        guard x + r >= 0, x - r < width, y + r >= 0, y - r < height else { return false }
        var count = 0
        for py in max(0, y - r)...min(height - 1, y + r) {
            for px in max(0, x - r)...min(width - 1, x + r) where (px - x) * (px - x) + (py - y) * (py - y) <= r * r {
                count += Int(edges[py * width + px])
                if count >= 4 { return true }
            }
        }
        return false
    }
}

public struct GripStability {
    private var misses = 0
    public init() {}
    public mutating func shouldRelease(hasGrip: Bool) -> Bool {
        misses = hasGrip ? 0 : misses + 1
        return misses >= 2
    }
    public mutating func reset() { misses = 0 }
}

public enum TerrainDetector {
    public static func detect(_ image: CGImage, logicalSize: CGSize) -> [CGRect] {
        analyze(image, logicalSize: logicalSize).holds
    }

    /// No text/shape classifiers: adjacent RGB changes are the terrain rule.
    public static func analyze(_ image: CGImage, logicalSize: CGSize) -> PixelTerrain {
        guard logicalSize.width > 0, logicalSize.height > 0 else {
            return PixelTerrain(size: logicalSize, holds: [], width: 0, height: 0, edges: [])
        }
        let ratio = min(1, 1600 / logicalSize.width)
        let w = max(8, Int(logicalSize.width * ratio)), h = max(8, Int(logicalSize.height * ratio))
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let rendered = rgba.withUnsafeMutableBytes { storage -> Bool in
            guard let c = CGContext(data: storage.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                    bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
            c.interpolationQuality = .high
            c.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard rendered else { return PixelTerrain(size: logicalSize, holds: [], width: 0, height: 0, edges: []) }
        var edges = [UInt8](repeating: 0, count: w * h)
        // Preserve hue-only boundaries and thin strokes instead of collapsing to gray.
        rgba.withUnsafeBufferPointer { bytes in
            edges.withUnsafeMutableBufferPointer { mask in
                for y in 1..<(h - 1) {
                    for x in 1..<(w - 1) {
                        let p = (y * w + x) * 4
                        var discontinuity = 0
                        for channel in 0..<3 {
                            let value = Int(bytes[p + channel])
                            discontinuity = max(discontinuity, abs(value - Int(bytes[p + 4 + channel])), abs(value - Int(bytes[p + w * 4 + channel])))
                        }
                        if discontinuity >= 42 { mask[y * w + x] = 1 }
                    }
                }
            }
        }
        // Fixed cells remain stable when glyphs join or split. Large graphics are valid.
        let cell = 8
        var holds: [CGRect] = []
        for y in stride(from: 0, to: h, by: cell) {
            var runStart: Int?
            func flush(_ end: Int) {
                guard let start = runStart else { return }
                holds.append(CGRect(x: CGFloat(start) / ratio,
                                    y: logicalSize.height - CGFloat(min(y + cell, h)) / ratio,
                                    width: CGFloat(end - start) / ratio,
                                    height: CGFloat(min(cell, h - y)) / ratio))
                runStart = nil
            }
            for x in stride(from: 0, to: w, by: cell) {
                var count = 0
                for py in y..<min(y + cell, h) { for px in x..<min(x + cell, w) { count += Int(edges[py * w + px]) } }
                if count >= 4 {
                    if let start = runStart, CGFloat(x + cell - start) / ratio > 104 { flush(x) }
                    if runStart == nil { runStart = x }
                } else { flush(x) }
            }
            flush(w)
        }
        return PixelTerrain(size: logicalSize, holds: holds, width: w, height: h, edges: edges)
    }
}
