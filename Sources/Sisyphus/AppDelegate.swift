import AppKit
import ClimbCore
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var screen: NSScreen!
    private var engine: ClimbEngine!
    private var panel: CharacterPanel!
    private var character: CharacterView!
    private let webPanel = WebPanel()
    private var timer: Timer?
    private let tracker = WindowTracker()
    private let source = ScreenTerrainSource()
    private let registry = HoldRegistry()
    private let appearances = AppearanceLibrary()
    private var holds: [Surface] = []
    private var capturedWindows: [Surface] = []
    private var attachment: (hold: UInt32, window: UInt32, frame: CGRect)?
    private var latestTerrain: PixelTerrain?
    private var lastGripProbe: TimeInterval = 0
    private var lastFrame: TimeInterval = 0
    private var lastScan: TimeInterval = 0
    private var lastWindows: TimeInterval = 0
    private var permission = false
    private var receivedDesktopFrame = false
    private var captureFailed = false
    private var reconnectRequested = false
    private var importRequested = false
    private var accessibleStatus = ""
    private var menuOpen = false
    private var dragging = false
    private var hoverFrozen = false
    private var priorPaused = false
    private var dragOffset = CGPoint.zero
    private var pointerIntent = PointerIntent()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let first = NSScreen.screens.first else { NSApp.terminate(nil); return }
        screen = first
        setupCharacter()
        source.onFrame = { [weak self] field in
            guard let self, !self.engine.paused, !self.menuOpen, !self.dragging else { return }
            // A successfully delivered frame is authoritative. Core Graphics'
            // preflight result can remain stale after the user grants access.
            self.permission = true; self.receivedDesktopFrame = true; self.captureFailed = false
            self.acceptTerrain(field)
        }
        source.onFailure = { [weak self] _ in
            guard let self else { return }
            if self.engine.phase.usesWeb { self.engine.fall(.erased) }
            self.holds = []; self.latestTerrain = nil; self.receivedDesktopFrame = false; self.captureFailed = true
            self.permission = CGPreflightScreenCaptureAccess()
        }
        permission = CGPreflightScreenCaptureAccess()
        panel.orderFrontRegardless()
        // Try ScreenCaptureKit itself once, even if the cached preflight says no.
        // macOS presents its own consent prompt when access really is absent.
        reconnectDesktop()
        // Standard app quit shortcut, without a status item, Dock icon or settings window.
        let main = NSMenu(), root = NSMenuItem(title: "Sisyphus", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "Sisyphus")
        let quit = NSMenuItem(title: "退出 Sisyphus", action: #selector(quit), keyEquivalent: "q"); quit.target = self
        appMenu.addItem(quit); root.submenu = appMenu; main.addItem(root); NSApp.mainMenu = main
        lastFrame = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in self?.frame() }
        timer.tolerance = 0.003; RunLoop.main.add(timer, forMode: .common); self.timer = timer
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(waking), name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    private func setupCharacter() {
        let floor = screen.visibleFrame.minY - screen.frame.minY + 40
        engine = ClimbEngine(bounds: CGRect(origin: .zero, size: screen.frame.size), floor: floor, terrain: .handholds)
        panel = CharacterPanel(); character = CharacterView(engine: engine); panel.contentView = character
        applyAppearance()
        character.onMenu = { [weak self] event in self?.showMenu(event) }
        character.onPickUp = { [weak self] in self?.pickUp() }
        character.onDrag = { [weak self] point in self?.drag(to: point) }
        character.onDrop = { [weak self] in self?.drop() }
        panel.place(at: engine.position, screenOrigin: screen.frame.origin)
    }

    private func frame() {
        let now = ProcessInfo.processInfo.systemUptime, dt = now - lastFrame
        lastFrame = now
        let inside = panel.frame.insetBy(dx: 8, dy: 4).contains(NSEvent.mouseLocation)
        let response = pointerIntent.update(inside: inside, now: now, interacting: menuOpen || dragging)
        hoverFrozen = response.freeze && engine.phase != .falling && engine.phase != .recovering
        guard !menuOpen else { return }
        if response.disturb && engine.mouseEnabled && engine.phase.attached { engine.fall(.mouse) }
        if !engine.paused && !dragging {
            if now - lastScan >= 3 {
                if !source.isRunning && (permission || CGPreflightScreenCaptureAccess()) { source.start(on: screen) }
                lastScan = now
            }
            if !hoverFrozen && (receivedDesktopFrame || [.falling, .recovering].contains(engine.phase)) {
                if now - lastWindows >= 0.1 { validateParentWindow(); lastWindows = now }
                if now - lastGripProbe >= 0.1, let field = latestTerrain { _ = engine.updateGrip(field); lastGripProbe = now }
                engine.step(dt, surfaces: holds, mouse: nil)
            }
        }
        panel.place(at: engine.position, screenOrigin: screen.frame.origin)
        webPanel.update(engine, origin: screen.frame.origin, behind: panel)
        let status = engine.paused ? "已暂停" : (captureFailed ? "桌面读取未就绪，请右键重新连接桌面" :
            (!receivedDesktopFrame ? "正在连接桌面" : movementDescription))
        if status != accessibleStatus { character.setAccessibilityValue(status); accessibleStatus = status }
        if !engine.paused && !hoverFrozen || dragging { character.needsDisplay = true }
    }

    private var movementDescription: String {
        switch engine.phase {
        case .webCasting: return "正在发射蛛丝"
        case .webPulling: return "正在用蛛丝跨越空档"
        case .webSwinging: return "正在荡蛛丝"
        case .webHandoff: return "正在交替换丝"
        case .webVault: return "正在翻身接丝"
        case .falling: return "正在掉落"
        default: return engine.phase.attached ? "正在攀爬" : "正在寻找可抓的位置"
        }
    }

    private func acceptTerrain(_ field: PixelTerrain) {
        latestTerrain = field; lastGripProbe = ProcessInfo.processInfo.systemUptime
        let usable = field.holds.filter { $0.minY > engine.floor + 34 && $0.maxY < engine.bounds.maxY - 28 }
        let retained = hoverFrozen ? engine.support : engine.updateGrip(field)
        holds = registry.update(usable)
        capturedWindows = tracker.surfaces(on: screen)
        if engine.webEnabled {
            for index in holds.indices {
                let r = holds[index].frame
                holds[index].windowID = capturedWindows.first { $0.frame.contains(CGPoint(x: r.midX, y: r.midY)) }?.id
            }
        }
        if let retained { holds.removeAll { $0.id == retained.id }; holds.append(retained) }
    }

    private func validateParentWindow() {
        guard let support = engine.support, engine.phase.attached else { attachment = nil; return }
        let contact = engine.webAnchor ?? CGPoint(x: support.frame.midX, y: support.frame.midY)
        if attachment?.hold != support.id {
            attachment = capturedWindows.first(where: { $0.frame.contains(contact) }).map { (support.id, $0.id, $0.frame) }
        }
        guard let attached = attachment, attached.hold == support.id else { return }
        let current = tracker.surfaces(on: screen)
        guard let after = current.first(where: { $0.id == attached.window })?.frame else { engine.fall(.closed); return }
        let before = attached.frame
        if max(abs(before.minX - after.minX), abs(before.minY - after.minY), abs(before.width - after.width), abs(before.height - after.height)) > 2 { engine.fall(.moved); return }
        for window in current {
            if window.id == attached.window { break }
            if window.frame.contains(contact) { engine.fall(.covered); break }
        }
    }

    private func pickUp() {
        guard !menuOpen else { return }
        dragging = true; source.stop()
        let mouse = NSEvent.mouseLocation
        dragOffset = CGPoint(x: mouse.x - screen.frame.minX - engine.position.x, y: mouse.y - screen.frame.minY - engine.position.y)
        engine.beginDrag(); attachment = nil; pointerIntent.protect(after: ProcessInfo.processInfo.systemUptime)
        character.needsDisplay = true
    }
    private func drag(to mouse: CGPoint) {
        guard dragging else { return }
        engine.drag(to: CGPoint(x: mouse.x - screen.frame.minX - dragOffset.x, y: mouse.y - screen.frame.minY - dragOffset.y))
        panel.place(at: engine.position, screenOrigin: screen.frame.origin); character.needsDisplay = true
    }
    private func drop() {
        guard dragging else { return }
        dragging = false; engine.endDrag(); pointerIntent.protect(after: ProcessInfo.processInfo.systemUptime)
        lastScan = 0; latestTerrain = nil; character.needsDisplay = true
    }

    private func showMenu(_ event: NSEvent?) {
        guard !dragging && !menuOpen else { return }
        menuOpen = true; source.stop()
        let menu = NSMenu()
        func item(_ title: String, _ action: Selector, into targetMenu: NSMenu? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self
            (targetMenu ?? menu).addItem(item); return item
        }
        if !receivedDesktopFrame {
            let status = NSMenuItem(title: "桌面读取尚未生效", action: nil, keyEquivalent: "")
            status.isEnabled = false; menu.addItem(status)
            _ = item("重新连接桌面", #selector(reconnectDesktop))
            _ = item("屏幕录制权限…", #selector(requestPermission)); menu.addItem(.separator())
        }
        _ = item(engine.paused ? "继续攀爬" : "暂停", #selector(togglePause))
        _ = item("重新出发", #selector(restart))
        let looks = NSMenuItem(title: "外观", action: nil, keyEquivalent: "")
        let looksMenu = NSMenu(title: "外观")
        for entry in appearances.entries {
            let choice = item(entry.name, #selector(changeAppearance(_:)), into: looksMenu)
            choice.representedObject = entry.id; choice.state = entry.id == appearances.selectedID ? .on : .off
        }
        looksMenu.addItem(.separator())
        _ = item("导入角色…", #selector(requestImport), into: looksMenu)
        looks.submenu = looksMenu; menu.addItem(looks)
        let settings = NSMenuItem(title: "设置", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "设置")
        let mouse = item("鼠标掠过时掉落", #selector(toggleMouse), into: submenu); mouse.state = engine.mouseEnabled ? .on : .off
        submenu.addItem(.separator())
        for (label, value) in [("慢慢爬", 0.7), ("正常速度", 1.0), ("轻快一点", 1.5)] {
            let speed = item(label, #selector(changeSpeed(_:)), into: submenu)
            speed.representedObject = value; speed.state = engine.speed == value ? .on : .off
        }
        settings.submenu = submenu; menu.addItem(settings)
        menu.addItem(.separator()); _ = item("退出", #selector(quit))
        if let event { NSMenu.popUpContextMenu(menu, with: event, for: character) }
        else { menu.popUp(positioning: nil, at: CGPoint(x: 60, y: 62), in: character) }
        menuOpen = false; pointerIntent.protect(after: ProcessInfo.processInfo.systemUptime)
        lastFrame = ProcessInfo.processInfo.systemUptime; lastScan = 0; latestTerrain = nil
        if importRequested { importRequested = false; importCharacter() }
        if reconnectRequested { reconnectRequested = false; reconnectDesktop() }
    }
    private func applyAppearance() {
        engine.webEnabled = appearances.selectedID == AppearanceLibrary.spiderID
        character.spritePack = appearances.selected.pack
        character.setAccessibilityLabel(appearances.selected.name)
    }
    @objc private func changeAppearance(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        appearances.select(id); applyAppearance()
    }
    @objc private func requestImport() { importRequested = true }
    private func importCharacter() {
        menuOpen = true; source.stop()
        defer {
            menuOpen = false; pointerIntent.protect(after: ProcessInfo.processInfo.systemUptime)
            lastFrame = ProcessInfo.processInfo.systemUptime; lastScan = 0; latestTerrain = nil
        }
        let picker = NSOpenPanel()
        picker.title = "导入角色"
        picker.message = "选择透明 PNG、character.json，或含 shime1.png 的 Shimeji 图片文件夹。"
        picker.prompt = "导入"
        picker.canChooseFiles = true; picker.canChooseDirectories = true; picker.allowsMultipleSelection = false
        picker.allowedContentTypes = [.png, .json, .folder]
        NSApp.activate(ignoringOtherApps: true)
        guard picker.runModal() == .OK, let url = picker.url else { return }
        do { try appearances.importCharacter(from: url); applyAppearance() }
        catch {
            let alert = NSAlert(); alert.messageText = "这个角色暂时无法导入"
            alert.informativeText = error.localizedDescription; alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }
    @objc private func reconnectDesktop() {
        guard !menuOpen else { reconnectRequested = true; return }
        if engine.phase.usesWeb { engine.fall(.erased) }
        source.stop(); holds = []; latestTerrain = nil; receivedDesktopFrame = false; captureFailed = false
        lastScan = ProcessInfo.processInfo.systemUptime
        source.start(on: screen)
    }
    @objc private func requestPermission() {
        if CGPreflightScreenCaptureAccess() { permission = true; return }
        permission = CGRequestScreenCaptureAccess()
        if !permission, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }
    @objc private func togglePause() { engine.paused.toggle(); if engine.paused { source.stop() }; lastScan = 0 }
    @objc private func restart() { engine.restart(); attachment = nil; lastScan = 0 }
    @objc private func toggleMouse() { engine.mouseEnabled.toggle() }
    @objc private func changeSpeed(_ sender: NSMenuItem) { if let value = sender.representedObject as? Double { engine.speed = value } }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func sleeping() { priorPaused = engine.paused; engine.paused = true; source.stop() }
    @objc private func waking() { engine.paused = priorPaused; lastFrame = ProcessInfo.processInfo.systemUptime; lastScan = 0 }
    @objc private func screenChanged() {
        guard let next = NSScreen.screens.first, screen.frame != next.frame || screen.visibleFrame != next.visibleFrame else { return }
        source.stop(); panel.close(); screen = next
        holds = []; latestTerrain = nil; registry.reset(); capturedWindows = []; webPanel.orderOut(nil); attachment = nil
        setupCharacter(); panel.orderFrontRegardless(); lastScan = 0
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { panel.orderFrontRegardless(); return false }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); source.stop(); webPanel.orderOut(nil); panel?.orderOut(nil) }
}
