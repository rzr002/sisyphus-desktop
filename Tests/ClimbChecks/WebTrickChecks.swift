import Foundation
import CoreGraphics
import ClimbCore

private func reach(_ name: String, with hero: ClimbEngine, on ledges: [Surface]) throws {
    guard let phase = Phase(rawValue: name), advance(hero, until: phase, surfaces: ledges, seconds: 55) else {
        throw CheckFailure(description: "The normal game loop never performed \(name)")
    }
}

private func loadedSling(field: PixelTerrain? = nil) throws -> ClimbEngine {
    let hero = webHero()
    if let field { _ = hero.updateGrip(field) }
    try reach("webWindup", with: hero, on: skyline)
    for _ in 0..<60 {
        if hero.strands.filter(\.attached).count == 2 { return hero }
        hero.step(1 / 60, surfaces: skyline, mouse: nil)
    }
    throw CheckFailure(description: "Two strands never bore the load together")
}

func checkWebTricks() {
    check("The slingshot stretches two real anchors, fires freely, and catches at speed") {
        let hero = try loadedSling()
        let tips = hero.strands.map(\.tip)
        let upper = tips.sorted { $0.x < $1.x }
        try expect(upper[0].x < hero.position.x && hero.position.x < upper[1].x, "Anchors must straddle the body")
        try expect(tips.allSatisfy { p in skyline.contains { $0.frame.contains(p) } }, "Both tips must land on terrain")
        func lengths() -> [CGFloat] { hero.strands.map { hypot($0.hand.x - $0.tip.x, $0.hand.y - $0.tip.y) } }
        let initial = lengths()
        var stretch: CGFloat = 0, launchSpeed: CGFloat = 0
        var free = false, recast = false, caught = false
        var launchPoint = CGPoint.zero
        for _ in 0..<160 {
            let before = hero.position, previous = hero.phase.rawValue
            hero.step(1 / 60, surfaces: skyline, mouse: nil)
            let speed = 60 * hypot(hero.position.x - before.x, hero.position.y - before.y)
            try expect(speed < 1080 && hero.height >= 18 - 0.01, "The launch and catch must be continuous and clear the floor")
            switch hero.phase.rawValue {
            case "webWindup":
                try expect(hero.strands.map(\.tip) == tips, "Loaded endpoints must stay planted")
                try expect(abs(hero.strands[0].hand.x - hero.strands[1].hand.x) > 12, "Use two separated wrists")
                let current = lengths()
                stretch = max(stretch, min(current[0] - initial[0], current[1] - initial[1]))
            case "webLaunch":
                if previous == "webWindup" { launchPoint = hero.position }
                if hero.strands.isEmpty { free = true; launchSpeed = max(launchSpeed, speed) }
                if free && hero.strands.count == 1 { recast = true }
            case "webSwinging" where previous == "webLaunch":
                caught = true
                try expect(hypot(hero.position.x - launchPoint.x, hero.position.y - launchPoint.y) > 80, "Release must travel across the gap")
            default: break
            }
            if caught { break }
        }
        try expect(stretch > 16 && free && recast && caught && launchSpeed > 330 && hero.falls == 0,
                   "stretch \(stretch), launch speed \(launchSpeed), free \(free), recast \(recast), catch \(caught)")
    }
    check("Either loaded arm of the slingshot can catch the hero if the other anchor goes away") {
        for lost in 0...1 {
            let hero = try loadedSling(), tips = hero.strands.map(\.tip)
            let remaining = skyline.filter { !$0.frame.contains(tips[lost]) }
            hero.step(1 / 60, surfaces: remaining, mouse: nil)
            try expect(hero.phase == .webSwinging && hero.strands.count == 1 && hero.webAnchor == tips[1 - lost] && hero.falls == 0,
                       "Losing anchor \(lost) should cancel the launch on the surviving line")
        }
        let hero = try loadedSling()
        hero.step(1 / 60, surfaces: [], mouse: nil)
        try expect(hero.phase == .falling && hero.strands.isEmpty, "Losing both endpoints must drop the body immediately")
    }
    check("Erasing traction, dragging or changing skin interrupts the new tricks") {
        let hero = try loadedSling()
        let blank = terrain(canvas(1200) { _ in })
        _ = hero.updateGrip(blank); _ = hero.updateGrip(blank)
        try expect(hero.phase == .falling && hero.strands.isEmpty, "Erasing both endpoints cuts both strands")
        for (name, ledges) in [("webWindup", skyline), ("webLaunch", skyline), ("webRappel", [webLedge]), ("webKick", skyline)] {
            let e = webHero()
            try reach(name, with: e, on: ledges)
            let point = e.position, silk = e.strands.map(\.tip)
            e.paused = true; tick(e, seconds: 0.5, surfaces: ledges)
            try expect(e.position == point && e.strands.map(\.tip) == silk, "Pause must freeze \(name)")
            e.paused = false
            if name == "webLaunch" { e.webEnabled = false } else { e.beginDrag() }
            try expect(e.strands.isEmpty && !e.phase.usesWeb, "Interrupting \(name) must clear every strand")
        }
    }
    check("Erasing only the ink under either taut tip preserves the opposite strand") {
        func field(erasing point: CGPoint? = nil) -> PixelTerrain {
            terrain(canvas(1200) { c in
                c.setFillColor(CGColor(gray: 0.08, alpha: 1))
                for surface in skyline { c.fill(surface.frame) }
                if let point {
                    c.setFillColor(CGColor(gray: 0.95, alpha: 1))
                    c.fill(CGRect(x: point.x - 14, y: point.y - 14, width: 28, height: 28))
                }
            })
        }
        for lost in 0...1 {
            let hero = try loadedSling(field: field()), tips = hero.strands.map(\.tip)
            let erased = field(erasing: tips[lost])
            try expect(!erased.hasGrip(near: tips[lost], radius: 5) && erased.hasGrip(near: tips[1 - lost], radius: 5), "Erase only the chosen endpoint")
            _ = hero.updateGrip(erased); _ = hero.updateGrip(erased)
            try expect(hero.phase == .webSwinging && hero.webAnchor == tips[1 - lost], "An unchanged rectangle cannot prop up deleted ink")
        }
    }
    check("Upside-down rappel lowers, holds, and reels back to the same single anchor") {
        let hero = webHero()
        try reach("webRappel", with: hero, on: [webLedge])
        let top = hero.position, anchor = hero.webAnchor
        var low = top.y, stillFrames = 0
        for _ in 0..<180 {
            let previous = hero.position
            hero.step(1 / 60, surfaces: [webLedge], mouse: nil)
            if hero.phase.rawValue != "webRappel" { break }
            low = min(low, hero.position.y)
            if hero.position.y < top.y - 25 && abs(hero.position.y - previous.y) < 0.03 { stillFrames += 1 }
            try expect(hero.strands.count == 1 && hero.webAnchor == anchor && hero.height >= 18, "The single support must hold throughout")
        }
        try expect(hero.phase == .webSwinging && top.y - low > 30 && stillFrames >= 6 && abs(hero.position.y - top.y) < 4,
                   "Rappel must visibly lower, hang for a beat and retract")
    }
    check("A one-handed scissor kick carries a moving swing through to its follow-through") {
        let hero = webHero()
        try reach("webKick", with: hero, on: skyline)
        let start = hero.position, tip = hero.webAnchor
        var frames = 0
        while hero.phase.rawValue == "webKick" && frames < 100 {
            try expect(hero.strands.count == 1 && hero.webAnchor == tip, "The kick keeps the load-bearing wrist")
            hero.step(1 / 60, surfaces: skyline, mouse: nil); frames += 1
        }
        try expect(hero.phase == .webSwinging && frames >= 16 && hypot(hero.position.x - start.x, hero.position.y - start.y) > 22,
                   "The body must keep swinging during the kick")
    }
    check("An overlapping or moving window invalidates either slingshot endpoint even if the ink stays identical") {
        for lost in 0...1 {
            for covered in [false, true] {
                let hero = try loadedSling(), tips = hero.strands.map(\.tip)
                let owners = tips.enumerated().map { index, point in
                    Surface(id: UInt32(8000 + index), frame: CGRect(x: point.x - 55, y: point.y - 50, width: 110, height: 100))
                }
                hero.validateWindowContacts(current: owners, captured: owners)
                var current = owners
                if covered { current.insert(Surface(id: 8999, frame: owners[lost].frame), at: 0) }
                else { current[lost].frame.origin.y += 20 }
                hero.validateWindowContacts(current: current, captured: owners)
                try expect(hero.phase == .webSwinging && hero.webAnchor == tips[1 - lost], "Only the surviving window can bear the load")
            }
        }
    }
    check("Erasing the only catch point after launch interrupts free flight") {
        let hero = webHero()
        try reach("webLaunch", with: hero, on: skyline)
        hero.step(1 / 60, surfaces: [], mouse: nil)
        try expect(hero.phase == .falling && hero.lastFall == .closed && hero.strands.isEmpty, "A ballistic launch cannot catch a vanished point")
    }
    check("Tricks respect both screen edges and the floor at different simulation speeds") {
        var launches = 0, rappels = 0, kicks = 0
        var lowest = CGFloat.infinity
        for size in [CGSize(width: 700, height: 430), CGSize(width: 1280, height: 800)] {
            for level: CGFloat in [150, 210, min(360, size.height - 56)] {
                let rect = CGRect(origin: .zero, size: size), floor: CGFloat = 56
                let row = stride(from: 50, to: Int(size.width - 50), by: 148).enumerated().map { index, x in
                    Surface(id: UInt32(1200 + index), frame: CGRect(x: CGFloat(x), y: level + CGFloat(index % 2 * 12), width: 56, height: 12))
                }
                let solitary = size.width == 700 && level == 360
                let ledges = solitary ? [row[row.count / 2]] : row
                for (rate, speed) in [(60, 1.0), (20, 2.0)] {
                    let hero = ClimbEngine(bounds: rect, floor: floor, terrain: .handholds)
                    hero.webEnabled = true; hero.speed = speed
                    for _ in 0..<(rate * 35) {
                        let before = hero.phase
                        hero.step(1 / Double(rate), surfaces: ledges, mouse: nil)
                        if hero.phase != before {
                            switch hero.phase.rawValue {
                            case "webLaunch": launches += 1
                            case "webKick": kicks += 1
                            case "webRappel": rappels += 1
                            default: break
                            }
                        }
                        guard ["webWindup", "webLaunch", "webKick", "webRappel", "webSwinging"].contains(hero.phase.rawValue) else { continue }
                        lowest = min(lowest, hero.height)
                        try expect(hero.height >= 17.99 && hero.position.y <= rect.maxY - 38 &&
                                   hero.position.x >= rect.minX + 42 && hero.position.x <= rect.maxX - 42, "Trick leaves safe display area")
                    }
                    try expect(hero.falls == 0, "A stable arrangement should never drop the hero")
                }
            }
        }
        print(String(format: "      12 trick routes: %d launches, %d rappels, %d kicks, %.2f pt minimum clearance", launches, rappels, kicks, Double(lowest)))
        try expect(launches > 0 && rappels > 0 && kicks > 0, "All new moves must actually run in the route sweep")
    }
}
