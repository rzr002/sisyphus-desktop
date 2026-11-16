import AppKit
import CoreGraphics
import ImageIO

// Publication fixture only. No screen capture, user documents, running-app
// enumeration, clock, network, or visible window is used by the exporter.
enum PromoScene {
    static let size = CGSize(width: 1280, height: 800)
    static let paper = CGRect(x: 116, y: 157, width: 475, height: 422)
    static let atlas = CGRect(x: 653, y: 240, width: 489, height: 333)
    static func bitmap() -> CGContext {
        CGContext(data:nil,width:Int(size.width),height:Int(size.height),bitsPerComponent:8,bytesPerRow:0,
                  space:CGColorSpace(name: CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
    static func text(_ string: String,_ x: CGFloat,_ y: CGFloat,_ size: CGFloat,_ face: String,_ color: UInt32,_ kern: CGFloat = 0) {
        let f = NSFont(name:face,size:size) ?? .systemFont(ofSize:size)
        (string as NSString).draw(at:CGPoint(x:x,y:y),withAttributes:[.font:f,.foregroundColor:NSColor.rgb(color),.kern:kern])
    }
    static func rounded(_ c:CGContext,_ rect:CGRect,_ radius:CGFloat,_ color:CGColor) {
        c.addPath(CGPath(roundedRect:rect,cornerWidth:radius,cornerHeight:radius,transform:nil));c.setFillColor(color);c.fillPath()
    }
    static func paperBody(_ c: CGContext, _ r: CGRect) {
        c.setFillColor(NSColor.rgb(0xFFFEFA).cgColor); c.fill(r)
        let x: CGFloat = 32, h = r.height
        text("FIELD NOTES    /    03",x,h-42,11,"Menlo",0x526C6B,1.3)
        text("山行手记",x,h-107,45,"Songti SC Bold",0x1D3035,2)
        text("十一月的山路，风先找到我们。",x,h-145,18,"Songti SC Regular",0x465F60)
        for (i,a,b) in [(0,"01   溪桥","从木桥望向对岸，松林顺着坡地伸远。"),(1,"02   山顶","沿石阶向上，回头已能看见整条来路。")] {
            let y = h - 210 - CGFloat(i * 77)
            text(a,x,y,20,"PingFangSC-Semibold",0x21363B)
            text(b,x,y-32,17,"Songti SC Regular",0x526767)
        }
    }
    // Draw the map into a genuine, in-memory PDF page before rendering it.
    static func mapPDF() -> CGPDFDocument {
        let data=NSMutableData(), consumer=CGDataConsumer(data: data as CFMutableData)!
        var box=CGRect(x:0,y:0,width:480,height:300)
        let c=CGContext(consumer:consumer,mediaBox:&box,nil)!
        c.beginPDFPage(nil);NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current=NSGraphicsContext(cgContext:c,flipped:false)
        c.setFillColor(NSColor.rgb(0xF5F0DC).cgColor);c.fill(box)
        text("TRAIL NOTES    /    03",28,263,11,"Menlo",0x41635A,1.2)
        text("周末步道",26,195,45,"Songti SC Bold",0x203C38,2)
        text("溪桥   →   松林   →   山顶",28,166,15,"PingFangSC-Regular",0x49685E)
        let ridge:[CGPoint]=[(26,52),(72,66),(112,58),(153,108),(198,90),(250,130),(281,117),(331,147),(388,133),(451,174)].map {CGPoint(x:$0.0,y:$0.1)}
        for i in (0..<6).reversed() {
            c.beginPath();c.addLines(between:ridge.map{CGPoint(x:$0.x,y:$0.y-CGFloat(i*7))})
            c.setLineWidth(i == 0 ? 2.7 : 0.8);c.setStrokeColor(NSColor.rgb(i == 0 ? 0x366556 : 0xAABDA7).cgColor);c.strokePath()
        }
        for i in [0,5,9] {let p=ridge[i];c.setFillColor(NSColor.rgb(0xAF5639).cgColor);c.fillEllipse(in:CGRect(x:p.x-3,y:p.y-3,width:6,height:6))}
        text("0 km",26,6,10,"Menlo",0x4B655D);text("6.4 km",409,6,10,"Menlo",0x4B655D)
        NSGraphicsContext.restoreGraphicsState();c.endPDFPage();c.closePDF()
        return CGPDFDocument(CGDataProvider(data:data as CFData)!)!
    }
    final class Page: NSView {
        let pdf: CGPDFDocument?
        init(size:CGSize, pdf: CGPDFDocument?) {self.pdf=pdf;super.init(frame:CGRect(origin:.zero,size:size))}
        required init?(coder:NSCoder){fatalError()}
        override func draw(_ rect:NSRect) {
            let c=NSGraphicsContext.current!.cgContext
            if let page=pdf?.page(at:1) {
                c.saveGState();c.concatenate(page.getDrawingTransform(.mediaBox,rect:bounds,rotate:0,preserveAspectRatio:false))
                c.drawPDFPage(page);c.restoreGState()
            } else {PromoScene.paperBody(c,bounds)}
        }
    }
    static func window(_ rect:CGRect, title:String, pdf:CGPDFDocument?, into c:CGContext) {
        let style:NSWindow.StyleMask=[.titled,.closable,.miniaturizable,.resizable]
        let content=NSWindow.contentRect(forFrameRect:CGRect(origin:.zero,size:rect.size),styleMask:style)
        let window=NSWindow(contentRect:content,styleMask:style,backing:.buffered,defer:true)
        window.appearance=NSAppearance(named:.aqua);window.title=title
        window.contentView=Page(size:content.size,pdf:pdf)
        let frame=window.contentView!.superview!
        frame.layoutSubtreeIfNeeded()
        let rep=frame.bitmapImageRepForCachingDisplay(in:frame.bounds)!
        frame.cacheDisplay(in:frame.bounds,to:rep)
        c.saveGState();c.setShadow(offset:CGSize(width:0,height:-5),blur:15,color:NSColor.black.withAlphaComponent(0.23).cgColor)
        let outline=CGPath(roundedRect:rect,cornerWidth:10,cornerHeight:10,transform:nil)
        c.addPath(outline);c.setFillColor(NSColor.white.cgColor);c.fillPath();c.setShadow(offset:.zero,blur:0,color:nil)
        c.addPath(outline);c.clip();c.draw(rep.cgImage!,in:rect);c.restoreGState()
    }
    static func reference() throws -> CGImage {
        let c=bitmap(), rect=CGRect(origin:.zero,size:size)
        NSGraphicsContext.saveGraphicsState();defer{NSGraphicsContext.restoreGraphicsState()}
        NSGraphicsContext.current=NSGraphicsContext(cgContext:c,flipped:false)
        guard let wallpaperPath=ProcessInfo.processInfo.environment["SISYPHUS_PROMO_WALLPAPER"] else { throw CocoaError(.fileNoSuchFile) }
        let wallpaper=URL(fileURLWithPath:wallpaperPath)
        guard let source=CGImageSourceCreateWithURL(wallpaper as CFURL,nil),
              let backdrop=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:1700] as CFDictionary) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let z=max(size.width/CGFloat(backdrop.width),size.height/CGFloat(backdrop.height))
        let w=CGFloat(backdrop.width)*z,h=CGFloat(backdrop.height)*z
        c.draw(backdrop,in:CGRect(x:(size.width-w)/2,y:(size.height-h)/2,width:w,height:h))
        c.setFillColor(NSColor.white.withAlphaComponent(0.79).cgColor);c.fill(CGRect(x:0,y:size.height-26,width:size.width,height:26))
        text("",17,779,14,"Helvetica",0x21372F)
        text("文本编辑     文件     编辑     格式     显示     窗口     帮助",48,779,13,"PingFangSC-Medium",0x21372F)
        text("周六   10:00",1165,779,12,"PingFangSC-Medium",0x28433C)
        let items=["/System/Library/CoreServices/Finder.app/Contents/Resources/Finder.icns",
                   "/System/Applications/Launchpad.app/Contents/Resources/AppIcon.icns",
                   "/Applications/Safari.app/Contents/Resources/AppIcon.icns",
                   "/System/Applications/TextEdit.app/Contents/Resources/AppIcon.icns",
                   "/System/Applications/Preview.app/Contents/Resources/AppIcon.icns",
                   "/System/Applications/Calculator.app/Contents/Resources/AppIcon.icns",
                   "/System/Applications/Utilities/Terminal.app/Contents/Resources/Terminal.icns"]
        let dock=CGRect(x:(rect.width-365)/2,y:6,width:365,height:55)
        rounded(c,dock,15,NSColor.white.withAlphaComponent(0.64).cgColor)
        for (i,path) in items.enumerated() {
            guard let src=CGImageSourceCreateWithURL(URL(fileURLWithPath:path) as CFURL,nil),
                  let image=CGImageSourceCreateThumbnailAtIndex(src,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:96] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
            c.draw(image,in:CGRect(x:dock.minX+10+CGFloat(i*50),y:12,width:44,height:44))
        }
        window(paper,title:"山行手记.rtf",pdf:nil,into:c)
        window(atlas,title:"周末步道图.pdf",pdf:mapPDF(),into:c)
        return c.makeImage()!
    }
}
