import Foundation
import CoreGraphics
import ImageIO
import ClimbCore

struct CheckFailure: Error, CustomStringConvertible { let description: String }
func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure(description: message) }
}
let world = CGRect(x: 0, y: 0, width: 1200, height: 900)
let wall = Surface(id: 1, name: "Browser", frame: CGRect(x: 420, y: 80, width: 500, height: 650))
func tick(_ e: ClimbEngine, seconds: Double, surfaces: [Surface], mouse: CGPoint? = nil) {
    for _ in 0..<Int(seconds * 60) { e.step(1 / 60, surfaces: surfaces, mouse: mouse) }
}
func attached() throws -> ClimbEngine {
    let e = ClimbEngine(bounds: world, floor: 40)
    tick(e, seconds: 5, surfaces: [wall])
    try expect(e.phase == .climbing, "Expected climber to grab a real window after approaching; got \(e.phase)")
    return e
}
var failed = 0
var passed = 0
func check(_ name: String, _ body: () throws -> Void) {
    do { try body(); print("PASS  \(name)"); passed += 1 }
    catch { print("FAIL  \(name): \(error)"); failed += 1 }
}

check("Approach a window from the desktop floor, then climb upward") {
    let e = try attached(); let y = e.position.y
    tick(e, seconds: 1, surfaces: [wall])
    try expect(e.position.y > y + 15, "Climbing should make upward progress")
    try expect(e.support?.id == wall.id, "Must attach to a real surface")
}
check("Closing the supporting window releases the climber") {
    let e = try attached(); e.step(1 / 60, surfaces: [], mouse: nil)
    try expect(e.phase == .falling && e.lastFall == .closed, "Closing must cause a fall")
}
check("Moving the supporting window releases the climber") {
    let e = try attached(); var moved = wall; moved.frame.origin.x += 14
    e.step(1 / 60, surfaces: [moved], mouse: nil)
    try expect(e.phase == .falling && e.lastFall == .moved, "Movement must invalidate grip")
}
check("Resizing the supporting window releases the climber") {
    let e = try attached(); var resized = wall; resized.frame.size.height -= 24
    e.step(1 / 60, surfaces: [resized], mouse: nil)
    try expect(e.phase == .falling, "Resize must invalidate grip")
}
check("Subpixel jitter does not release a grip") {
    let e = try attached(); var jitter = wall; jitter.frame.origin.x += 0.2
    tick(e, seconds: 1, surfaces: [jitter])
    try expect(e.phase == .climbing, "Subpixel jitter should be tolerated")
}
check("A mouse collision causes a fall") {
    let e = try attached(); e.step(1 / 60, surfaces: [wall], mouse: e.position)
    try expect(e.phase == .falling && e.lastFall == .mouse, "Mouse must disturb climber")
}
check("Mouse interference can be disabled") {
    let e = try attached(); e.mouseEnabled = false
    e.step(1 / 60, surfaces: [wall], mouse: e.position)
    try expect(e.phase == .climbing, "Disabled mouse should be harmless")
}
check("Pause freezes position and simulation time") {
    let e = try attached(); e.paused = true; let p = e.position; let t = e.elapsed
    tick(e, seconds: 2, surfaces: [])
    try expect(e.position == p && e.elapsed == t, "Paused state must not advance")
}
check("A fall lands, gets up, and begins another attempt") {
    let e = try attached(); e.fall(.manual)
    tick(e, seconds: 6, surfaces: [wall])
    try expect(e.attempt == 2 && e.falls == 1, "Exactly one new attempt expected")
    try expect(e.phase == .climbing, "Must resume climbing automatically")
}
check("An empty desktop waits without floating or crashing") {
    let e = ClimbEngine(bounds: world, floor: 40)
    tick(e, seconds: 20, surfaces: [])
    try expect(e.phase == .waiting && e.position.y == 40, "No invisible wall to climb")
}
check("A newly covering window invalidates the current handhold") {
    let e = try attached()
    let covering = Surface(id: 2, frame: CGRect(x: 0, y: 0, width: 1200, height: 900))
    e.step(1 / 60, surfaces: [covering, wall], mouse: nil)
    try expect(e.phase == .falling && e.lastFall == .covered, "Occluded handhold must disappear")
}
check("Moving an unrelated background window does not cause a fall") {
    let e = try attached()
    let other = Surface(id: 3, frame: CGRect(x: 50, y: 500, width: 200, height: 250))
    tick(e, seconds: 1, surfaces: [wall, other])
    try expect(e.phase == .climbing, "Only actual support movement matters")
}
check("Climber transfers from a low window to a higher window") {
    let low = Surface(id: 4, frame: CGRect(x: 400, y: 70, width: 350, height: 200))
    let high = Surface(id: 5, frame: CGRect(x: 600, y: 300, width: 350, height: 450))
    let e = ClimbEngine(bounds: world, floor: 40)
    tick(e, seconds: 15, surfaces: [high, low])
    try expect(e.support?.id == high.id && e.height > 300, "Should find a higher reachable window")
}
check("Climber stays on screen while climbing a maximized window") {
    let full = Surface(id: 8, frame: CGRect(x: 0, y: 0, width: 1200, height: 870))
    let e = ClimbEngine(bounds: world, floor: 40)
    tick(e, seconds: 8, surfaces: [full])
    try expect(e.phase == .climbing, "Screen-edge window should be climbable")
    try expect(e.position.x >= 24 && e.position.x <= 1176, "Character must remain visible")
}
check("A suspended frame does not teleport the climber") {
    let e = try attached(); let p = e.position
    e.step(60, surfaces: [wall], mouse: nil)
    try expect(abs(e.position.y - p.y) < 12, "Frame delta must be capped after wake")
}
check("Window coordinates convert correctly on an offset secondary display") {
    let quartz = CGRect(x: 1510, y: 140, width: 600, height: 400)
    let screen = CGRect(x: 1440, y: -200, width: 1200, height: 900)
    let actual = Coordinates.localWindowFrame(quartz, primaryHeight: 900, screenFrame: screen)
    try expect(actual == CGRect(x: 70, y: 560, width: 600, height: 400), "Expected bottom-left local coordinates, got \(actual)")
}
let textHolds = [
    Surface(id: 101, frame: CGRect(x: 480, y: 112, width: 150, height: 18)),
    Surface(id: 102, frame: CGRect(x: 510, y: 177, width: 140, height: 18)),
    Surface(id: 103, frame: CGRect(x: 470, y: 242, width: 150, height: 18)),
    Surface(id: 104, frame: CGRect(x: 500, y: 307, width: 150, height: 18))
]
func textClimber() -> ClimbEngine { ClimbEngine(bounds: world, floor: 40, terrain: .handholds) }
check("Small text rows are usable handholds") {
    let e = textClimber(); tick(e, seconds: 6, surfaces: textHolds)
    try expect(e.height > 130, "Character must climb actual text rows")
    try expect(e.support != nil, "A text row must support the character")
}
check("Smooth areas only allow ground patrol, never vertical climbing") {
    let e = textClimber(); tick(e, seconds: 2, surfaces: []); let x = e.position.x
    tick(e, seconds: 2, surfaces: [])
    try expect(e.phase == .searching && e.position.y == 40 && e.position.x != x, "Must walk sideways searching on a blank surface")
}
check("Unreachable text does not become an invisible ladder") {
    let e = textClimber()
    tick(e, seconds: 12, surfaces: [textHolds[0], Surface(id: 201, frame: CGRect(x: 500, y: 650, width: 140, height: 20))])
    try expect(e.height > 10 && e.height < 110 && e.falls == 0, "Must hang and search laterally when the next grip is too far")
}
check("Removing a held text row triggers a fall") {
    let e = textClimber(); tick(e, seconds: 4, surfaces: [textHolds[0]])
    try expect(e.support?.id == 101, "Should be holding the first row")
    e.step(1 / 60, surfaces: [], mouse: nil)
    try expect(e.phase == .falling && e.lastFall == .closed, "Missing text must release grip")
}
check("Moving text while climbing triggers a fall") {
    let e = textClimber(); tick(e, seconds: 4, surfaces: [textHolds[0]])
    var moved = textHolds[0]; moved.frame.origin.y += 20
    e.step(1 / 60, surfaces: [moved], mouse: nil)
    try expect(e.phase == .falling && e.lastFall == .moved, "Scrolling or moving text must release grip")
}
let fixturePaths = CommandLine.arguments.dropFirst()
let webLedge = Surface(id: 900, frame: CGRect(x: 710, y: 350, width: 100, height: 10))
func webHero() -> ClimbEngine {
    let engine = textClimber()
    engine.webEnabled = true
    return engine
}
func advance(_ engine: ClimbEngine, until phase: Phase, surfaces: [Surface], seconds: Int = 15) -> Bool {
    for _ in 0..<(seconds * 60) {
        engine.step(1 / 60, surfaces: surfaces, mouse: nil)
        if engine.phase == phase { return true }
    }
    return false
}
check("Only Spider-Man can zip across a gap outside normal climbing reach") {
    let hero = webHero(), regular = textClimber()
    let ledges = [textHolds[0], webLedge]
    try expect(advance(hero, until: .webCasting, surfaces: ledges), "The gap should provoke a visible cast")
    try expect(hero.support?.id == webLedge.id && hero.webAnchor.map(webLedge.frame.contains) == true, "Web must select a real distant surface")
    try expect(advance(hero, until: .webPulling, surfaces: ledges), "Cast must become a zip")
    try expect(advance(hero, until: .climbing, surfaces: ledges) && hero.height > 250, "Zip must end on the selected hold")
    tick(regular, seconds: 12, surfaces: ledges)
    try expect(regular.height < 110 && regular.webAnchor == nil, "Other characters keep climbing normally")
}
check("Spider-Man can cross a horizontal gap between columns at the same height") {
    let hero = webHero()
    let otherColumn = Surface(id: 901, frame: CGRect(x: 835, y: 112, width: 65, height: 10))
    let columns = [textHolds[0], otherColumn]
    try expect(advance(hero, until: .webPulling, surfaces: columns), "A distant column at the same height is a valid destination")
    try expect(hero.support?.id == otherColumn.id, "The web must cross to the other column")
}
check("A web lands on ink inside a broad ledge and releases when only that patch is erased") {
    let hero = webHero()
    let partial = terrain(canvas(1200) { c in
        c.setFillColor(CGColor(gray: 0.04, alpha: 1))
        c.fill(CGRect(x: 768, y: 350, width: 24, height: 9))
    })
    _ = hero.updateGrip(partial)
    try expect(advance(hero, until: .webPulling, surfaces: [webLedge]), "Should find the actual ink")
    guard let anchor = hero.webAnchor else { throw CheckFailure(description: "Missing anchor") }
    try expect(anchor.x >= 766 && partial.hasGrip(near: anchor, radius: 5), "The left side of this segmented ledge is blank")
    let shifted = terrain(canvas(1200) { c in
        c.setFillColor(CGColor(gray: 0.04, alpha: 1))
        c.fill(CGRect(x: 710, y: 350, width: 25, height: 9))
    })
    _ = hero.updateGrip(shifted); _ = hero.updateGrip(shifted)
    try expect(hero.lastFall == .erased && hero.webAnchor == nil && !shifted.holds.isEmpty, "Other ink in the same row cannot support the original web")
}

