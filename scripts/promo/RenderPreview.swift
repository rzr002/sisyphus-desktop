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
        let view = hero.projection
        for strand in hero.displayStrands { SpiderRenderer.silk(strand, scale: view.scale, in: c) }
        c.translateBy(x:view.body.x-CharacterPanel.pivot.x*view.scale,y:view.body.y-CharacterPanel.pivot.y*view.scale)
        SpiderRenderer.body(hero,in:c)
        return c.makeImage()!
    }
    static func main() throws {
        let drop = CommandLine.arguments.last == "--drop"
        let args = drop ? Array(CommandLine.arguments.dropLast()) : CommandLine.arguments
        guard args.count == 2 || args.count == 4 else {
            print("Usage: render-preview SCRATCH_DIRECTORY [START_SECONDS DURATION_SECONDS] [--drop]");return
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
        let write=args.count == 4
        let start=write ? Int((Double(args[2])! * 60).rounded()) : 0
        let count=write ? Int((Double(args[3])! * 60).rounded()) : 60*75
        var outputFrame=0, near: CGFloat=0, far: CGFloat=2
        if drop { hero.beginDrag(); hero.drag(to:CGPoint(x:537,y:432)) }
        for frame in 0..<(start+count) {
            if drop && frame == 16 { hero.endDrag() }
            if frame % 6 == 0 { _ = hero.updateGrip(field) }
            let last=hero.phase
            hero.step(1/60,surfaces:holds,mouse:nil)
            if frame >= start { near=max(near,hero.projection.scale); far=min(far,hero.projection.scale) }
            if last != hero.phase {
                let owner=hero.support?.windowID ?? 0
                print(String(format:"%6.2f %@  anchorWindow=%d body=(%.0f, %.0f)",Double(frame)/60,hero.phase.rawValue,owner,hero.position.x,hero.position.y))
            }
            if write && frame >= start && (frame-start)%3==0 {
                try autoreleasepool { try save(render(hero,on:base),to:dir.appendingPathComponent(String(format:"frame-%04d.png",outputFrame))) }
                outputFrame+=1
            }
        }
        print(String(format: "Depth range %.2fx to %.2fx.",far,near),"Detected",holds.count,"real pixel ledges. Exported",outputFrame,"frames.")
    }
}
