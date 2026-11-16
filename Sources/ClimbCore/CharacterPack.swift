import Foundation
import CoreGraphics
import ImageIO

public struct SpriteClip: Codable {
    public let frames: [Int]
    public let fps: Double
    public let anchor: [Double]?
    public init(frames: [Int], fps: Double, anchor: [Double]? = nil) {
        self.frames = frames; self.fps = fps; self.anchor = anchor
    }
}

public struct CharacterManifest: Codable {
    public var version: Int
    public var name: String
    public var image: String
    public var columns: Int
    public var rows: Int
    public var renderHeight: Double?
    public var facesRight: Bool?
    public var animations: [String: SpriteClip]
}

public struct CharacterPackError: LocalizedError {
    public let errorDescription: String?
    init(_ description: String) { errorDescription = description }
}

/// Local image data only. Importing a pack never executes its code or scripts.
public final class CharacterPack {
    public let manifest: CharacterManifest
    public let image: CGImage
    private var frameCache: [Int: CGImage] = [:]
    private init(manifest: CharacterManifest, image: CGImage) {
        self.manifest = manifest; self.image = image
    }

    public static func load(from url: URL) throws -> CharacterPack {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let manifest = url.appendingPathComponent("character.json")
            if FileManager.default.fileExists(atPath: manifest.path) { return try load(from: manifest) }
            return try loadShimeji(from: url)
        }
        if url.pathExtension.lowercased() == "png" {
            let image = try readPNG(url)
            let manifest = CharacterManifest(version: 1, name: String(url.deletingPathExtension().lastPathComponent.prefix(40)),
                image: "sprite.png", columns: 1, rows: 1, animations: ["idle": SpriteClip(frames: [0], fps: 1)])
            return CharacterPack(manifest: manifest, image: image)
        }
        guard url.pathExtension.lowercased() == "json" else { throw CharacterPackError("请选择透明 PNG、character.json 或 Shimeji 图片文件夹。") }
        guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 262_144 else {
            throw CharacterPackError("角色配置文件过大。")
        }
        let manifest: CharacterManifest
        do { manifest = try JSONDecoder().decode(CharacterManifest.self, from: Data(contentsOf: url)) }
        catch { throw CharacterPackError("角色配置格式不正确，请检查 character.json。") }
        try validate(manifest)
        let directory = url.deletingLastPathComponent().resolvingSymlinksInPath()
        let imageURL = directory.appendingPathComponent(manifest.image).resolvingSymlinksInPath()
        guard imageURL.deletingLastPathComponent() == directory else { throw CharacterPackError("角色图片必须保存在配置文件同一目录中。") }
        let image = try readPNG(imageURL)
        guard image.width % manifest.columns == 0, image.height % manifest.rows == 0 else {
            throw CharacterPackError("图片尺寸必须能被精灵图的列数和行数整除。")
        }
        return CharacterPack(manifest: manifest, image: image)
    }

    private static func validate(_ value: CharacterManifest) throws {
        guard value.version == 1, !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.name.count <= 80, (1...16).contains(value.columns), (1...16).contains(value.rows),
              value.animations["idle"] != nil, value.animations.count <= 12 else {
            throw CharacterPackError("角色版本、名称、行列数或 idle 动作不正确。")
        }
        guard !value.image.contains("/"), !value.image.contains("\\"), value.image.lowercased().hasSuffix(".png") else {
            throw CharacterPackError("图片名称只能是同目录内的 PNG 文件名。")
        }
        if let height = value.renderHeight, !height.isFinite || !(64...120).contains(height) {
            throw CharacterPackError("角色显示高度应在 64–120 点之间。")
        }
        for clip in value.animations.values {
            guard !clip.frames.isEmpty, clip.frames.count <= 256, clip.fps.isFinite, clip.fps > 0, clip.fps <= 30,
                  clip.frames.allSatisfy({ $0 >= 0 && $0 < value.rows * value.columns }) else {
                throw CharacterPackError("动作帧编号超出精灵图范围，或播放速度不正确。")
            }
            if let anchor = clip.anchor, anchor.count != 2 || !anchor.allSatisfy({ $0.isFinite && (0...1).contains($0) }) {
                throw CharacterPackError("动作锚点应是两个 0–1 之间的数。")
            }
        }
    }

    private static func readPNG(_ url: URL) throws -> CGImage {
        guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 32 * 1024 * 1024,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetType(source) as String? == "public.png",
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = props[kCGImagePropertyPixelWidth as String] as? Int,
              let height = props[kCGImagePropertyPixelHeight as String] as? Int,
              width > 0, height > 0, width <= 8192, height <= 8192, width * height <= 16_777_216,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CharacterPackError("无法读取 PNG，或图片超过 32 MB / 1600 万像素。")
        }
        return image
    }

    public func animationName(for phase: Phase) -> String {
        switch phase {
        case .walking, .searching: return "walk"
        case .climbing, .reaching, .traversing: return "climb"
        case .jumping, .falling: return "fall"
        case .dragging: return "drag"
        case .recovering: return "recover"
        default: return "idle"
        }
    }
    public func clip(for phase: Phase) -> SpriteClip { manifest.animations[animationName(for: phase)] ?? manifest.animations["idle"]! }
    public func frameIndex(for phase: Phase, time: Double) -> Int {
        let clip = clip(for: phase)
        guard time.isFinite else { return clip.frames[0] }
        let cycle = max(0, time).truncatingRemainder(dividingBy: Double(clip.frames.count) / clip.fps)
        return clip.frames[min(clip.frames.count - 1, Int(cycle * clip.fps))]
    }
    public func sourceRect(for index: Int) -> CGRect {
        let width = image.width / manifest.columns, height = image.height / manifest.rows
        return CGRect(x: (index % manifest.columns) * width, y: (index / manifest.columns) * height, width: width, height: height)
    }
    public func sprite(for phase: Phase, time: Double) -> CGImage {
        let index = frameIndex(for: phase, time: time)
        if let cached = frameCache[index] { return cached }
        let frame = image.cropping(to: sourceRect(for: index))!
        frameCache[index] = frame; return frame
    }

    /// Copy verified pixels into a self-contained pack before selecting it.
    public func install(into directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let identifier = UUID().uuidString
        let staging = directory.appendingPathComponent(".import-" + identifier)
        let destination = directory.appendingPathComponent(identifier)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            var normalized = manifest; normalized.image = "sprite.png"
            let imageURL = staging.appendingPathComponent(normalized.image)
            guard let writer = CGImageDestinationCreateWithURL(imageURL as CFURL, "public.png" as CFString, 1, nil) else {
                throw CharacterPackError("无法保存角色图片。")
            }
            CGImageDestinationAddImage(writer, image, nil)
            guard CGImageDestinationFinalize(writer) else { throw CharacterPackError("保存角色图片失败。") }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(normalized).write(to: staging.appendingPathComponent("character.json"), options: .atomic)
            try FileManager.default.moveItem(at: staging, to: destination)
            return destination.appendingPathComponent("character.json")
        } catch { try? FileManager.default.removeItem(at: staging); throw error }
    }

    private static func loadShimeji(from directory: URL) throws -> CharacterPack {
        var base = directory
        if !FileManager.default.fileExists(atPath: base.appendingPathComponent("shime1.png").path) {
            base = directory.appendingPathComponent("img")
        }
        guard FileManager.default.fileExists(atPath: base.appendingPathComponent("shime1.png").path) else {
            throw CharacterPackError("请选中含 shime1.png 的 Shimeji 图片目录，或含 character.json 的角色包。")
        }
        let numbers = [1, 2, 3, 4, 5, 6, 11, 14, 15, 16]
        var pictures: [(Int, CGImage)] = []
        for number in numbers {
            let url = base.appendingPathComponent("shime\(number).png").resolvingSymlinksInPath()
            guard url.deletingLastPathComponent() == base.resolvingSymlinksInPath() else { throw CharacterPackError("Shimeji 图片不能指向目录之外。") }
            if FileManager.default.fileExists(atPath: url.path) {
                let picture = try readPNG(url)
                guard picture.width <= 1024, picture.height <= 1024 else { throw CharacterPackError("每张 Shimeji 动作图应不超过 1024 × 1024 像素。") }
                pictures.append((number, picture))
            }
        }
        let side = min(512, max(pictures.map { max($0.1.width, $0.1.height) }.max() ?? 128, 16))
        let columns = 4, rows = Int(ceil(Double(pictures.count) / 4))
        guard let context = CGContext(data: nil, width: side * columns, height: side * rows, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CharacterPackError("无法处理 Shimeji 图片。")
        }
        var indices: [Int: Int] = [:]
        for (index, entry) in pictures.enumerated() {
            indices[entry.0] = index
            let factor = min(1, CGFloat(side) / CGFloat(max(entry.1.width, entry.1.height)))
            let w = CGFloat(entry.1.width) * factor, h = CGFloat(entry.1.height) * factor
            context.draw(entry.1, in: CGRect(x: CGFloat(index % columns * side) + (CGFloat(side) - w) / 2,
                y: CGFloat((rows - 1 - index / columns) * side), width: w, height: h))
        }
        func clip(_ numbers: [Int], _ fps: Double) -> SpriteClip {
            let frames = numbers.compactMap { indices[$0] }
            return SpriteClip(frames: frames.isEmpty ? [0] : frames, fps: fps)
        }
        let manifest = CharacterManifest(version: 1, name: String(directory.lastPathComponent.prefix(40)), image: "sprite.png",
            columns: columns, rows: rows, renderHeight: 104, facesRight: false,
            animations: ["idle": clip([1], 1), "walk": clip([1, 2, 1, 3], 7), "climb": clip([14, 15, 16, 15], 5),
                         "fall": clip([4], 1), "drag": clip([5, 6], 4), "recover": clip([11, 1], 2)])
        return CharacterPack(manifest: manifest, image: context.makeImage()!)
    }
}
