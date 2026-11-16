import AppKit
import ClimbCore

/// The silk is visual only. Its window never intercepts a click on the document.
final class WebPanel: NSPanel {
    private let silk = SilkView()
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "Sisyphus Web"
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        ignoresMouseEvents = true; hidesOnDeactivate = false; isReleasedWhenClosed = false
        level = .floating; animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        silk.setAccessibilityElement(false); contentView = silk
        setAccessibilityElement(false)
    }

    func update(_ engine: ClimbEngine, origin: CGPoint, behind character: NSWindow) {
        let strands = engine.strands
        guard !strands.isEmpty else { if isVisible { orderOut(nil) }; return }
        let points = strands.flatMap { [$0.hand, $0.tip] }
        let box = points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }.insetBy(dx: -7, dy: -7).integral
        setFrame(box.offsetBy(dx: origin.x, dy: origin.y), display: false)
        silk.strands = strands; silk.localOrigin = box.origin; silk.needsDisplay = true
        if !isVisible { order(.below, relativeTo: character.windowNumber) }
    }

    private final class SilkView: NSView {
        var strands: [WebStrand] = []
        var localOrigin = CGPoint.zero
        override var isOpaque: Bool { false }
        override func draw(_ dirtyRect: NSRect) {
            guard let c = NSGraphicsContext.current?.cgContext else { return }
            c.clear(dirtyRect)
            c.saveGState(); defer { c.restoreGState() }
            c.translateBy(x: -localOrigin.x, y: -localOrigin.y)
            for strand in strands { draw(strand, in: c) }
        }
        private func draw(_ strand: WebStrand, in c: CGContext) {
            let hand = strand.hand, tip = strand.tip, attached = strand.attached
            let line = CGMutablePath(); line.move(to: hand)
            line.addQuadCurve(to: tip, control: CGPoint(x: (hand.x + tip.x) * 0.5, y: (hand.y + tip.y) * 0.5 - (attached ? 1 : 5)))
            if attached {
                for (x,y) in [(-3,2), (3,2), (1,-3)] {
                    line.move(to: tip); line.addLine(to: CGPoint(x: tip.x + CGFloat(x), y: tip.y + CGFloat(y)))
                }
            }
            c.setLineCap(.round)
            c.addPath(line); c.setLineWidth(2.8); c.setStrokeColor(NSColor.rgb(0x283B50, alpha: 0.76).cgColor); c.strokePath()
            c.addPath(line); c.setLineWidth(1.2); c.setStrokeColor(NSColor.rgb(0xE8F7FF).cgColor); c.strokePath()
        }
    }
}
