import AppKit
import ScreenCaptureKit
import CoreImage
import CoreMedia
import CoreVideo
import ClimbCore
import os

final class HoldRegistry {
    private var previous: [Surface] = []
    private var nextID: UInt32 = 100_000
    func reset() { previous = [] }
    func update(_ rects: [CGRect]) -> [Surface] {
        var used: Set<UInt32> = []
        func key(_ x: Int, _ y: Int) -> Int { x + y * 8192 }
        var buckets: [Int: [Surface]] = [:]
        for surface in previous {
            let x = Int(floor(surface.frame.midX / 32)), y = Int(floor(surface.frame.midY / 16))
            buckets[key(x, y), default: []].append(surface)
        }
        let result = rects.map { rect -> Surface in
            let x = Int(floor(rect.midX / 32)), y = Int(floor(rect.midY / 16))
            var nearby: [Surface] = []
            for dx in -1...1 { for dy in -1...1 { nearby += buckets[key(x + dx, y + dy)] ?? [] } }
            let match = nearby.filter { !used.contains($0.id) &&
                abs($0.frame.midX - rect.midX) < 15 && abs($0.frame.midY - rect.midY) < 10 &&
                min($0.frame.width, rect.width) / max($0.frame.width, rect.width) > 0.55
            }.min { hypot($0.frame.midX - rect.midX, $0.frame.midY - rect.midY) < hypot($1.frame.midX - rect.midX, $1.frame.midY - rect.midY) }
            let id: UInt32
            if let match { id = match.id; used.insert(id) }
            else { nextID += 1; id = nextID }
            return Surface(id: id, name: "纹理支点", frame: rect)
        }
        previous = result
        return result
    }
}

private final class TerrainStreamOutput: NSObject, SCStreamOutput {
    let size: CGSize
    let onFrame: (PixelTerrain) -> Void
    let onUnavailable: () -> Void
    let context = CIContext(options: [.cacheIntermediates: false])
    init(size: CGSize, onFrame: @escaping (PixelTerrain) -> Void, onUnavailable: @escaping () -> Void) {
        self.size = size; self.onFrame = onFrame; self.onUnavailable = onUnavailable
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer),
              let info = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = info.first?[.status] as? Int else { return }
        if status == SCFrameStatus.blank.rawValue || status == SCFrameStatus.suspended.rawValue {
            DispatchQueue.main.async { [onUnavailable] in onUnavailable() }; return
        }
        guard status == SCFrameStatus.complete.rawValue, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        autoreleasepool {
            let input = CIImage(cvPixelBuffer: buffer)
            guard let image = context.createCGImage(input, from: input.extent) else { return }
            let field = TerrainDetector.analyze(image, logicalSize: size)
            DispatchQueue.main.async { [onFrame] in onFrame(field) }
        }
    }
}

final class ScreenTerrainSource: NSObject, SCStreamDelegate {
    var onFrame: ((PixelTerrain) -> Void)?
    var onFailure: ((Error) -> Void)?
    var onUnavailable: (() -> Void)?
    private let logger = Logger(subsystem: "studio.leosnow.sisyphus", category: "DesktopCapture")
    private(set) var isRunning = false
    private var stream: SCStream?
    private var output: TerrainStreamOutput?
    private var version = 0
    private let queue = DispatchQueue(label: "studio.leosnow.sisyphus.pixel-terrain", qos: .userInitiated)
    func start(on screen: NSScreen) {
        guard !isRunning else { return }
        isRunning = true; version += 1
        let token = version, size = screen.frame.size
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        let pid = ProcessInfo.processInfo.processIdentifier
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { [weak self] content, error in
            DispatchQueue.main.async {
                guard let self, self.version == token else { return }
                guard let content, let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    self.failed(error ?? NSError(domain: "Sisyphus", code: 1, userInfo: [NSLocalizedDescriptionKey: "没有找到可读取的显示器。"])); return
                }
                let filter = SCContentFilter(display: display, excludingApplications: content.applications.filter { $0.processID == pid }, exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.width = Int(size.width); config.height = Int(size.height)
                config.minimumFrameInterval = CMTime(value: 1, timescale: 10)
                config.queueDepth = 3; config.showsCursor = false; config.capturesAudio = false
                config.ignoreShadowsDisplay = true; config.pixelFormat = kCVPixelFormatType_32BGRA
                let output = TerrainStreamOutput(size: size, onFrame: { [weak self] field in
                    guard let self, self.version == token, self.isRunning else { return }
                    self.onFrame?(field)
                }, onUnavailable: { [weak self] in
                    guard let self, self.version == token, self.isRunning else { return }
                    self.onUnavailable?()
                })
                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                self.output = output; self.stream = stream
                do { try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: self.queue) }
                catch { self.failed(error); return }
                stream.startCapture { [weak self] error in
                    if let error { DispatchQueue.main.async {
                        guard let self, self.version == token else { return }
                        self.failed(error)
                    } }
                }
            }
        }
    }
    private func failed(_ error: Error) {
        stop()
        logger.error("Desktop capture failed: \(error.localizedDescription, privacy: .public)")
        onFailure?(error)
    }
    func stop() {
        version += 1; isRunning = false
        let old = stream; stream = nil; output = nil
        old?.stopCapture { _ in }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.stream = nil; self.output = nil; self.failed(error)
        }
    }
    private(set) var busy = false
    func capture(on screen: NSScreen, completion: @escaping (Result<[CGRect], Error>) -> Void) {
        guard !busy else { return }
        busy = true
        let size = screen.frame.size
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        let ownPID = ProcessInfo.processInfo.processIdentifier
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { [weak self] content, error in
            guard let content, let display = content.displays.first(where: { $0.displayID == displayID }) else {
                DispatchQueue.main.async { self?.busy = false; completion(.failure(error ?? NSError(domain: "Sisyphus", code: 1, userInfo: [NSLocalizedDescriptionKey: "暂时无法读取这块屏幕。"]))) }
                return
            }
            // Excluding this app prevents the climber, labels and camp becoming footholds.
            let excluded = content.windows.filter { $0.owningApplication?.processID == ownPID }
            let filter = SCContentFilter(display: display, excludingWindows: excluded)
            let config = SCStreamConfiguration()
            config.width = Int(size.width); config.height = Int(size.height)
            config.showsCursor = false; config.capturesAudio = false
            config.ignoreShadowsDisplay = true
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, error in
                guard let image else {
                    DispatchQueue.main.async { self?.busy = false; completion(.failure(error ?? NSError(domain: "Sisyphus", code: 2))) }
                    return
                }
                DispatchQueue.global(qos: .utility).async {
                    let holds = TerrainDetector.detect(image, logicalSize: size)
                    DispatchQueue.main.async { self?.busy = false; completion(.success(holds)) }
                }
            }
        }
    }
}
