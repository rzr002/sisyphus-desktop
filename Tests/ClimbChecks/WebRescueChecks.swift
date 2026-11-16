import CoreGraphics
import ClimbCore

private let rescueLedge = Surface(id: 801, frame: CGRect(x: 669, y: 465, width: 95, height: 12))
private let dropPoint = CGPoint(x: 546, y: 360)

private func pixels(_ ledges: [Surface]) -> PixelTerrain {
    terrain(canvas(900) { c in
        c.setFillColor(CGColor(gray: 0.08, alpha: 1))
        for ledge in ledges { c.fill(ledge.frame.insetBy(dx: 3, dy: 2)) }
    })
}

private func drop(_ hero: ClimbEngine, at point: CGPoint = dropPoint) {
    hero.beginDrag(); hero.drag(to: point); hero.endDrag()
}

private func shooting(_ hero: ClimbEngine, toward ledges: [Surface]) throws {
    for _ in 0..<60 {
        hero.step(1 / 60, surfaces: ledges, mouse: nil)
        if hero.incomingWebSupport != nil && hero.support == nil { return }
        if hero.phase == .recovering { break }
    }
    throw CheckFailure(description: "No shot during free fall")
}

func checkWebRescue() {
    let ledges = [rescueLedge], field = pixels(ledges), blank = pixels([])
    check("A descending hero fires from the wrist, then turns the fall into a swing") {
        for (rate, speed) in [(60, 1.0), (20, 2.0)] {
            let hero = webHero(); hero.speed = speed
            _ = hero.updateGrip(field); drop(hero)
            var falling = false, casting = false, caughtAt: CGPoint?
            for _ in 0..<(rate * 2) {
                let old = hero.position
                hero.step(1 / Double(rate), surfaces: ledges, mouse: nil)
                if hero.phase == .falling && hero.position.y < old.y { falling = true }
                if let strand = hero.strands.first, !strand.attached {
                    casting = true
                    try expect(hero.support == nil && hero.position.y < old.y, "The moving tip must not stop gravity")
                    try expect(hypot(strand.hand.x - hero.position.x - hero.throwOffset.x,
                                     strand.hand.y - hero.position.y - hero.throwOffset.y) < 0.01, "Silk must leave the aiming wrist")
                }
                if hero.phase == .webSwinging { caughtAt = hero.position; break }
            }
            guard let caughtAt, let tip = hero.webAnchor else { throw CheckFailure(description: "No catch at \(rate) Hz") }
            try expect(falling && casting && field.hasGrip(near: tip, radius: 3) && hero.height > 18, "Need free fall, growing silk and a real elevated catch")
            try expect(caughtAt.y < dropPoint.y - 20 && hero.support?.id == rescueLedge.id, "No teleport to the ledge")
            tick(hero, seconds: 0.55, surfaces: ledges)
            try expect(hero.position.x > caughtAt.x + 24 && hero.falls == 1 && hero.attempt == 1, "The same attempt should swing away")
        }
    }
    check("Blank pixels, no fresh pixels, distant edges, underfoot edges and low drops cannot save a fall") {
        let distant = Surface(id: 802, frame: rescueLedge.frame.offsetBy(dx: 300, dy: 0))
        let below = Surface(id: 803, frame: CGRect(x: 660, y: 65, width: 60, height: 10))
        for (map, holds, start) in [(blank as PixelTerrain?, ledges, dropPoint), (nil, ledges, dropPoint),
                                    (pixels([distant]), [distant], dropPoint), (pixels([below]), [below], dropPoint),
                                    (field, ledges, CGPoint(x: 590, y: 78))] {
            let hero = webHero(); if let map { _ = hero.updateGrip(map) }; drop(hero, at: start)
            var fired = false
            for _ in 0..<75 { hero.step(1 / 60, surfaces: holds, mouse: nil); fired = fired || hero.incomingWebSupport != nil }
            try expect(!fired && hero.phase == .recovering && hero.position.y == hero.floor, "Impossible shot from \(start) with \(holds)")
        }
        let regular = textClimber(); _ = regular.updateGrip(field); drop(regular)
        try expect(advance(regular, until: .recovering, surfaces: ledges, seconds: 1), "Ordinary climbers still land")
    }
    check("Deleting, moving or covering a target before impact spends one shot and preserves downward momentum") {
        let back = Surface(id: 77, frame: CGRect(x: 640, y: 420, width: 180, height: 140))
        let cover = Surface(id: 78, frame: back.frame)
        for interruption in 0..<4 {
            let hero = webHero(); _ = hero.updateGrip(field); drop(hero); try shooting(hero, toward: ledges)
            hero.step(1 / 60, surfaces: ledges, mouse: nil)
            hero.validateWindowContacts(current: [back], captured: [back])
            let old = hero.position.y
            switch interruption {
            case 0: _ = hero.updateGrip(blank)
            case 1: var moved = back; moved.frame.origin.x += 10; hero.validateWindowContacts(current: [moved], captured: [back])
            case 2: hero.validateWindowContacts(current: [cover, back], captured: [back])
            default: hero.validateWindowContacts(current: [], captured: [back])
            }
            _ = hero.updateGrip(field)
            hero.step(1 / 60, surfaces: ledges, mouse: nil)
            try expect(hero.phase == .falling && hero.strands.isEmpty && hero.position.y < old - 1, "Lost anchor must not reset downward velocity")
            try expect(advance(hero, until: .recovering, surfaces: ledges, seconds: 1) && hero.falls == 1 && hero.attempt == 1,
                       "Reappearing pixels cannot start an endless retry")
        }
    }
    check("Closing a real support mid-swing allows a different window to catch the same fall") {
        var old = Surface(id: 810, frame: CGRect(x: 538, y: 342, width: 95, height: 12)); old.windowID = 91
        var stale = Surface(id: 811, frame: CGRect(x: 635, y: 430, width: 64, height: 12)); stale.windowID = 91
        var fresh = rescueLedge; fresh.windowID = 92
        let oldWindow = Surface(id: 91, frame: CGRect(x: 515, y: 310, width: 150, height: 150))
        let newWindow = Surface(id: 92, frame: CGRect(x: 667, y: 445, width: 130, height: 64))
        let hero = webHero(); _ = hero.updateGrip(pixels([old, stale, fresh]))
        try expect(advance(hero, until: .webSwinging, surfaces: [old]), "Hero must be hanging before the window closes")
        hero.validateWindowContacts(current: [oldWindow, newWindow], captured: [oldWindow, newWindow])
        hero.validateWindowContacts(current: [newWindow], captured: [oldWindow, newWindow])
        try expect(hero.phase == .falling && hero.lastFall == .closed, "Window loss must cause genuine free fall")
        try shooting(hero, toward: [old, stale, fresh])
        try expect(hero.incomingWebSupport?.id == fresh.id, "Neither the old hold nor its vanished window can rescue the fall")
        try expect(advance(hero, until: .webSwinging, surfaces: [fresh], seconds: 1) && hero.falls == 1, "Fresh ink should arrest the same fall")
    }
    check("Pausing freezes the shot; changing character or picking it up removes the live strand") {
        let hero = webHero(); _ = hero.updateGrip(field); drop(hero); try shooting(hero, toward: ledges)
        hero.step(1 / 60, surfaces: ledges, mouse: nil)
        let before = hero.position, tip = hero.strands.first?.tip
        hero.paused = true; tick(hero, seconds: 0.5, surfaces: ledges)
        try expect(hero.position == before && tip != nil && hero.strands.first?.tip == tip, "Pause must freeze body and silk together")
        hero.paused = false; hero.webEnabled = false
        try expect(hero.phase == .falling && hero.strands.isEmpty && hero.falls == 1, "Changing skin should resume the same fall")
        hero.webEnabled = true; _ = hero.updateGrip(field); drop(hero); try shooting(hero, toward: ledges)
        hero.beginDrag()
        try expect(hero.phase == .dragging && hero.strands.isEmpty && hero.incomingWebSupport == nil, "Picking up clears a pending shot")
    }
}
