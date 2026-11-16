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
        let strands = engine.displayStrands
        guard !strands.isEmpty else { if isVisible { orderOut(nil) }; return }
        let points = strands.flatMap { [$0.hand, $0.tip] }
        let box = points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }.insetBy(dx: -7, dy: -7).integral
        setFrame(box.offsetBy(dx: origin.x, dy: origin.y), display: false)
        silk.strands = strands; silk.scale = engine.projection.scale; silk.localOrigin = box.origin; silk.needsDisplay = true
        if !isVisible { order(.below, relativeTo: character.windowNumber) }
    }

    private final class SilkView: NSView {
        var strands: [WebStrand] = []
        var scale: CGFloat = 1
        var localOrigin = CGPoint.zero
        override var isOpaque: Bool { false }
        override func draw(_ dirtyRect: NSRect) {
            guard let c = NSGraphicsContext.current?.cgContext else { return }
            c.clear(dirtyRect)
            c.saveGState(); defer { c.restoreGState() }
            c.translateBy(x: -localOrigin.x, y: -localOrigin.y)
            for strand in strands { SpiderRenderer.silk(strand, scale: scale, in: c) }
        }
    }
}
