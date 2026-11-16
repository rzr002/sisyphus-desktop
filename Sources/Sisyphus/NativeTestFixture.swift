#if DEBUG
import AppKit
import ClimbCore

final class PracticeView: NSView {
    let editor = NSTextView(frame: .zero)
    private let sceneControl = NSSegmentedControl(labels: ["可编辑文字", "图形与颜色"], trackingMode: .selectOne, target: nil, action: nil)
    private var shapes = false
    var smooth = false { didSet { editor.isHidden = smooth || shapes; sceneControl.isHidden = smooth; needsDisplay = true } }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        editor.drawsBackground = false; editor.isRichText = false; editor.isEditable = true; editor.isSelectable = true
        editor.font = .systemFont(ofSize: 17, weight: .medium); editor.textColor = Ink.night
        editor.insertionPointColor = Ink.orange; editor.textContainerInset = CGSize(width: 8, height: 8)
        editor.textContainer?.lineFragmentPadding = 0
        editor.isVerticallyResizable = false; editor.isHorizontallyResizable = false
        editor.textContainer?.widthTracksTextView = true
        let paragraph = NSMutableParagraphStyle(); paragraph.paragraphSpacing = 23; paragraph.minimumLineHeight = 22
        editor.defaultParagraphStyle = paragraph
        editor.typingAttributes = [.font: editor.font!, .foregroundColor: Ink.night, .paragraphStyle: paragraph]
        let document = "每次都算重新出发\n窗外，还有一座山\n今天的待办事项\n一封没写完的信\n抓紧，再向上\n从这一行开始"
        editor.textStorage?.setAttributedString(NSAttributedString(string: document, attributes: editor.typingAttributes))
        addSubview(editor)
        sceneControl.selectedSegment = 0; sceneControl.target = self; sceneControl.action = #selector(changeScene)
        addSubview(sceneControl)
        needsLayout = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        editor.frame = CGRect(x: 40, y: 65, width: bounds.width * 0.57 - 58, height: max(200, bounds.height - 205))
        sceneControl.frame = CGRect(x: 26, y: bounds.height - 127, width: bounds.width * 0.57 - 48, height: 25)
    }
    @objc private func changeScene() {
        shapes = sceneControl.selectedSegment == 1
        editor.isHidden = shapes || smooth; needsDisplay = true
    }
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.rgb(0xF4F0E5).setFill(); bounds.fill()
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        let split = bounds.width * 0.57
        NSColor.rgb(0xEBEEDC).setFill(); CGRect(x: split, y: 0, width: bounds.width - split, height: bounds.height).fill()
        if !smooth {
            drawText("THE EVERYDAY MOUNTAIN", at: CGPoint(x: 30, y: bounds.height - 43), font: .monospacedSystemFont(ofSize: 10, weight: .medium), color: .rgb(0x767B6C))
            drawText("日常，也是山。", at: CGPoint(x: 30, y: bounds.height - 91), font: NSFont(name: "Songti SC", size: 28) ?? .systemFont(ofSize: 28), color: Ink.night)
            if shapes {
                c.setFillColor(NSColor.rgb(0xD98061).cgColor); c.fill(CGRect(x: 55, y: 75, width: 145, height: 100))
                c.setFillColor(NSColor.rgb(0x70908B).cgColor); c.fillEllipse(in: CGRect(x: 150, y: 170, width: 145, height: 145))
                c.setStrokeColor(Ink.night.cgColor); c.setLineWidth(5)
                c.move(to: CGPoint(x: 70, y: 95)); c.addCurve(to: CGPoint(x: 265, y: 385), control1: CGPoint(x: 300, y: 205), control2: CGPoint(x: 20, y: 295)); c.strokePath()
                c.setStrokeColor(NSColor.rgb(0xC99445).cgColor); c.setLineWidth(4)
                c.strokeEllipse(in: CGRect(x: 75, y: 280, width: 115, height: 100))
            }
            drawText(shapes ? "颜色交界可以抓，纯色内部没有抓力。" : "上面的字可以编辑。删掉它抓住的地方试试。", at: CGPoint(x: 26, y: 23), font: .systemFont(ofSize: 10), color: .rgb(0x777E70))
        }
        // The right-hand wall is intentionally uniform: no decorative texture.
        if !smooth {
            drawText("平滑的地方", at: CGPoint(x: split + 28, y: bounds.height - 65), font: .systemFont(ofSize: 15, weight: .medium), color: .rgb(0x5F6D56))
            drawText("没有落手点，就要另找一条路。", at: CGPoint(x: split + 28, y: bounds.height - 89), font: .systemFont(ofSize: 10), color: .rgb(0x7E8872))
            c.setStrokeColor(NSColor.rgb(0x9BA68B, alpha: 0.2).cgColor); c.setLineWidth(1)
            c.move(to: CGPoint(x: split, y: 22)); c.addLine(to: CGPoint(x: split, y: bounds.height - 22)); c.strokePath()
        }
    }
    func detectedHolds(screen: NSScreen) -> [CGRect] {
        pixelTerrain(screen: screen)?.holds ?? []
    }
    func pixelTerrain(screen: NSScreen) -> PixelTerrain? {
        layoutSubtreeIfNeeded()
        guard let bitmap = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: bitmap)
        guard let image = bitmap.cgImage, let window else { return nil }
        let origin = window.convertPoint(toScreen: convert(.zero, to: nil))
        return TerrainDetector.analyze(image, logicalSize: bounds.size).translated(by: CGPoint(x: origin.x - screen.frame.minX, y: origin.y - screen.frame.minY))
    }
}

final class PracticeWindow: NSWindow {
    let terrainView = PracticeView(frame: .zero)
    init(screen: NSScreen) {
        let available = screen.visibleFrame
        let height = min(550, available.height - 70)
        let width = min(660, available.width * 0.54)
        let rect = CGRect(x: available.minX + max(45, available.width * 0.20), y: available.minY + 8, width: width, height: height)
        super.init(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        title = "Sisyphus 自动验证窗口"
        isReleasedWhenClosed = false
        minSize = CGSize(width: 460, height: 380)
        appearance = NSAppearance(named: .aqua)
        contentView = terrainView
        terrainView.autoresizingMask = [.width, .height]
        terrainView.frame = CGRect(origin: .zero, size: rect.size)
    }
}
#endif
