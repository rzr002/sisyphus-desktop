import AppKit

let destination = CommandLine.arguments[1]
let image = NSImage(size: CGSize(width: 1024, height: 1024))
image.lockFocus()
let c = NSGraphicsContext.current!.cgContext
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: 1) }
let dark = color(0.13, 0.18, 0.15), cream = color(0.97, 0.91, 0.77), orange = color(0.93, 0.51, 0.32)
c.addPath(CGPath(roundedRect: CGRect(x: 34, y: 34, width: 956, height: 956), cornerWidth: 215, cornerHeight: 215, transform: nil))
c.setFillColor(dark); c.fillPath()
c.setStrokeColor(color(0.32, 0.41, 0.34)); c.setLineWidth(4)
for offset in stride(from: 0, to: 220, by: 40) {
    c.move(to: CGPoint(x: 130 + offset, y: 160)); c.addCurve(to: CGPoint(x: 850, y: 850 - offset), control1: CGPoint(x: 660, y: 190 + offset), control2: CGPoint(x: 300 + offset, y: 730)); c.strokePath()
}
func line(_ points: [CGPoint], _ width: CGFloat, _ ink: CGColor) {
    c.setStrokeColor(ink); c.setLineWidth(width); c.setLineCap(.round); c.setLineJoin(.round)
    c.move(to: points[0]); points.dropFirst().forEach { c.addLine(to: $0) }; c.strokePath()
}
// A climber reaching toward the next little typographic ledge.
line([CGPoint(x: 610, y: 630), CGPoint(x: 825, y: 630)], 18, cream)
line([CGPoint(x: 225, y: 320), CGPoint(x: 390, y: 320)], 18, cream)
line([CGPoint(x: 430, y: 475), CGPoint(x: 395, y: 385), CGPoint(x: 320, y: 342)], 42, color(0.50, 0.59, 0.47))
line([CGPoint(x: 480, y: 470), CGPoint(x: 555, y: 370), CGPoint(x: 597, y: 315)], 44, color(0.65, 0.73, 0.57))
line([CGPoint(x: 445, y: 573), CGPoint(x: 376, y: 613), CGPoint(x: 346, y: 694)], 37, orange)
line([CGPoint(x: 483, y: 571), CGPoint(x: 573, y: 593), CGPoint(x: 647, y: 640)], 41, orange)
c.setFillColor(color(0.39, 0.51, 0.44)); c.addPath(CGPath(roundedRect: CGRect(x: 350, y: 469, width: 85, height: 150), cornerWidth: 30, cornerHeight: 30, transform: nil)); c.fillPath()
c.setFillColor(orange); c.addPath(CGPath(roundedRect: CGRect(x: 400, y: 458, width: 108, height: 151), cornerWidth: 42, cornerHeight: 42, transform: nil)); c.fillPath()
line([CGPoint(x: 414, y: 479), CGPoint(x: 495, y: 479)], 13, cream)
c.setFillColor(color(0.95, 0.78, 0.61)); c.fillEllipse(in: CGRect(x: 418, y: 590, width: 99, height: 92))
c.setFillColor(cream); c.fillEllipse(in: CGRect(x: 402, y: 637, width: 128, height: 72))
line([CGPoint(x: 410, y: 645), CGPoint(x: 531, y: 645)], 19, cream)
c.setFillColor(dark); c.fillEllipse(in: CGRect(x: 490, y: 618, width: 12, height: 16))
c.setFillColor(cream); c.fillEllipse(in: CGRect(x: 632, y: 627, width: 32, height: 32)); c.fillEllipse(in: CGRect(x: 332, y: 682, width: 30, height: 30))
line([CGPoint(x: 423, y: 599), CGPoint(x: 363, y: 574), CGPoint(x: 317, y: 589)], 20, color(0.77, 0.30, 0.23))
image.unlockFocus()
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination + "/icon_\(size)x\(size)\(suffix).png"))
    }
}
