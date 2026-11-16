#if DEBUG
import AppKit
import ClimbCore

enum NativeChecks {
    /// Read-only diagnosis: feed actual visible pixels through the production
    /// detector and movement engine. No fixture windows or saved screenshots.
    static func diagnoseDesktop() {
        guard let screen = NSScreen.screens.first, CGPreflightScreenCaptureAccess() else {
            print("{\"permission\":false}"); exit(2)
        }
        let source = ScreenTerrainSource()
        var field: PixelTerrain?
        source.onFrame = { field = $0 }
        source.start(on: screen)
        let deadline = Date(timeIntervalSinceNow: 8)
        while field == nil && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
        source.stop()
        guard let field else { print("{\"permission\":true,\"frames\":0}"); exit(3) }
        let floor = screen.visibleFrame.minY - screen.frame.minY + 40
        let engine = ClimbEngine(bounds: CGRect(origin: .zero, size: screen.frame.size), floor: floor, terrain: .handholds)
        let registry = HoldRegistry()
        let holds = registry.update(field.holds.filter { $0.minY > floor + 34 && $0.maxY < screen.frame.height - 28 })
        var trace: [[String: Any]] = []
        for frame in 0..<3600 {
            if frame % 6 == 0 { _ = engine.updateGrip(field) }
            engine.step(1 / 60, surfaces: holds, mouse: nil)
            if frame % 300 == 0 {
                trace.append(["second": frame / 60, "phase": engine.phase.rawValue,
                              "x": engine.position.x, "y": engine.position.y,
                              "hold": engine.support.map { NSStringFromRect($0.frame) } ?? "none"])
            }
        }
        let report: [String: Any] = ["permission": true, "floor": floor, "holds": holds.count,
                                    "height": engine.bestHeight, "falls": engine.falls, "trace": trace]
        let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8)!); exit(0)
    }

    static func run() {
        guard let screen = NSScreen.screens.first else { print("{\"checks\":{\"displayAvailable\":false}}"); exit(1) }
        var checks: [String: Bool] = [:]
        let overlay = CharacterPanel()
        checks["inputWindowIsOnlyCharacterSized"] = overlay.frame.width <= 100 && overlay.frame.height <= 120 && !overlay.ignoresMouseEvents
        checks["characterDoesNotStealKeyboardFocus"] = !overlay.canBecomeKey && !overlay.canBecomeMain
        checks["overlayTransparent"] = !overlay.isOpaque && overlay.backgroundColor.alphaComponent == 0
        let practice = PracticeWindow(screen: screen)
        practice.orderFrontRegardless()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        let id = UInt32(practice.windowNumber)
        let tracker = WindowTracker(); tracker.testWindowIDs = [id]
        let before = tracker.surfaces(on: screen).first { $0.id == id }
        checks["nativeWindowDetected"] = before != nil
        practice.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue + 1)
        checks["floatingDocumentCanOwnAnAnchor"] = tracker.surfaces(on: screen).contains { $0.id == id }
        practice.level = .normal
        let detected = practice.terrainView.detectedHolds(screen: screen)
        checks["practiceTextDetectedFromPixels"] = detected.count >= 12
        let document = practice.terrainView.editor.string
        let contentOrigin = practice.convertPoint(toScreen: .zero)
        let documentRect = practice.terrainView.editor.frame.offsetBy(dx: contentOrigin.x - screen.frame.minX, dy: contentOrigin.y - screen.frame.minY)
        let beforeDocument = detected.filter { documentRect.contains(CGPoint(x: $0.midX, y: $0.midY)) }.count
        practice.terrainView.editor.string = ""
        let afterDocument = practice.terrainView.detectedHolds(screen: screen).filter { documentRect.contains(CGPoint(x: $0.midX, y: $0.midY)) }.count
        checks["editableDocumentDeletionChangesPixels"] = beforeDocument > 0 && afterDocument == 0
        practice.terrainView.editor.string = document
        let split = practice.frame.minX - screen.frame.minX + practice.terrainView.bounds.width * 0.57
        checks["practiceSmoothCenterHasNoHolds"] = !detected.contains { $0.midX > split + 20 && $0.midY < practice.frame.midY }
        practice.setFrameOrigin(CGPoint(x: practice.frame.minX + 21, y: practice.frame.minY))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.18))
        let after = tracker.surfaces(on: screen).first { $0.id == id }
        checks["nativeWindowMovementObserved"] = before != nil && after != nil && abs(after!.frame.minX - before!.frame.minX - 21) < 1
        practice.terrainView.smooth = true
        checks["removingTextRemovesAllPracticeHolds"] = practice.terrainView.detectedHolds(screen: screen).isEmpty
        practice.orderOut(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.18))
        checks["nativeWindowClosureObserved"] = !tracker.surfaces(on: screen).contains { $0.id == id }
        let engine = ClimbEngine(bounds: CGRect(origin: .zero, size: screen.frame.size), floor: 40, terrain: .handholds)
        let character = CharacterView(engine: engine)
        var menuCalled = false; character.onMenu = { _ in menuCalled = true }
        checks["contextMenuIsAccessible"] = character.accessibilityPerformShowMenu() && menuCalled
        checks["backgroundCharacterAcceptsFirstClick"] = character.acceptsFirstMouse(for: nil)
        let image = NSImage(size: CGSize(width: 96, height: 120))
        image.lockFocus()
        if let c = NSGraphicsContext.current?.cgContext {
            ClimberArt.draw(in: c, at: CGPoint(x: 48, y: 45), phase: .reaching, time: 0.3, handholds: true)
        }
        image.unlockFocus()
        checks["climberVectorRendering"] = image.tiffRepresentation != nil
        let skinRoot = FileManager.default.temporaryDirectory.appendingPathComponent("sisyphus-appearance-check-\(UUID().uuidString)")
        let suite = "studio.leosnow.sisyphus.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: skinRoot); defaults.removePersistentDomain(forName: suite) }
        let library = AppearanceLibrary(defaults: defaults, directory: skinRoot)
        checks["bundledCharacterIsDefault"] = library.selected.name.contains("新条茜") && library.selected.pack != nil
        if let pack = library.selected.pack {
            let preview = NSImage(size: CharacterPanel.canvas)
            preview.lockFocus()
            if let c = NSGraphicsContext.current?.cgContext { SpriteArt.draw(pack, in: c, phase: .climbing, time: 0.3, facing: -1) }
            preview.unlockFocus()
            checks["spriteRendererDecodesAnimation"] = preview.tiffRepresentation != nil
            // Draw beyond the panel's bounds to detect real sprite clipping,
            // including mirrored poses at the opposite screen edge.
            var contained = true
            for direction: CGFloat in [-1, 1] {
                for time in [0.0, 0.25, 0.5, 0.75] {
                    let context = CGContext(data: nil, width: 160, height: 176, bitsPerComponent: 8, bytesPerRow: 640,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    context.translateBy(x: 32, y: 32)
                    SpriteArt.draw(pack, in: context, phase: .climbing, time: time, facing: direction)
                    let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
                    for y in 0..<176 {
                        for x in 0..<160 where x < 32 || x >= 128 || y < 32 || y >= 144 {
                            if pixels[(y * 160 + x) * 4 + 3] > 24 { contained = false }
                        }
                    }
                }
            }
            checks["backClimbingFramesFitBothDirections"] = contained
            do {
                let source = try pack.install(into: skinRoot.appendingPathComponent("source"))
                try library.importCharacter(from: source)
                let selected = library.selectedID
                let reopened = AppearanceLibrary(defaults: defaults, directory: skinRoot)
                checks["importSelectionSurvivesRelaunch"] = reopened.selectedID == selected && reopened.selected.pack != nil
                reopened.select("builtin.climber")
                checks["originalCharacterRemainsSelectable"] = reopened.selected.pack == nil
            } catch { checks["importSelectionSurvivesRelaunch"] = false }
        }
        library.select(AppearanceLibrary.spiderID)
        checks["spiderIsAnOptionalPersistentCharacter"] = library.selected.name == "蜘蛛侠" &&
            AppearanceLibrary(defaults: defaults, directory: skinRoot).selectedID == AppearanceLibrary.spiderID
        let thread = WebPanel()
        checks["webPanelPassesClicksThrough"] = thread.ignoresMouseEvents && !thread.canBecomeKey && !thread.canBecomeMain
        var completePoses = true
        for phase: Phase in [.climbing, .webCasting, .webPulling, .webSwinging, .falling, .recovering] {
            for side: CGFloat in [-1, 1] {
                let bitmap = CGContext(data: nil, width: 144, height: 160, bitsPerComponent: 8, bytesPerRow: 576,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                bitmap.translateBy(x: 24, y: 24)
                SpiderArt.draw(in: bitmap, phase: phase, time: 0.6, facing: side, angle: side * 0.92)
                let pixels = bitmap.data!.assumingMemoryBound(to: UInt8.self)
                var visible = 0
                for y in 0..<160 {
                    for x in 0..<144 where pixels[(y * 144 + x) * 4 + 3] > 20 {
                        visible += 1
                        if !(24..<120).contains(x) || !(24..<136).contains(y) { completePoses = false }
                    }
                }
                if visible < 650 { completePoses = false }
            }
        }
        checks["spiderPosesVisibleAndUnclipped"] = completePoses
        var screenHoldCount = -1
        if CGPreflightScreenCaptureAccess() {
            let source = ScreenTerrainSource()
            var completed = false
            source.capture(on: screen) { result in
                if case .success(let rects) = result { checks["screenTerrainReadback"] = true; screenHoldCount = rects.count }
                else { checks["screenTerrainReadback"] = false }
                completed = true
            }
            let deadline = Date(timeIntervalSinceNow: 10)
            while !completed && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
            if !completed { checks["screenTerrainReadback"] = false }
            withExtendedLifetime(source) {}
            let streamingSource = ScreenTerrainSource()
            var receivedFrame = false
            streamingSource.onFrame = { _ in receivedFrame = true }
            streamingSource.start(on: screen)
            let streamDeadline = Date(timeIntervalSinceNow: 6)
            while !receivedFrame && Date() < streamDeadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
            checks["continuousScreenTerrainReadback"] = receivedFrame
            streamingSource.stop()
        }
        let report: [String: Any] = ["checks": checks, "detectedPracticeHolds": detected.count,
                                    "detectedScreenHolds": screenHoldCount,
                                    "screenCapturePermission": CGPreflightScreenCaptureAccess(),
                                    "note": "Only this test process's own windows were moved and hidden."]
        let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8)!)
        practice.close(); overlay.close()
        exit(checks.values.allSatisfy { $0 } ? 0 : 1)
    }
}
#endif
