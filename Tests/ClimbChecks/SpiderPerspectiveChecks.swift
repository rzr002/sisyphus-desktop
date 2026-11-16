import CoreGraphics
import ClimbCore

func checkSpiderPerspective() {
    check("A single fixed anchor yields distinct near and far passes without moving the ink") {
        let hero = webHero()
        try expect(advance(hero, until: .webSwinging, surfaces: [webLedge]), "Need a real pendulum")
        let tip = hero.webAnchor!
        var minScale: CGFloat = 2, maxScale: CGFloat = 0, maxStep: CGFloat = 0, previous = hero.projection.scale
        for _ in 0..<250 {
            hero.step(1 / 60, surfaces: [webLedge], mouse: nil)
            let view = hero.projection
            minScale = min(minScale, view.scale); maxScale = max(maxScale, view.scale)
            maxStep = max(maxStep, abs(view.scale - previous)); previous = view.scale
            guard let silk = hero.displayStrands.first else { throw CheckFailure(description: "Visual strand went missing") }
            try expect(silk.tip == tip && silk.hand == view.project(hero.gripOffset), "Only the wrist travels in depth; ink is pinned")
            try expect(view.body.y - hero.floor >= 0, "The projected body must stay above the floor")
        }
        try expect(minScale < 0.90 && maxScale > 1.16 && maxStep < 0.06,
                   "Depth should read across an arc and change smoothly: \(minScale)...\(maxScale), step \(maxStep)")
        hero.paused = true; let frozen = hero.projection
        tick(hero, seconds: 1, surfaces: [webLedge])
        try expect(hero.projection == frozen, "A frozen pose must hold its depth")
    }
    check("Both projected wrists follow the slingshot while its two anchors remain pinned to the desktop") {
        let hero = webHero()
        try expect(advance(hero, until: .webWindup, surfaces: skyline, seconds: 55), "Need a double silk slingshot")
        for _ in 0..<50 {
            hero.step(1 / 60, surfaces: skyline, mouse: nil)
            let held = hero.strands, drawn = hero.displayStrands, view = hero.projection
            if held.count == 2 && held.allSatisfy(\.attached) {
                try expect(held.map(\.tip) == drawn.map(\.tip) && drawn.map(\.hand) == [view.project(hero.gripOffset), view.project(hero.throwOffset)],
                           "Each end must use its own projected wrist and fixed desktop pixel")
                hero.beginDrag()
                try expect(hypot(hero.projection.body.x-view.body.x, hero.projection.body.y-view.body.y) < 0.01 && hero.displayStrands.isEmpty,
                           "Picking up a projected character must not jump away from the pointer")
                return
            }
        }
        throw CheckFailure(description: "Both endpoints never bore weight")
    }
    check("Reduced motion and ordinary characters stay flat without changing the trajectory") {
        let shown = webHero(), flat = webHero(); flat.perspectiveEnabled = false
        for _ in 0..<750 {
            for hero in [shown, flat] { hero.step(1 / 60, surfaces: [webLedge], mouse: nil) }
            try expect(flat.position == shown.position && flat.phase == shown.phase && flat.webAnchor == shown.webAnchor, "Visual depth must not change physics")
            try expect(flat.projection.scale == 1 && flat.projection.body == flat.position, "Reduced motion keeps the original overlay")
        }
        let ordinary = textClimber(); tick(ordinary, seconds: 4, surfaces: textHolds)
        try expect(ordinary.projection.scale == 1 && ordinary.projection.body == ordinary.position, "Imported/regular artwork stays at its authored size")
    }
}