check("A fresh web chooses a load-bearing patch rather than an isolated noisy pixel") {
    let hero = webHero()
    let f = terrain(canvas(1200) { c in
        c.setFillColor(CGColor(gray:0.02,alpha:1))
        c.fill(CGRect(x:711,y:355,width:1,height:1))
        c.fill(CGRect(x:766,y:350,width:22,height:10))
    })
    _ = hero.updateGrip(f)
    try expect(advance(hero, until:.webPulling, surfaces:[webLedge]), "Expected a real ledge")
    guard let point=hero.webAnchor else {throw CheckFailure(description:"Missing fresh anchor")}
    try expect(f.hasGrip(near:point,radius:5), "The first unchanged capture must accept the exact point the shot selected")
}
check("After climbing Spider-Man swings autonomously in both directions on one fixed anchor") {
    let hero = webHero()
    try expect(advance(hero, until: .webSwinging, surfaces: [webLedge]), "One overhead ledge should eventually support a free swing")
    let anchor = hero.webAnchor
    var left = CGFloat.infinity, right = -CGFloat.infinity, previousSign = 0, turns = 0
    for _ in 0..<650 {
        let x = hero.position.x
        hero.step(1 / 60, surfaces: [webLedge], mouse: nil)
        guard hero.phase == .webSwinging else { break }
        try expect(hero.webAnchor == anchor && world.contains(hero.position) && hero.position.y >= hero.floor, "The pivot must stay fixed and the body on screen")
        left = min(left, hero.position.x); right = max(right, hero.position.x)
        let delta = hero.position.x - x
        if abs(delta) > 0.08 {
            let sign = delta > 0 ? 1 : -1
            if previousSign != 0 && sign != previousSign { turns += 1 }
            previousSign = sign
        }
    }
    try expect(right - left > 65 && turns >= 2, "The arc should reverse visibly at least twice")
}
check("A web cannot attach to empty space; an erased or moved anchor releases it") {
    let empty = webHero(); tick(empty, seconds: 9, surfaces: [])
    try expect(empty.height == 0 && empty.webAnchor == nil, "Blank desktop supplies no anchor")
    let hero = webHero()
    try expect(advance(hero, until: .webPulling, surfaces: [webLedge]), "Expected a genuine attachment")
    let blank = terrain(canvas(1200) { _ in })
    _ = hero.updateGrip(blank); _ = hero.updateGrip(blank)
    try expect(hero.phase == .falling && hero.webAnchor == nil && hero.lastFall == .erased, "Erasing the pixels must cut the web")
    let moved = webHero()
    try expect(advance(moved, until: .webSwinging, surfaces: [webLedge]), "Expected another attachment")
    var changed = webLedge; changed.frame.origin.x += 25
    moved.step(1 / 60, surfaces: [changed], mouse: nil)
    try expect(moved.phase == .falling && moved.webAnchor == nil && moved.lastFall == .moved, "Moving the web's real target must break the swing")
}
check("Pause, pickup and switching character do not leave an orphaned web") {
    let hero = webHero()
    try expect(advance(hero, until: .webSwinging, surfaces: [webLedge]), "Expected a swing")
    let position = hero.position, pivot = hero.webAnchor
    hero.paused = true; tick(hero, seconds: 1, surfaces: [webLedge])
    try expect(hero.position == position && hero.webAnchor == pivot, "Pausing freezes the rope and body together")
    hero.paused = false; hero.beginDrag()
    try expect(hero.webAnchor == nil && hero.phase == .dragging, "Pickup severs the tether")
    let other = webHero()
    try expect(advance(other, until: .webPulling, surfaces: [webLedge]), "Expected a zip")
    other.webEnabled = false
    try expect(other.webAnchor == nil && other.phase == .falling, "Switching away in midair releases the web immediately")
}
let skyline: [Surface] = [280, 480, 680, 880, 1060].enumerated().map { i, x in
    var ledge = Surface(id: UInt32(930 + i), frame: CGRect(x: x, y: 335 + 10 * (i % 2), width: 68, height: 12))
    ledge.windowID = UInt32(41 + i)
    return ledge
}
check("Forward swings can chain three real anchors with alternating wrists and a free flip") {
    let hero = webHero()
    var catches: [UInt32] = [], wrist: CGFloat?, sawTwo = false, free = false, castAfterFlip = false
    var biggestStep: CGFloat = 0
    for _ in 0..<2100 {
        let previous = hero.position, before = hero.phase
        hero.step(1/60, surfaces: skyline, mouse: nil)
        biggestStep = max(biggestStep, hypot(hero.position.x - previous.x, hero.position.y - previous.y))
        if hero.phase == .webHandoff && hero.strands.count == 2 {
            let a = hero.strands[0], b = hero.strands[1]
            try expect(a.attached && !b.attached && hypot(a.hand.x-b.hand.x, a.hand.y-b.hand.y) > 5, "The incoming silk must leave a different wrist")
            sawTwo = true
        }
        if hero.phase == .webVault {
            if hero.flipProgress > 0.1 && hero.flipProgress < 0.9 && hero.strands.isEmpty { free = true }
            if free && hero.flipProgress == 1 && hero.strands.count == 1 { castAfterFlip = true }
        }
        if [.webHandoff,.webVault].contains(before) && hero.phase == .webSwinging, let hold = hero.support, let anchor = hero.webAnchor {
            try expect(hold.frame.contains(anchor), "Each catch must land on the real destination")
            if let wrist { try expect(wrist != hero.wristSide, "Each catch switches leading wrist") }
            wrist = hero.wristSide; catches.append(hold.id)
        }
        if Set(catches).count >= 3 && castAfterFlip { break }
    }
    try expect(sawTwo && Set(catches).count >= 2 && castAfterFlip && biggestStep < 18,
               "Expected double cast, airborne tuck, recatch and no teleport: catches=\(catches), two=\(sawTwo), flip=\(castAfterFlip), step=\(biggestStep)")
}
check("Losing only the incoming anchor aborts a handoff but preserves the old silk") {
    let hero = webHero()
    try expect(advance(hero, until: .webHandoff, surfaces: skyline), "Expected a real handoff")
    guard let old = hero.support else { throw CheckFailure(description: "Lost the original support early") }
    hero.step(1/60, surfaces: [old], mouse: nil)
    try expect(hero.phase == .webSwinging && hero.support?.id == old.id && hero.strands.count == 1, "The old attached strand must still carry the hero")
}
check("Erasing a future anchor in free flight or picking up a double cast clears every strand") {
    let hero = webHero()
    try expect(advance(hero, until: .webVault, surfaces: skyline), "Expected an airborne switch")
    _ = hero.updateGrip(terrain(canvas(1200) { _ in }))
    try expect(hero.phase == .falling && hero.lastFall == .erased && hero.strands.isEmpty, "No current web exists to save the fall")
    let other = webHero()
    try expect(advance(other, until: .webHandoff, surfaces: skyline), "Expected the second strand")
    other.step(1/60, surfaces: skyline, mouse: nil)
    other.beginDrag()
    try expect(other.phase == .dragging && other.strands.isEmpty, "Dragging must clear both the loaded and incoming silk")
}
check("A long incoming strand cannot cause a fall or floor scrape on a stable low skyline") {
    var catches = 0, flips = 0, groundReleases = 0
    var lowest = CGFloat.infinity
    for height in [165, 185, 205, 235, 265, 305] {
        for gap in [135, 185, 230, 280] {
            var ledges: [Surface] = []
            for i in -2...2 {
                let x = CGFloat(580 + i * gap), y = CGFloat(height + (i % 2) * 8)
                let rect = CGRect(x: x, y: y, width: 58, height: 10)
                ledges.append(Surface(id: UInt32(1105 + i), frame: rect))
            }
            for (rate, speed) in [(60, 1.0), (20, 2.0)] {
                let hero = webHero(); hero.speed = speed
                for _ in 0..<(rate * 15) {
                    let before = hero.phase
                    hero.step(1 / Double(rate), surfaces: ledges, mouse: nil)
                    if [.webSwinging, .webHandoff, .webVault].contains(hero.phase) { lowest = min(lowest, hero.height) }
                    if hero.phase == .webSwinging && [.webHandoff,.webVault].contains(before) { catches += 1 }
                    if hero.phase == .webVault && before != .webVault { flips += 1 }
                    if hero.phase == .falling && before != .falling && hero.lastFall == .manual { groundReleases += 1 }
                }
            }
        }
    }
    print(String(format: "      48 low routes: %d catches, %d flips, %d false falls, %.2f pt minimum clearance", catches, flips, groundReleases, Double(lowest)))
    try expect(catches > 15 && flips > 0 && groundReleases == 0 && lowest >= 7,
               "catches=\(catches) flips=\(flips) premature ground releases=\(groundReleases) lowest clearance=\(lowest)")
}
check("Picking the character up detaches it without counting a fall") {
    let e = try attached(); e.beginDrag()
    try expect(e.phase == .dragging && e.support == nil && e.falls == 0, "Dragging should deliberately release support")
}
check("Dragging follows the pointer and stays inside the display") {
    let e = textClimber(); e.beginDrag(); e.drag(to: CGPoint(x: 700, y: 400))
    try expect(e.position == CGPoint(x: 700, y: 400), "Must follow the requested drag position")
    e.drag(to: CGPoint(x: -100, y: 2000))
    try expect(e.position.x >= 28 && e.position.y <= world.maxY - 50, "Dragged character must stay reachable")
}
check("Releasing a dragged character restores gravity") {
    let e = textClimber(); e.beginDrag(); e.drag(to: CGPoint(x: 500, y: 500)); e.endDrag()
    let startY = e.position.y
    tick(e, seconds: 0.4, surfaces: [])
    try expect(e.phase == .falling && e.position.y < startY - 30, "Release must drop naturally, not remain floating")
}
check("Hovering holds the character still so its menu is reachable") {
    var pointer = PointerIntent()
    try expect(pointer.update(inside: true, now: 10).freeze, "Character must wait for an intentional click")
    try expect(!pointer.update(inside: true, now: 11).disturb, "Stationary menu targeting should be safe")
    try expect(!pointer.update(inside: false, now: 12).disturb, "Leaving after a deliberate hover should be safe")
}
check("A quick mouse sweep still disturbs the character") {
    var pointer = PointerIntent(); _ = pointer.update(inside: true, now: 10)
    try expect(pointer.update(inside: false, now: 10.15).disturb, "Quick pass-through should count as interference")
}
check("Closing a menu or finishing a drag does not trigger mouse interference") {
    var pointer = PointerIntent(); _ = pointer.update(inside: true, now: 10)
    pointer.protect(after: 10.1)
    try expect(!pointer.update(inside: false, now: 10.15).disturb, "Explicit interactions must be protected")
}
func canvas(_ size: Int = 320, _ draw: (CGContext) -> Void) -> CGImage {
    let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setFillColor(CGColor(gray: 0.95, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: size, height: size))
    draw(c); return c.makeImage()!
}
func terrain(_ image: CGImage) -> PixelTerrain { TerrainDetector.analyze(image, logicalSize: CGSize(width: image.width, height: image.height)) }
check("A large drawing can be climbed along its contour without text recognition") {
    let image = canvas { c in c.setStrokeColor(CGColor(gray: 0.1, alpha: 1)); c.setLineWidth(5); c.strokeEllipse(in: CGRect(x: 45, y: 45, width: 230, height: 230)) }
    let field = terrain(image)
    try expect(field.hasGrip(near: CGPoint(x: 45, y: 160)), "Large graphic contours should be valid grips")
    try expect(!field.hasGrip(near: CGPoint(x: 160, y: 160)), "A circle's flat interior must stay smooth")
}
check("Different hues with almost identical luminance still form a grip") {
    let image = canvas { c in
        c.setFillColor(CGColor(red: 180 / 255, green: 30 / 255, blue: 30 / 255, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 320, height: 320))
        c.setFillColor(CGColor(red: 30 / 255, green: 75 / 255, blue: 30 / 255, alpha: 1)); c.fill(CGRect(x: 80, y: 55, width: 180, height: 200))
    }
    try expect(terrain(image).hasGrip(near: CGPoint(x: 80, y: 120)), "Color discontinuity must survive equal-luminance conversion")
}
check("A smooth color gradient does not become a ladder") {
    let image = canvas { c in
        for x in 0..<320 { c.setFillColor(CGColor(gray: CGFloat(x) / 320, alpha: 1)); c.fill(CGRect(x: x, y: 0, width: 1, height: 320)) }
    }
    try expect(terrain(image).holds.isEmpty, "Slow gradients are not rough surfaces")
}
check("Erasing only the actual contact patch releases it while other terrain remains") {
    let drawPattern: (CGContext) -> Void = { c in
        c.setStrokeColor(CGColor(gray: 0.1, alpha: 1)); c.setLineWidth(4)
        for x in stride(from: 40, through: 280, by: 24) { c.move(to: CGPoint(x: x, y: 30)); c.addLine(to: CGPoint(x: x, y: 290)); c.strokePath() }
    }
    let before = terrain(canvas { drawPattern($0) })
    let after = terrain(canvas { c in drawPattern(c); c.setFillColor(CGColor(gray: 0.95, alpha: 1)); c.fill(CGRect(x: 105, y: 105, width: 110, height: 110)) })
    try expect(before.hasGrip(near: CGPoint(x: 160, y: 160)), "Contact initially has texture")
    try expect(!after.hasGrip(near: CGPoint(x: 160, y: 160)), "Erased contact must be smooth")
    try expect(!after.holds.isEmpty, "Unrelated texture remains")
}
check("Pixel contacts use bottom-left desktop coordinates") {
    let image = canvas { c in c.setFillColor(CGColor(gray: 0.05, alpha: 1)); c.fill(CGRect(x: 80, y: 40, width: 80, height: 20)) }
    try expect(terrain(image).hasGrip(near: CGPoint(x: 100, y: 40)), "Contact must align with the drawn lower edge")
    try expect(!terrain(image).hasGrip(near: CGPoint(x: 100, y: 280)), "Must not mirror the image vertically")
}
check("One weak frame is tolerated but two missing contact frames release") {
    var stability = GripStability()
    try expect(!stability.shouldRelease(hasGrip: false), "One noisy frame should be tolerated")
    try expect(stability.shouldRelease(hasGrip: false), "Two absent frames must release the grip")
    stability.reset()
    try expect(!stability.shouldRelease(hasGrip: false), "Reset clears missing-frame history")
    try expect(!stability.shouldRelease(hasGrip: true), "A restored patch re-establishes support")
    try expect(!stability.shouldRelease(hasGrip: false), "Non-consecutive absent frames must not accumulate")
}
check("Erasing the load-bearing pixels releases the real game state after two frames") {
    let e = textClimber(); tick(e, seconds: 4, surfaces: [textHolds[0]])
    let blank = terrain(canvas(1200) { _ in })
    _ = e.updateGrip(blank)
    try expect(e.phase != .falling, "First absent contact frame gets one-frame tolerance")
    _ = e.updateGrip(blank)
    try expect(e.phase == .falling && e.lastFall == .erased, "Erased local pixels must cause the actual fall, even if the old rectangle exists")
}
check("Stable local pixels retain support while unrelated pixels change") {
    let e = textClimber(); tick(e, seconds: 4, surfaces: [textHolds[0]])
    let field = terrain(canvas(1200) { c in c.setFillColor(CGColor(gray: 0.05, alpha: 1)); c.fill(textHolds[0].frame) })
    for _ in 0..<5 { _ = e.updateGrip(field) }
    try expect(e.phase != .falling && e.support?.id == 101, "Unchanged load-bearing pixels should retain the grip")
}
check("Subpixel recognition jitter does not interrupt approach to a text hold") {
    let e = textClimber()
    let hold = Surface(id: 301, frame: CGRect(x: 200, y: 112, width: 120, height: 18))
    tick(e, seconds: 0.5, surfaces: [hold])
    try expect(e.phase == .walking, "Must be approaching the distant text")
    var jitter = hold; jitter.frame.origin.x += 0.5
    e.step(1 / 60, surfaces: [jitter], mouse: nil)
    try expect(e.phase == .walking, "A half-point detection variation must not cancel the approach")
}
if fixturePaths.count == 2 {
    for (i, path) in fixturePaths.enumerated() {
        check(i == 0 ? "User text screenshot yields plentiful handholds" : "User blank screenshot has no holds in its smooth center") {
            let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            let holds = TerrainDetector.detect(image, logicalSize: CGSize(width: image.width, height: image.height))
            if i == 0 { try expect(holds.count >= 20, "Expected >= 20 text/icon holds; got \(holds.count)") }
            else {
                let center = CGRect(x: 60, y: 60, width: image.width - 120, height: image.height - 120)
                try expect(!holds.contains(where: { $0.intersects(center) }), "Flat background/watermark must not become handholds: \(holds)")
            }
            print("      detected \(holds.count) handholds")
        }
    }
}
func withCharacterFixture(_ body: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("sisyphus-skin-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let image = canvas(320) { c in
        c.setFillColor(CGColor(gray: 0.2, alpha: 1)); c.fill(CGRect(x: 40, y: 30, width: 70, height: 260))
    }
    let destination = CGImageDestinationCreateWithURL(root.appendingPathComponent("sprite.png") as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    try expect(CGImageDestinationFinalize(destination), "Fixture PNG should be written")
    try body(root)
}
func writeCharacterManifest(_ root: URL, image: String = "sprite.png", frames: [Int] = [0, 1], fps: Double = 8) throws -> URL {
    let manifest: [String: Any] = ["version": 1, "name": "My character", "image": image, "columns": 2, "rows": 2,
        "animations": ["idle": ["frames": [0], "fps": 1], "climb": ["frames": frames, "fps": fps]]]
    let url = root.appendingPathComponent("character.json")
    try JSONSerialization.data(withJSONObject: manifest).write(to: url)
    return url
}
check("A plain PNG imports as a single-frame character") {
    try withCharacterFixture { root in
        let pack = try CharacterPack.load(from: root.appendingPathComponent("sprite.png"))
        try expect(pack.manifest.columns == 1 && pack.frameIndex(for: .climbing, time: 4) == 0, "PNG should work without a manifest")
    }
}
check("A custom sprite sheet selects animation frames and top-to-bottom cells") {
    try withCharacterFixture { root in
        let pack = try CharacterPack.load(from: writeCharacterManifest(root))
        try expect(pack.frameIndex(for: .climbing, time: 0.15) == 1, "Climbing must advance the supplied animation")
        try expect(pack.frameIndex(for: .walking, time: 1) == 0, "Missing clips should fall back to idle")
        try expect(pack.sourceRect(for: 2) == CGRect(x: 0, y: 160, width: 160, height: 160), "Sheets use row-major order from top left")
    }
}
check("A character manifest cannot load files outside its own directory") {
    try withCharacterFixture { root in
        let manifest = try writeCharacterManifest(root, image: "../sprite.png")
        do { _ = try CharacterPack.load(from: manifest); throw CheckFailure(description: "Path traversal must be rejected") }
        catch is CharacterPackError {}
    }
}
check("Malformed animation frames and zero frame rates are rejected") {
    try withCharacterFixture { root in
        for (frames, fps) in [([4], 8.0), ([0], 0.0), ([], 8.0)] {
            let manifest = try writeCharacterManifest(root, frames: frames, fps: fps)
            do { _ = try CharacterPack.load(from: manifest); throw CheckFailure(description: "Invalid animation must not import") }
            catch is CharacterPackError {}
        }
    }
}
check("Imported character assets survive removal of the original folder") {
    try withCharacterFixture { root in
        let source = try CharacterPack.load(from: writeCharacterManifest(root))
        let library = root.appendingPathComponent("library")
        let installed = try source.install(into: library)
        try FileManager.default.removeItem(at: root.appendingPathComponent("sprite.png"))
        let reloaded = try CharacterPack.load(from: installed)
        try expect(reloaded.image.width == 320 && reloaded.manifest.name == "My character", "Importer must own a persistent copy")
    }
}
check("A standard Shimeji image folder maps movement and pickup frames") {
    try withCharacterFixture { root in
        let img = root.appendingPathComponent("img")
        try FileManager.default.createDirectory(at: img, withIntermediateDirectories: false)
        for number in [1, 2, 3, 4, 5, 6, 11, 14, 15, 16] {
            try FileManager.default.copyItem(at: root.appendingPathComponent("sprite.png"), to: img.appendingPathComponent("shime\(number).png"))
        }
        let pack = try CharacterPack.load(from: root)
        try expect(pack.manifest.columns == 4 && pack.manifest.rows == 3, "Ten Shimeji frames must form a complete atlas")
        try expect(pack.clip(for: .climbing).frames == [7, 8, 9, 8], "Standard climbing frames must be preserved")
        try expect(pack.clip(for: .dragging).frames == [4, 5], "Pickup uses its own expression")
        try expect(pack.manifest.facesRight == false, "Standard Shimeji artwork faces left")
        let reloaded = try CharacterPack.load(from: pack.install(into: root.appendingPathComponent("library")))
        try expect(reloaded.sprite(for: .dragging, time: 0.3).width == 320, "Converted Shimeji must survive save/reload")
    }
}
check("Symlinked sprite images cannot escape a character pack") {
    try withCharacterFixture { root in
        let packDir = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: packDir, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: packDir.appendingPathComponent("sprite.png"), withDestinationURL: root.appendingPathComponent("sprite.png"))
        let manifest = try writeCharacterManifest(packDir)
        do { _ = try CharacterPack.load(from: manifest); throw CheckFailure(description: "Symlink escape must be rejected") }
        catch is CharacterPackError {}
    }
}
check("The bundled Akane sheet decodes every animation with actual transparency") {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let pack = try CharacterPack.load(from: root.appendingPathComponent("Resources/Characters/Akane/character.json"))
    try expect(pack.manifest.name.contains("新条茜") && pack.image.width == 1448 && pack.image.height == 1086, "Expected the selected character asset")
    try expect([CGImageAlphaInfo.first, .last, .premultipliedFirst, .premultipliedLast].contains(pack.image.alphaInfo), "Desktop art requires real alpha")
    for phase in [Phase.waiting, .walking, .climbing, .falling, .dragging, .recovering] {
        for frame in pack.clip(for: phase).frames {
            try expect(pack.image.cropping(to: pack.sourceRect(for: frame))?.width == 362, "Every referenced cell must decode")
        }
    }
}
if CommandLine.arguments.contains("--benchmark") {
    let c = CGContext(data: nil, width: 1512, height: 982, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setFillColor(CGColor(gray: 0.95, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 1512, height: 982))
    c.setFillColor(CGColor(gray: 0.15, alpha: 1))
    for y in stride(from: 40, to: 940, by: 38) {
        for x in stride(from: 40, to: 1440, by: 19) where x % 157 < 118 { c.fill(CGRect(x: x, y: y, width: 5 + x % 7, height: 16)) }
    }
    let image = c.makeImage()!
    var samples: [Double] = []; var count = 0
    for _ in 0..<12 {
        let start = ProcessInfo.processInfo.systemUptime
        count = TerrainDetector.analyze(image, logicalSize: CGSize(width: 1512, height: 982)).holds.count
        samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
    }
    samples.sort()
    print(String(format: "BENCH 1512x982 synthetic image, 12 frames: median %.2f ms, max %.2f ms, %d ledges. Capture/render time excluded.", samples[6], samples.last!, count))
}
print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
