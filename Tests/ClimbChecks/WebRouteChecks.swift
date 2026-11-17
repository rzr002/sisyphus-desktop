import CoreGraphics
import ClimbCore

func checkWebRoutes() {
    let bounds = CGRect(x: 0, y: 0, width: 1280, height: 800)
    func ink(_ surfaces: [Surface]) -> PixelTerrain {
        terrain(canvas(Int(bounds.width), height: Int(bounds.height)) { c in
            c.setFillColor(CGColor(gray: 0.05, alpha: 1))
            for s in surfaces { c.fill(s.frame.insetBy(dx: 2, dy: 2)) }
        })
    }

    check("A dead-end sidebar on either side can escape via newly visible ink below it") {
        let rows = stride(from: 113, through: 713, by: 65).map { CGRect(x: 55, y: $0, width: 34, height: 10) }
        let bridge = [(275,520), (478,505), (695,525), (885,510), (1075,525)].map {
            CGRect(x: $0.0, y: $0.1, width: 58, height: 10)
        }
        for mirrored in [false, true] {
            let ledges = (rows + bridge).enumerated().map { i, rect in
                let frame = mirrored ? rect.offsetBy(dx: bounds.width - rect.maxX - rect.minX, dy: 0) : rect
                return Surface(id: UInt32(i + 1), frame: frame)
            }
            let sidebar = ink(Array(ledges.prefix(rows.count)))
            let connected = ink(ledges)
            let hero = ClimbEngine(bounds: bounds, floor: 40, terrain: .handholds)
            hero.webEnabled = true
            hero.beginDrag()
            hero.drag(to: CGPoint(x: mirrored ? bounds.maxX - 72 : 72, y: hero.floor))
            hero.endDrag()
            for frame in 0..<(30 * 60) {
                if frame.isMultiple(of: 6) { _ = hero.updateGrip(sidebar) }
                hero.step(1 / 60, surfaces: ledges, mouse: nil)
                try expect(mirrored ? hero.position.x > bounds.maxX - 120 : hero.position.x < 120,
                           "A rectangle with no ink cannot provide an exit")
            }
            try expect(hero.position.y > 620, "Start from the actual dead end high on the sidebar")
            var shotDown = false, reachedCenter = false
            for frame in 0..<(22 * 60) {
                if frame.isMultiple(of: 6) { _ = hero.updateGrip(connected) }
                hero.step(1 / 60, surfaces: ledges, mouse: nil)
                if hero.phase == .webCasting, let tip = hero.webAnchor, tip.y < hero.position.y - 80 {
                    shotDown = connected.hasGrip(near: tip, radius: 5)
                }
                if abs(hero.position.x - bounds.midX) < 150 { reachedCenter = true; break }
            }
            try expect(shotDown && reachedCenter && hero.falls == 1,
                       "A real lower bridge should bring the hero back without another fall (mirrored=\(mirrored))")
        }
    }

    check("A lower exit can disappear during a cast without cutting the original swinging line") {
        let upper = Surface(id: 51, frame: CGRect(x: 155, y: 605, width: 50, height: 12))
        let lower = Surface(id: 52, frame: CGRect(x: 408, y: 410, width: 65, height: 12))
        let hero = ClimbEngine(bounds: bounds, floor: 40, terrain: .handholds)
        hero.webEnabled = true
        hero.beginDrag(); hero.drag(to: CGPoint(x: 185, y: 495)); hero.endDrag()
        let single = ink([upper]), both = ink([upper, lower])
        _ = hero.updateGrip(single)
        try expect(advance(hero, until: .webSwinging, surfaces: [upper]), "Catch the real outer ledge first")
        _ = hero.updateGrip(both)
        try expect(advance(hero, until: .webHandoff, surfaces: [upper, lower]), "Cast toward the lower exit")
        let old = hero.webAnchor
        _ = hero.updateGrip(single)
        try expect(hero.phase == .webSwinging && hero.webAnchor == old && hero.strands.count == 1,
                   "Keep hanging when only the new ink disappears")
        _ = hero.updateGrip(both)
        try expect(advance(hero, until: .webPulling, surfaces: [upper, lower]) && hero.support?.id == lower.id,
                   "Once the new tip attaches it can reel him over to the lower ledge")
    }

    check("A connected desktop keeps getting visits on both sides after the first minute") {
        var ledges: [Surface] = []
        for (i, x) in stride(from: 140, through: 1140, by: 170).enumerated() {
            for level in [300, 430, 560] {
                var s = Surface(id: UInt32(ledges.count + 1),
                                frame: CGRect(x: x, y: level + i % 2 * 20, width: 58, height: 10))
                s.windowID = x < 360 ? 1 : x > 900 ? 3 : 2
                ledges.append(s)
            }
        }
        let hero = ClimbEngine(bounds: bounds, floor: 40, terrain: .handholds)
        hero.webEnabled = true
        for minute in 0..<3 {
            var left = false, right = false
            for _ in 0..<(60 * 60) {
                hero.step(1 / 60, surfaces: ledges, mouse: nil)
                guard let tip = hero.webAnchor, hero.phase == .webSwinging else { continue }
                left = left || tip.x < bounds.width * 0.32
                right = right || tip.x > bounds.width * 0.68
            }
            try expect(left && right && hero.falls == 0, "Repeated catches stayed in one area in minute \(minute + 1)")
        }
    }
}
