import AppKit
import ClimbCore
import ImageIO
import UniformTypeIdentifiers

@main enum RenderPreview {
    static func save(_ image: CGImage, to file: URL) throws {
        guard let dest=CGImageDestinationCreateWithURL(file as CFURL,UTType.png.identifier as CFString,1,nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(dest,image,nil)
        if !CGImageDestinationFinalize(dest) { throw CocoaError(.fileWriteUnknown) }
    }
    static func render(_ hero:ClimbEngine, on base:CGImage) -> CGImage {
        let c=PromoScene.bitmap()
        c.draw(base,in:CGRect(origin:.zero,size:PromoScene.size))
        for strand in hero.strands {
            let (a,b)=(strand.hand,strand.tip)
            let line=CGMutablePath();line.move(to:a)
            line.addQuadCurve(to:b,control:CGPoint(x:(a.x+b.x)/2,y:(a.y+b.y)/2 - (strand.attached ? 1:5)))
            if strand.attached {
                for (x,y) in [(-3,2),(3,2),(1,-3)] { line.move(to:b);line.addLine(to:CGPoint(x:b.x+CGFloat(x),y:b.y+CGFloat(y))) }
            }
            c.setLineCap(.round)
            for (width,color) in [(2.8,NSColor.rgb(0x283B50,alpha:0.76)),(1.2,NSColor.rgb(0xE8F7FF))] {
                c.addPath(line);c.setLineWidth(width);c.setStrokeColor(color.cgColor);c.strokePath()
            }
        }
        c.translateBy(x:hero.position.x-CharacterPanel.pivot.x,y:hero.position.y-CharacterPanel.pivot.y)
        c.setShadow(offset:CGSize(width:0,height:-1),blur:2,color:NSColor.black.withAlphaComponent(0.2).cgColor)
        SpiderArt.draw(in:c,phase:hero.phase,time:hero.elapsed,facing:hero.facing,angle:hero.swingAngle,
                      wristSide:hero.wristSide,grip:hero.gripOffset,aim:hero.throwOffset,progress:hero.poseProgress)
        return c.makeImage()!
    }
    static func main() throws {
        guard CommandLine.arguments.count == 2 || CommandLine.arguments.count == 4 else {
            print("Usage: render-preview SCRATCH_DIRECTORY [START_SECONDS DURATION_SECONDS]");return
        }
        NSApplication.shared.setActivationPolicy(.prohibited)
        let dir=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let base=try PromoScene.reference()
        try save(base,to:dir.appendingPathComponent("scene.png"))
        let field=TerrainDetector.analyze(base,logicalSize:PromoScene.size)
        let floor:CGFloat=100, world=CGRect(origin:.zero,size:PromoScene.size)
        let hero=ClimbEngine(bounds:world,floor:floor,terrain:.handholds);hero.webEnabled=true
        let holds=field.holds.filter{$0.minY>floor+34 && $0.maxY<world.maxY-28}.enumerated().map{ index, rect -> Surface in
            var s=Surface(id:UInt32(index+1),frame:rect)
            let mid=CGPoint(x:rect.midX,y:rect.midY)
            if PromoScene.paper.contains(mid) {s.windowID=1}
            if PromoScene.atlas.contains(mid) {s.windowID=2}
            return s
        }
        let write=CommandLine.arguments.count == 4
        let start=write ? Int((Double(CommandLine.arguments[2])! * 60).rounded()) : 0
        let count=write ? Int((Double(CommandLine.arguments[3])! * 60).rounded()) : 60*75
        var outputFrame=0
        for frame in 0..<(start+count) {
            if frame % 6 == 0 { _ = hero.updateGrip(field) }
            let last=hero.phase
            hero.step(1/60,surfaces:holds,mouse:nil)
            if last != hero.phase {
                let owner=hero.support?.windowID ?? 0
                print(String(format:"%6.2f %@  anchorWindow=%d body=(%.0f, %.0f)",Double(frame)/60,hero.phase.rawValue,owner,hero.position.x,hero.position.y))
            }
            if write && frame >= start && (frame-start)%3==0 {
                try autoreleasepool { try save(render(hero,on:base),to:dir.appendingPathComponent(String(format:"frame-%04d.png",outputFrame))) }
                outputFrame+=1
            }
        }
        print("Detected",holds.count,"real pixel ledges. Exported",outputFrame,"frames.")
    }
}
