import AppKit
import ClimbCore

/// Only this 96 × 112 pt sprite-sized window receives input. The desktop around
/// it remains untouched; no full-screen mouse monitor or Accessibility grant.
final class CharacterPanel: NSPanel {
    static let canvas = CGSize(width: 96, height: 112)
    static let pivot = CGPoint(x: 48, y: 44)
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    init() {
        super.init(contentRect: CGRect(origin: .zero, size: Self.canvas), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "Sisyphus"
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        hidesOnDeactivate = false; ignoresMouseEvents = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false; animationBehavior = .none
    }
    func place(at point: CGPoint, screenOrigin: CGPoint) {
        setFrameOrigin(CGPoint(x: screenOrigin.x + point.x - Self.pivot.x,
                               y: screenOrigin.y + point.y - Self.pivot.y))
    }
}

final class CharacterView: NSView {
    let engine: ClimbEngine
    var spritePack: CharacterPack? { didSet { needsDisplay = true } }
    var onMenu: ((NSEvent?) -> Void)?
    var onPickUp: (() -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onDrop: (() -> Void)?
    init(engine: ClimbEngine) {
        self.engine = engine
        super.init(frame: CGRect(origin: .zero, size: CharacterPanel.canvas))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("攀爬小人")
        setAccessibilityHelp("左键按住拖动，右键打开设置和退出菜单")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func rightMouseDown(with event: NSEvent) { onMenu?(event) }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { onMenu?(event) }
        else { onPickUp?() }
    }
    override func mouseDragged(with event: NSEvent) { onDrag?(NSEvent.mouseLocation) }
    override func mouseUp(with event: NSEvent) { onDrop?() }
    override func accessibilityPerformShowMenu() -> Bool { onMenu?(nil); return true }
    override func draw(_ dirtyRect: NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        c.clear(dirtyRect)
        if engine.height < 12 && engine.phase != .dragging {
            c.setFillColor(NSColor.black.withAlphaComponent(0.13).cgColor)
            c.fillEllipse(in: CGRect(x: 26, y: 5, width: 44, height: 6))
        }
        c.setShadow(offset: CGSize(width: 0, height: -1), blur: 2, color: NSColor.black.withAlphaComponent(0.2).cgColor)
        if engine.webEnabled {
            SpiderArt.draw(in: c, phase: engine.phase, time: engine.elapsed, facing: engine.facing, angle: engine.swingAngle,
                          wristSide: engine.wristSide, grip: engine.gripOffset, aim: engine.throwOffset, flip: engine.flipProgress)
        } else if let spritePack {
            // Reaching and traversing are one continuous climb cycle; changing
            // handholds must not reset it to the same leading arm every time.
            let moving = [Phase.searching, .walking, .climbing, .reaching, .traversing].contains(engine.phase)
            SpriteArt.draw(spritePack, in: c, phase: engine.phase,
                           time: moving ? engine.elapsed : engine.phaseTime, facing: engine.facing)
        } else {
            ClimberArt.draw(in: c, at: CharacterPanel.pivot, phase: engine.phase, time: engine.elapsed,
                            phaseTime: engine.phaseTime, facing: engine.facing,
                            grip: engine.gripX - engine.position.x, handholds: true)
        }
    }
}

enum SpriteArt {
    static func draw(_ pack: CharacterPack, in c: CGContext, phase: Phase, time: Double, facing: CGFloat) {
        let image = pack.sprite(for: phase, time: time)
        let clip = pack.clip(for: phase)
        let factor = min(CGFloat(pack.manifest.renderHeight ?? 104) / CGFloat(image.height),
                         92 / CGFloat(image.width), 104 / CGFloat(image.height))
        let width = CGFloat(image.width) * factor, height = CGFloat(image.height) * factor
        let climbing = [.climbing, .reaching, .traversing].contains(phase)
        let airborne = [.falling, .jumping, .dragging].contains(phase)
        let anchor = clip.anchor ?? (climbing ? [0.72, 0.82] : airborne ? [0.5, 0.42] : [0.5, 0.03])
        let targetY = climbing ? CharacterPanel.pivot.y + 29 : airborne ? CharacterPanel.pivot.y : 4
        c.saveGState()
        c.translateBy(x: CharacterPanel.pivot.x, y: targetY)
        c.scaleBy(x: facing * (pack.manifest.facesRight == false ? -1 : 1), y: 1)
        c.interpolationQuality = .high
        c.draw(image, in: CGRect(x: -width * anchor[0], y: -height * anchor[1], width: width, height: height))
        c.restoreGState()
    }
}
