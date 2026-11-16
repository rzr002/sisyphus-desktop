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
        guard let tip = engine.webTip else { if isVisible { orderOut(nil) }; return }
        let hand = engine.webHand
        let box = CGRect(x: min(hand.x,tip.x) - 7, y: min(hand.y,tip.y) - 7,
                         width: abs(hand.x - tip.x) + 14, height: abs(hand.y - tip.y) + 14)
        let localHand = CGPoint(x: hand.x - box.minX, y: hand.y - box.minY)
        let localTip = CGPoint(x: tip.x - box.minX, y: tip.y - box.minY)
        setFrame(box.offsetBy(dx: origin.x, dy: origin.y), display: false)
        silk.hand = localHand; silk.tip = localTip
        silk.attached = engine.phase != .webCasting; silk.needsDisplay = true
        if !isVisible { order(.below, relativeTo: character.windowNumber) }
    }

    private final class SilkView: NSView {
        var hand = CGPoint.zero, tip = CGPoint.zero
        var attached = false
        override var isOpaque: Bool { false }
        override func draw(_ dirtyRect: NSRect) {
            guard let c = NSGraphicsContext.current?.cgContext else { return }
            c.clear(dirtyRect)
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
