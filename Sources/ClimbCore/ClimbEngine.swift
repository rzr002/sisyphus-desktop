import Foundation
import CoreGraphics

public struct Surface: Equatable {
    public let id: UInt32
    public let name: String
    public var frame: CGRect
    public var windowID: UInt32?
    public init(id: UInt32, name: String = "Window", frame: CGRect) {
        self.id = id; self.name = name; self.frame = frame
    }
}

public enum Phase: String {
    case waiting, searching, walking, jumping, climbing, reaching, traversing, summit, falling, recovering, dragging
    case webCasting, webPulling, webSwinging, webHandoff, webVault
    case webWindup, webLaunch, webRappel, webKick, webRescue

    public var usesWeb: Bool {
        switch self {
        case .webCasting, .webPulling, .webSwinging, .webHandoff, .webVault, .webWindup, .webLaunch, .webRappel, .webKick, .webRescue: return true
        default: return false
        }
    }
    public var attached: Bool { (usesWeb && self != .webRescue) || [.jumping, .climbing, .reaching, .traversing, .summit].contains(self) }
    public var inFreeFall: Bool { self == .falling || self == .webRescue }
}
public enum Terrain { case windowEdges, handholds }
public enum Edge: Int { case left = 1, right = -1 }
public enum FallReason: String { case moved, closed, covered, mouse, summit, manual, erased }

public final class ClimbEngine {
    public let bounds: CGRect
    public let floor: CGFloat
    public let terrain: Terrain
    public private(set) var position: CGPoint
    public private(set) var phase: Phase = .waiting
    public private(set) var support: Surface?
    public private(set) var edge: Edge = .left
    public private(set) var attempt = 1
    public private(set) var falls = 0
    public private(set) var bestHeight: CGFloat = 0
    public private(set) var lastFall: FallReason?
    public private(set) var phaseTime: Double = 0
    public private(set) var elapsed: Double = 0
    public var webEnabled = false {
        didSet { if !webEnabled { if phase.usesWeb { fall(.manual) }; webField = nil; webRoute = WebRoute(); camera = SwingCamera() } }
    }
    public var webAnchor: CGPoint? { web?.anchor }
    public var incomingWebSupport: Surface? { swingTarget?.surface }
    public private(set) var wristSide: CGFloat = -1
    public var gripOffset: CGPoint {
        if phase == .webWindup, let sling, let web {
            return WebMotion.blend(sling.initialWrist, aimedWrist(at: web.anchor), phaseTime / WebSlingshot.cast)
        }
        return web?.wristOffset ?? CGPoint(x: wristSide * 8 * facing, y: WebMotion.wristHeight)
    }
    public var webHand: CGPoint { CGPoint(x: position.x + gripOffset.x, y: position.y + gripOffset.y) }
    public var throwOffset: CGPoint {
        guard let next = swingTarget else { return .zero }
        return aimedWrist(at: next.anchor)
    }
    private func aimedWrist(at anchor: CGPoint) -> CGPoint {
        let dx = anchor.x - position.x, dy = anchor.y - position.y - 8
        let distance = max(1, hypot(dx, dy))
        if phase == .webWindup {
            return CGPoint(x: (dx < 0 ? -1 : 1) * (14 + 16 * abs(dx) / distance), y: 9 + 24 * dy / distance)
        }
        return CGPoint(x: 32 * dx / distance, y: 8 + 28 * dy / distance)
    }
    public var flipProgress: CGFloat { phase == .webVault ? min(1, phaseTime / WebMotion.flipTime) : 0 }
    public var poseProgress: CGFloat {
        switch phase {
        case .webWindup: return WebSlingshot.tension(at: phaseTime)
        case .webLaunch: return min(1, phaseTime / WebSlingshot.flight)
        case .webRappel: return WebMotion.rappelExtension(at: phaseTime)
        case .webKick: return min(1, phaseTime / WebMotion.kickTime)
        case .webRescue: return min(1, phaseTime / WebRescue.flight)
        default: return flipProgress
        }
    }
    public var strands: [WebStrand] { strands(in: SpiderProjection(body: position, scale: 1, depth: 0)) }
    public var displayStrands: [WebStrand] { strands(in: projection) }
    private func strands(in view: SpiderProjection) -> [WebStrand] {
        var result: [WebStrand] = []
        if let web {
            let hand = view.project(gripOffset)
            let tip = phase == .webCasting ? WebMotion.blend(hand, web.anchor, min(1, phaseTime / WebMotion.castTime)) : web.anchor
            result.append(WebStrand(hand: hand, tip: tip, attached: phase != .webCasting))
        }
        if let target = swingTarget {
            let time: Double
            switch phase {
            case .webVault: time = phaseTime - WebMotion.flipTime
            case .webLaunch: time = phaseTime - (WebSlingshot.flight - WebMotion.handoffTime)
            default: time = phaseTime
            }
            if time > 0 {
                let hand = view.project(throwOffset)
                let tip = WebMotion.blend(hand, target.anchor, min(1, time / WebMotion.handoffTime))
                result.append(WebStrand(hand: hand, tip: tip, attached: secondStrandLoaded))
            }
        }
        return result
    }
    public var webTip: CGPoint? {
        guard let web else { return nil }
        return phase == .webCasting ? WebMotion.blend(webHand, web.anchor, min(1, phaseTime / WebMotion.castTime)) : web.anchor
    }
    public var swingAngle: CGFloat { web?.angle ?? 0 }
    private var camera = SwingCamera()
    public var perspectiveEnabled = true { didSet { if !perspectiveEnabled { camera = SwingCamera() } } }
    public var projection: SpiderProjection {
        guard webEnabled && perspectiveEnabled else { return SpiderProjection(body: position, scale: 1, depth: 0) }
        return camera.view(body: position, bounds: bounds, floor: floor)
    }
    private var web: WebMotion?
    private var webRoute = WebRoute()
    private var swingTarget: SwingTarget?
    private var rescue = WebRescue()
    private var sling: WebSlingshot?
    private var nextSlingTime: Double = 6
    private var nextVaultTime: Double = 0
    private var nextKickTime: Double = 3
    private var nextRappelTime: Double = 0
    private var secondStrandLoaded: Bool { phase == .webWindup && phaseTime >= WebSlingshot.cast }
    private var hasTransferred = false
    private var webField: PixelTerrain?
    private var nextSwingTime: Double = 2.2
    private var nextLateralWebTime: Double = 0
    private var lastWebSearch: Double = -1
    public var paused = false
    public var mouseEnabled = true
    public var speed: Double = 1
    public var height: CGFloat { max(0, position.y - floor) }
    public var gripX: CGFloat {
        guard let support else { return position.x + 18 }
        if terrain == .handholds { return min(support.frame.maxX - 3, max(support.frame.minX + 3, position.x + 9)) }
        return edge == .left ? max(bounds.minX + 7, support.frame.minX + 3) : min(bounds.maxX - 7, support.frame.maxX - 3)
    }
    public var facing: CGFloat {
        if terrain == .handholds && [.climbing, .reaching, .traversing].contains(phase) { return direction }
        if phase == .climbing { return gripX >= position.x ? 1 : -1 }
        return direction
    }
    private var direction: CGFloat = 1
    private var velocity = CGVector.zero
    private var jumpStart = CGPoint.zero
    private var jumpEnd = CGPoint.zero
    private var jumpDuration: Double = 0.9
    private var groundTarget: CGFloat = 0
    private var lastSearch: Double = -1
    private var armedTime: Double = 0
    private var nextHold: Surface?
    private var gripStability = GripStability()
    private enum WindowOwner { case desktop, window(Surface) }
    private var windowOwners: [UInt32: WindowOwner] = [:]
    public func beginDrag() {
        position = projection.body; camera.pinUnderPointer()
        webRoute = WebRoute()
        windowOwners.removeAll()
        web = nil; swingTarget = nil; sling = nil; hasTransferred = false; support = nil; nextHold = nil; velocity = .zero; gripStability.reset()
        transition(.dragging)
    }
    public func drag(to point: CGPoint) {
        guard phase == .dragging else { return }
        position = CGPoint(x: max(bounds.minX + 32, min(bounds.maxX - 32, point.x)),
                           y: max(floor, min(bounds.maxY - 56, point.y)))
    }
    public func endDrag() {
        guard phase == .dragging else { return }
        rescue = WebRescue()
        falls += 1; lastFall = .manual; velocity = .zero
        armedTime = elapsed + 0.8; transition(.falling)
    }
    /// Recheck load-bearing pixels, independently of object/rectangle identity.
    /// The returned anchor can be retained across segmentation changes for one noisy frame.
    public func updateGrip(_ field: PixelTerrain) -> Surface? {
        if webEnabled {
            webField = field
            if let target = swingTarget, !field.hasGrip(near: target.anchor, radius: 5) {
                cancelTransfer(.erased)
            }
            if let web, let support {
                if gripStability.shouldRelease(hasGrip: field.hasGrip(near: web.anchor, radius: 5)) {
                    releaseSupport(.erased); return self.support
                }
                return support
            }
        }
        guard terrain == .handholds, [.climbing, .reaching, .traversing].contains(phase), let anchor = support else {
            gripStability.reset(); return nil
        }
        let x = phase == .reaching ? jumpStart.x : position.x
        let y = anchor.frame.minY + min(4, anchor.frame.height / 2)
        let contacts = [-10.0, 10.0].map { offset in
            CGPoint(x: min(anchor.frame.maxX - 2, max(anchor.frame.minX + 2, x + offset)), y: y)
        }
        let present = contacts.contains { field.hasGrip(near: $0) }
        if gripStability.shouldRelease(hasGrip: present) { fall(.erased); return nil }
        return anchor
    }
    public init(bounds: CGRect, floor: CGFloat, terrain: Terrain = .windowEdges) {
        self.bounds = bounds; self.floor = floor; self.terrain = terrain
        position = CGPoint(x: bounds.midX, y: floor)
    }
    public func step(_ rawDT: Double, surfaces: [Surface], mouse: CGPoint?) {
        guard !paused, rawDT.isFinite, rawDT > 0 else { return }
        let dt = min(rawDT, 0.05) * max(0.25, min(2, speed))
        elapsed += dt
        defer {
            if webEnabled && perspectiveEnabled && phase != .dragging {
                camera.follow(phase, angle: swingAngle, progress: poseProgress, body: position,
                              anchor: webAnchor ?? swingTarget?.anchor, dt: dt)
            }
        }

        if phase.attached, mouseEnabled, elapsed > armedTime, height > 28, let mouse,
           hypot(mouse.x - position.x, mouse.y - (position.y + 4)) < 34 {
            fall(.mouse); return
        }
        if let target = swingTarget, let lost = loss(of: target.surface, in: surfaces) { cancelTransfer(lost) }
        if phase.attached, let anchor = support {
            if let lost = loss(of: anchor, in: surfaces) { releaseSupport(lost); return }
            let b = anchor.frame
            let hand = CGPoint(x: phase == .climbing ? gripX : position.x, y: min(b.maxY - 5, position.y + 16))
            if terrain == .windowEdges && phase != .jumping && !isExposed(hand, on: anchor, surfaces: surfaces) { fall(.covered); return }
        }

        phaseTime += dt
        if terrain == .handholds {
            stepHandholds(dt, surfaces: surfaces)
            bestHeight = max(bestHeight, height)
            return
        }

        switch phase {
        case .searching, .reaching, .dragging, .webCasting, .webPulling, .webSwinging, .webHandoff, .webVault,
             .webWindup, .webLaunch, .webRappel, .webKick, .webRescue: break
        case .waiting:
            if elapsed - lastSearch > 0.5 {
                lastSearch = elapsed
                if let route = findRoute(surfaces, fromGround: true) {
                    support = route.surface; edge = route.edge; groundTarget = route.point.x
                    transition(.walking)
                }
            }
        case .walking:
            guard let anchor = support, let current = surfaces.first(where: { $0.id == anchor.id }), current.frame == anchor.frame else {
                support = nil; transition(.waiting); return
            }
            let delta = groundTarget - position.x
            direction = delta >= 0 ? 1 : -1
            if abs(delta) <= 150 * dt {
                position.x = groundTarget
                let y = max(floor + 12, anchor.frame.minY + 34)
                launch(to: CGPoint(x: groundTarget, y: y))
            } else { position.x += direction * 150 * dt }
        case .jumping:
            let t = min(1, phaseTime / jumpDuration)
            let smooth = t * t * (3 - 2 * t)
            position = CGPoint(x: jumpStart.x + (jumpEnd.x - jumpStart.x) * smooth,
                               y: jumpStart.y + (jumpEnd.y - jumpStart.y) * smooth + sin(t * .pi) * 52)
            if t >= 1 { transition(.climbing); armedTime = elapsed + 0.5 }
        case .climbing:
            guard let anchor = support else { transition(.waiting); return }
            // Slow at each hand exchange; the body rises in deliberate little pulls.
            let rhythm = 0.62 + 0.58 * pow(sin(elapsed * .pi * 1.2), 2)
            position.y += 52 * rhythm * dt
            if position.y >= min(anchor.frame.maxY - 23, bounds.maxY - 68) {
                position.y = min(anchor.frame.maxY + 28, bounds.maxY - 42)
                transition(.traversing)
            }
        case .traversing:
            guard let anchor = support else { fall(.closed); return }
            if phaseTime > 0.55, let route = findRoute(surfaces, fromGround: false) {
                support = route.surface; edge = route.edge; launch(to: route.point)
            } else {
                let target = min(bounds.maxX - 35, max(bounds.minX + 35, anchor.frame.midX))
                direction = target >= position.x ? 1 : -1
                let delta = target - position.x
                position.x += direction * min(abs(delta), 92 * dt)
                if abs(delta) < 3 || phaseTime > 4 { transition(.summit) }
            }
        case .summit:
            if phaseTime > 2.4 { fall(.summit) }
        case .falling:
            velocity.dy -= 980 * dt
            position.x += velocity.dx * dt; position.y += velocity.dy * dt
            if position.x < bounds.minX + 28 || position.x > bounds.maxX - 28 { velocity.dx *= -0.5 }
            position.x = min(bounds.maxX - 28, max(bounds.minX + 28, position.x))
            if position.y <= floor {
                position.y = floor; velocity = .zero; transition(.recovering)
            }
        case .recovering:
            if phaseTime > 1.65 {
                attempt += 1; support = nil; lastSearch = -1
                transition(.waiting)
            }
        }
        bestHeight = max(bestHeight, height)
    }

    public func fall(_ reason: FallReason) {
        if phase == .webRescue { cancelTransfer(reason); return }
        guard phase != .falling && phase != .recovering else { return }
        let lost = support ?? swingTarget?.surface
        rescue = WebRescue()
        rescue.lostGrip = lost?.id
        if reason == .moved || reason == .closed {
            if let lost, case .window(let owner) = windowOwners[lost.id] { rescue.lostWindow = owner.id }
            else { rescue.lostWindow = lost?.windowID }
        }
        lastFall = reason; falls += 1
        windowOwners.removeAll()
        if phase != .webVault && phase != .webLaunch { velocity = web?.speed ?? CGVector(dx: -facing * 105, dy: 105) }
        web = nil; swingTarget = nil; sling = nil; hasTransferred = false; nextHold = nil; gripStability.reset()
        nextSwingTime = elapsed + 3
        support = nil
        transition(.falling)
    }

    public func restart() {
        camera = SwingCamera()
        webRoute = WebRoute()
        windowOwners.removeAll()
        attempt += 1; support = nil; nextHold = nil; lastFall = nil; velocity = .zero
        position = CGPoint(x: bounds.midX, y: floor)
        web = nil; swingTarget = nil; sling = nil; hasTransferred = false; gripStability.reset(); lastWebSearch = -1; nextSwingTime = elapsed + 2.2; nextLateralWebTime = elapsed
        nextSlingTime = elapsed + 6; nextVaultTime = elapsed; nextKickTime = elapsed + 3; nextRappelTime = elapsed
        lastSearch = -1; transition(.waiting)
    }

    private func transition(_ next: Phase) { phase = next; phaseTime = 0 }

    private func loss(of anchor: Surface, in surfaces: [Surface]) -> FallReason? {
        guard let current = surfaces.first(where: { $0.id == anchor.id }) else { return .closed }
        return frameChanged(anchor.frame, current.frame) ? .moved : nil
    }

    private func frameChanged(_ a: CGRect, _ b: CGRect) -> Bool {
        max(abs(a.minX - b.minX), abs(a.minY - b.minY), abs(a.width - b.width), abs(a.height - b.height)) > 2
    }

    private func releaseSupport(_ reason: FallReason) {
        if secondStrandLoaded, let target = swingTarget { catchNext(target, speed: web?.speed ?? .zero) }
        else { fall(reason) }
    }

    /// Keep each tip tied to the window that supplied its pixels, including
    /// the second arm during a draw and the pending recatch during free flight.
    public func validateWindowContacts(current: [Surface], captured: [Surface]) {
        guard phase.attached || swingTarget != nil else { windowOwners.removeAll(); return }
        windowOwners = windowOwners.filter { $0.key == support?.id || $0.key == swingTarget?.surface.id }
        func check(_ hold: Surface, at tip: CGPoint) -> FallReason? {
            let owner = windowOwners[hold.id] ?? captured.first { $0.frame.contains(tip) }.map(WindowOwner.window) ?? .desktop
            windowOwners[hold.id] = owner
            let front = current.first { $0.frame.contains(tip) }
            switch owner {
            case .desktop: return front == nil ? nil : .covered
            case .window(let before):
                guard let after = current.first(where: { $0.id == before.id }) else { return .closed }
                if frameChanged(before.frame, after.frame) { return .moved }
                return front?.id == before.id ? nil : .covered
            }
        }
        // Check the incoming endpoint first so a missing pair can never rescue itself.
        if let target = swingTarget, let reason = check(target.surface, at: target.anchor) { cancelTransfer(reason) }
        if let support {
            let point = webAnchor ?? CGPoint(x: support.frame.midX, y: support.frame.midY)
            if let reason = check(support, at: point) { releaseSupport(reason) }
        }
    }

    private func holdRoute(_ surfaces: [Surface], fromGround: Bool) -> Route? {
        let currentGripY = support?.frame.minY ?? floor + 28
        var options: [Route] = []
        for s in surfaces {
            let r = s.frame
            guard r.width >= 8, r.height >= 4, r.height <= 70, r.minY < bounds.maxY - 35 else { continue }
            let bodyY = r.minY - 29
            if fromGround {
                guard bodyY >= floor + 8, bodyY <= floor + 118 else { continue }
            } else {
                guard s.id != support?.id, r.minY > currentGripY + 23, r.minY < currentGripY + 123 else { continue }
            }
            let x = max(bounds.minX + 30, min(bounds.maxX - 30, min(r.maxX - 4, max(r.minX + 4, position.x))))
            let horizontal = abs(x - position.x)
            if !fromGround && horizontal > 122 { continue }
            options.append(Route(surface: s, edge: .left, point: CGPoint(x: x, y: bodyY),
                                 score: horizontal * 1.1 + (bodyY - position.y) * 0.7))
        }
        return options.min { $0.score < $1.score }
    }

    private func stepHandholds(_ dt: Double, surfaces: [Surface]) {
        switch phase {
        case .waiting, .searching:
            if phase == .waiting { transition(.searching) }
            if elapsed - lastSearch > 0.35 {
                lastSearch = elapsed
                if let route = holdRoute(surfaces, fromGround: true) {
                    if webEnabled, abs(route.point.x - position.x) > 115, tryWebAcross(surfaces) { return }
                    support = route.surface; groundTarget = route.point.x; jumpEnd = route.point
                    transition(.walking); return
                }
                if webEnabled, tryWebAcross(surfaces) { return }
            }
            position.x += direction * 62 * dt
            if position.x > bounds.maxX - 48 { direction = -1 }
            if position.x < bounds.minX + 48 { direction = 1 }
            position.x = max(bounds.minX + 32, min(bounds.maxX - 32, position.x))
        case .walking:
            guard let anchor = support, let fresh = surfaces.first(where: { $0.id == anchor.id }),
                  abs(fresh.frame.minX - anchor.frame.minX) <= 2, abs(fresh.frame.minY - anchor.frame.minY) <= 2,
                  abs(fresh.frame.width - anchor.frame.width) <= 2, abs(fresh.frame.height - anchor.frame.height) <= 2 else {
                support = nil; transition(.searching); return
            }
            let delta = groundTarget - position.x
            if abs(delta) <= 145 * dt { position.x = groundTarget; launch(to: jumpEnd) }
            else { direction = delta > 0 ? 1 : -1; position.x += direction * 145 * dt }
        case .jumping:
            let t = min(1, phaseTime / jumpDuration), smooth = t * t * (3 - 2 * t)
            position = CGPoint(x: jumpStart.x + (jumpEnd.x - jumpStart.x) * smooth,
                               y: jumpStart.y + (jumpEnd.y - jumpStart.y) * smooth + sin(t * .pi) * 20)
            if t >= 1 { transition(.climbing); armedTime = elapsed + 0.45 }
        case .climbing, .traversing:
            guard let anchor = support else { transition(.searching); return }
            let canSearchWeb = webEnabled && elapsed - lastWebSearch > 0.45
            if webEnabled, phaseTime > 0.45, elapsed >= nextSwingTime,
               beginSwing(on: anchor) { return }
            // A sidebar can be climbable all the way to the top but too close
            // to the bezel for a pendulum. Take an opening while it is in reach.
            if canSearchWeb, phaseTime > 0.45,
               let inward = webRoute.inward(from: position.x, in: bounds),
               elapsed >= nextSwingTime || !swingArea.intersects(anchor.frame),
               tryWebAcross(surfaces, toward: inward) { return }
            if phaseTime > 0.55, let route = holdRoute(surfaces, fromGround: false) {
                nextHold = route.surface; jumpStart = position; jumpEnd = route.point
                direction = jumpEnd.x >= position.x ? 1 : -1; transition(.reaching)
            } else if canSearchWeb, phaseTime > 0.7, tryWebAcross(surfaces) {
                return
            } else if phaseTime > 1.2 {
                if phase == .climbing { transition(.traversing) }
                let left = max(bounds.minX + 30, anchor.frame.minX + 5)
                let right = min(bounds.maxX - 30, max(left, anchor.frame.maxX - 5))
                position.x += direction * 38 * dt
                if position.x >= right { position.x = right; direction = -1 }
                if position.x <= left { position.x = left; direction = 1 }
            }
        case .reaching:
            guard let target = nextHold, let fresh = surfaces.first(where: { $0.id == target.id }) else { fall(.closed); return }
            if abs(fresh.frame.minX - target.frame.minX) > 2 || abs(fresh.frame.minY - target.frame.minY) > 2 { fall(.moved); return }
            let t = min(1, phaseTime / 0.85), eased = t * t * (3 - 2 * t)
            position = CGPoint(x: jumpStart.x + (jumpEnd.x - jumpStart.x) * eased,
                               y: jumpStart.y + (jumpEnd.y - jumpStart.y) * eased)
            if t >= 1 { support = target; nextHold = nil; transition(.climbing) }
        case .falling, .webRescue:
            advanceFall(dt, surfaces: surfaces)
        case .recovering:
            if phaseTime > 1.65 { attempt += 1; support = nil; nextHold = nil; lastSearch = -1; transition(.searching) }
        case .webCasting, .webPulling, .webSwinging, .webHandoff, .webVault, .webWindup, .webLaunch, .webRappel, .webKick:
            advanceWeb(dt, surfaces: surfaces)
        case .summit, .dragging: break
        }
    }

    private func advanceFall(_ dt: Double, surfaces: [Surface]) {
        // Integrate only up to impact: coarse frames must not put the body under the floor before the silk catches.
        let air = phase == .webRescue ? min(dt, max(0, WebRescue.flight - (phaseTime - dt))) : dt
        position = WebRescue.fallingPoint(position, velocity, after: air, in: bounds)
        velocity.dy -= WebRescue.gravity * air
        if position.y <= floor {
            swingTarget = nil; position.y = floor; velocity = .zero; transition(.recovering); return
        }
        if phase == .webRescue {
            if phaseTime >= WebRescue.flight, let target = swingTarget {
                catchNext(target, speed: velocity)
                let rest = dt - air
                if rest > 0.000001 { phaseTime += rest; advanceWeb(rest, surfaces: surfaces) }
            }
        } else if webEnabled, let field = webField,
                  let target = rescue.shot(age: phaseTime, body: position, velocity: velocity, facing: facing,
                                          bounds: bounds, floor: floor, surfaces: surfaces, field: field, length: swingLength) {
            swingTarget = target
            direction = target.anchor.x >= position.x ? 1 : -1
            wristSide = -1
            transition(.webRescue)
        }
    }
    private func contact(on surface: Surface, near x: CGFloat, within area: CGRect? = nil) -> CGPoint? {
        let safe = surface.frame.intersection(area ?? bounds.insetBy(dx: 42, dy: 38))
        guard !safe.isNull, safe.width > 1, safe.height > 1 else { return nil }
        let point = CGPoint(x: min(safe.maxX - 0.5, max(safe.minX + 0.5, x)), y: safe.midY)
        if let field = webField { return field.nearestEdge(in: safe, to: point) }
        return point // Geometry-only clients supply already established surfaces.
    }

    private func tryWebAcross(_ surfaces: [Surface], toward heading: CGFloat? = nil) -> Bool {
        lastWebSearch = elapsed
        let hand = webHand
        let aimX = hand.x + (heading ?? 0) * WebRoute.preferredStep
        func score(_ point: CGPoint) -> CGFloat? {
            let dx = point.x - hand.x, dy = point.y - hand.y
            let distance = hypot(dx, dy)
            guard distance <= 390 else { return nil }
            if let heading {
                let progress = dx * heading
                guard progress >= 85, dy >= -210, point.y - 29 >= floor + WebMotion.groundClearance else { return nil }
                return abs(progress - WebRoute.preferredStep) + 0.65 * abs(dy) + webRoute.revisitCost(at: point)
            }
            let crossesGap = support != nil && abs(dx) > 122 && abs(dy) <= 24 && elapsed >= nextLateralWebTime
            guard dy > 12 || crossesGap else { return nil }
            return distance + abs(dx) * 0.12 + (dy > 12 ? 0 : 180)
        }
        let candidates = surfaces.compactMap { surface -> (Surface, CGFloat)? in
            let r = surface.frame
            guard surface.id != support?.id, r.width >= 8, r.height >= 4 else { return nil }
            let point = CGPoint(x: min(r.maxX - 1, max(r.minX + 1, aimX)), y: r.midY)
            guard let rank = score(point) else { return nil }
            return (surface, rank)
        }.sorted { $0.1 < $1.1 }
        for (target, _) in candidates {
            guard let anchor = contact(on: target, near: aimX), score(anchor) != nil else { continue }
            if phase == .webSwinging {
                // Keep moving on the loaded strand until the other wrist's
                // line has actually reached the ledge.
                swingTarget = SwingTarget(surface: target, anchor: anchor, length: nil)
                transition(.webHandoff)
                return true
            }
            if heading == nil && anchor.y - hand.y <= 12 { nextLateralWebTime = elapsed + 7 }
            direction = anchor.x >= hand.x ? 1 : -1
            startWeb(on: target, at: anchor, length: nil)
            return true
        }
        return false
    }

    private func beginSwing(on surface: Surface) -> Bool {
        guard let anchor = contact(on: surface, near: position.x, within: swingArea) else { return false }
        guard let length = swingLength(at: anchor) else { return false }
        startWeb(on: surface, at: anchor, length: length)
        return true
    }

    private static let minimumSwingLength: CGFloat = 74

    private var swingArea: CGRect {
        let margin = 54 + Self.minimumSwingLength
        let bottom = floor + WebMotion.wristHeight + WebMotion.groundClearance + Self.minimumSwingLength
        let width = bounds.width - 2 * margin, height = bounds.maxY - 38 - bottom
        guard width > 0, height > 0 else { return .null }
        return CGRect(x: bounds.minX + margin, y: bottom, width: width, height: height)
    }

    private func swingLength(at anchor: CGPoint) -> CGFloat? {
        let side = min(anchor.x - bounds.minX, bounds.maxX - anchor.x) - 54
        let length = min(158, side, anchor.y - floor - WebMotion.wristHeight - WebMotion.groundClearance)
        return length >= Self.minimumSwingLength ? length : nil
    }

    private func startWeb(on surface: Surface, at anchor: CGPoint, length: CGFloat?) {
        wristSide = -wristSide
        web = WebMotion(anchor: anchor, body: position, swingLength: length, direction: direction, wristX: wristSide * 8 * direction)
        swingTarget = nil; hasTransferred = false
        support = surface; nextHold = nil; gripStability.reset()
        armedTime = elapsed + 0.45; transition(.webCasting)
    }

    private func nextSwingTarget(in surfaces: [Surface], motion: WebMotion) -> SwingTarget? {
        let hand = webHand, heading: CGFloat = motion.speed.dx > 0 ? 1 : -1
        let preferred = CGPoint(x: motion.anchor.x + heading * WebRoute.preferredStep, y: motion.anchor.y + 40)
        let area = swingArea
        let candidates = surfaces.compactMap { surface -> (Surface, CGFloat, CGFloat)? in
            guard surface.id != support?.id, surface.frame.width >= 8, surface.frame.height >= 4 else { return nil }
            let rect = surface.frame.intersection(area)
            guard !rect.isNull, rect.width > 1, rect.height > 1 else { return nil }
            let x = min(rect.maxX - 1, max(rect.minX + 1, preferred.x))
            let dx = (x - hand.x) * heading, dy = rect.midY - hand.y
            guard dx > 58, (x - motion.anchor.x) * heading >= 125, dy >= 46, dy <= 255,
                  hypot(dx, dy) <= 350 else { return nil }
            let newWindow = surface.windowID != nil && support?.windowID != nil && surface.windowID != support?.windowID
            let visitCost = webRoute.revisitCost(at: CGPoint(x: x, y: rect.midY))
            let score = abs(x - preferred.x) + 0.85 * abs(rect.midY - preferred.y) + visitCost - (newWindow ? 75 : 0)
            return (surface, x, score)
        }.sorted { $0.2 < $1.2 }
        for (surface, x, _) in candidates {
            guard let anchor = contact(on: surface, near: x, within: area), let length = swingLength(at: anchor),
                  anchor.y - hand.y >= 40, (anchor.x - hand.x) * heading >= 50,
                  hypot(anchor.x - hand.x, anchor.y - hand.y) <= 355 else { continue }
            return SwingTarget(surface: surface, anchor: anchor, length: length)
        }
        return nil
    }

    private func attemptTransfer(_ motion: WebMotion, surfaces: [Surface]) {
        guard motion.age >= 0.95, elapsed - lastWebSearch > 0.19 else { return }
        lastWebSearch = elapsed
        let course = webRoute.preferredHeading(from: motion.anchor.x, in: bounds)
        let swingHeading: CGFloat = motion.speed.dx >= 0 ? 1 : -1
        let aligned = course == nil || course == swingHeading
        // Wait for the return half of the arc before shooting back out to an
        // edge. If the useful foothold is lower, a diagonal zip can reach it.
        guard (aligned || motion.age >= 4.2), abs(motion.speed.dx) > 95,
              let next = nextSwingTarget(in: surfaces, motion: motion) else {
            if motion.age >= 3.0, aligned, let course { _ = tryWebAcross(surfaces, toward: course) }
            return
        }
        swingTarget = next
        let leap = CGVector(dx: max(-310, min(310, motion.speed.dx)), dy: max(135, min(205, motion.speed.dy + 145)))
        let t = CGFloat(WebMotion.vaultTime)
        let landingX = position.x + leap.dx * t
        let landingY = position.y + leap.dy * t - 0.5 * 690 * t * t
        let canFlip = hasTransferred && elapsed >= nextVaultTime && height >= 44 && position.y + 85 < bounds.maxY &&
            landingX > bounds.minX + 48 && landingX < bounds.maxX - 48 && landingY > floor + 44 &&
            next.anchor.y - landingY > WebMotion.wristHeight + 20
        if elapsed >= nextSlingTime, !canFlip || nextSlingTime < nextVaultTime,
           let plan = WebSlingshot(from: position, on: motion, toward: next.anchor, bounds: bounds, floor: floor) {
            sling = plan; nextSlingTime = elapsed + 6.8
            direction = next.anchor.x > position.x ? 1 : -1
            transition(.webWindup)
        } else if canFlip {
            nextVaultTime = elapsed + 5.5
            web = nil; support = nil; velocity = leap; transition(.webVault)
        } else { transition(.webHandoff) }
    }

    private func cancelTransfer(_ reason: FallReason) {
        if phase == .webLaunch || phase == .webVault { fall(reason); return }
        let wrist = gripOffset
        swingTarget = nil; sling = nil; lastWebSearch = elapsed
        switch phase {
        case .webRescue: transition(.falling) // The line never bore weight; keep the same fall and its velocity.
        case .webWindup:
            // The surviving silk passes through the actual wrist at the
            // interrupted draw depth, not the old pendulum's previous body.
            if var rope = web {
                rope.age = 0
                rope.catchMovingBody(position, velocity: rope.speed, from: wrist)
                web = rope
            }
            transition(.webSwinging)
        case .webHandoff: transition(.webSwinging)
        default: break
        }
    }

    private func catchNext(_ target: SwingTarget, speed: CGVector) {
        let wrist = throwOffset
        wristSide = -wristSide
        direction = target.anchor.x >= position.x ? 1 : -1
        var motion = WebMotion(anchor: target.anchor, body: position, swingLength: target.length,
                               direction: direction, wristX: wristSide * 8 * direction)
        support = target.surface; swingTarget = nil; sling = nil
        if target.length != nil {
            motion.catchMovingBody(position, velocity: speed, from: wrist)
            webRoute.landed(at: target.anchor)
            hasTransferred = true
            transition(.webSwinging)
        } else {
            transition(.webPulling)
        }
        web = motion; gripStability.reset()
    }

    private func advanceWeb(_ dt: Double, surfaces: [Surface]) {
        if phase == .webLaunch, let sling, let target = swingTarget {
            position = sling.airborne(at: phaseTime)
            velocity = sling.airborneVelocity(at: phaseTime)
            if phaseTime >= WebSlingshot.flight { catchNext(target, speed: velocity) }
            return
        }
        if phase == .webVault, let target = swingTarget {
            // Stop exactly at the catch, even if the frame spans it. This is the
            // same parabola used to assess floor clearance before releasing.
            let air = min(dt, max(0, WebMotion.vaultTime - (phaseTime - dt)))
            position.x += velocity.dx * air
            position.y += velocity.dy * air - 0.5 * 690 * air * air
            velocity.dy -= 690 * air
            if phaseTime >= WebMotion.vaultTime { catchNext(target, speed: velocity) }
            return
        }
        guard var motion = web else { fall(.erased); return }
        let old = position
        switch phase {
        case .webCasting:
            if phaseTime >= WebMotion.castTime {
                if motion.swingLength != nil { webRoute.landed(at: motion.anchor) }
                transition(motion.swingLength == nil ? .webPulling : .webSwinging)
            }
        case .webPulling:
            let (point, finished) = motion.pulledBody(time: phaseTime)
            position = point
            if finished {
                webRoute.landed(at: motion.anchor)
                web = nil; gripStability.reset(); transition(.climbing)
                return
            }
        case .webWindup:
            guard let sling else { fall(.erased); return }
            position = sling.loading(at: phaseTime)
            if phaseTime >= WebSlingshot.windup {
                velocity = sling.impulse; web = nil; support = nil; transition(.webLaunch)
                return
            }
        case .webRappel:
            let reach = WebMotion.rappelExtension(at: phaseTime)
            let dx = max(-60, min(60, motion.anchor.x - motion.wristOffset.x - motion.start.x))
            let drop = min(58, motion.start.y - floor - WebMotion.groundClearance)
            position = CGPoint(x: motion.start.x + dx * reach, y: motion.start.y - drop * reach)
            if phaseTime >= WebMotion.rappelTime { transition(.webSwinging) }
        case .webSwinging, .webHandoff, .webKick:
            guard let length = motion.swingLength else { fall(.erased); return }
            position = motion.swingingBody(dt: dt, length: length, floor: floor)
            // Ground clearance is enforced through the strand length, not by
            // displacing or releasing an otherwise supported character.
            position.x = max(bounds.minX + 43, min(bounds.maxX - 43, position.x))
            if phase == .webKick && phaseTime >= WebMotion.kickTime {
                transition(.webSwinging)
            } else if phase == .webSwinging && motion.age >= 6.8 {
                motion.start = position; nextSwingTime = elapsed + 4
                transition(.webPulling)
            }
        default: return
        }
        motion.speed = CGVector(dx: (position.x - old.x) / dt, dy: (position.y - old.y) / dt)
        web = motion
        if phase == .webHandoff, let target = swingTarget, phaseTime >= WebMotion.handoffTime {
            catchNext(target, speed: motion.speed)
        } else if phase == .webSwinging {
            attemptTransfer(motion, surfaces: surfaces)
            if phase == .webSwinging { attemptSoloTrick(motion) }
        }
    }

    private func attemptSoloTrick(_ motion: WebMotion) {
        if elapsed >= nextRappelTime, motion.age >= 3.9, abs(motion.speed.dx) < 52, height >= 58 {
            web?.start = position
            nextRappelTime = elapsed + 10
            transition(.webRappel)
        } else if elapsed >= nextKickTime, abs(motion.speed.dx) > 135,
                  (hasTransferred && motion.age >= 0.28 || motion.age >= 4.8) {
            nextKickTime = elapsed + 4.5
            transition(.webKick)
        }
    }
    private func launch(to point: CGPoint) {
        jumpStart = position; jumpEnd = point
        jumpDuration = min(1.35, max(0.75, hypot(point.x - position.x, point.y - position.y) / 270))
        direction = point.x >= position.x ? 1 : -1
        armedTime = elapsed + 0.7; transition(.jumping)
    }

    private struct Route { let surface: Surface; let edge: Edge; let point: CGPoint; let score: CGFloat }
    private func findRoute(_ surfaces: [Surface], fromGround: Bool) -> Route? {
        var routes: [Route] = []
        for (index, surface) in surfaces.enumerated() {
            let frame = surface.frame.intersection(bounds)
            guard !frame.isNull, frame.width >= 120, frame.height >= 90, frame.maxY > floor + 70 else { continue }
            if !fromGround && (surface.id == support?.id || frame.maxY < position.y + 90) { continue }
            let y = fromGround ? max(floor + 12, frame.minY + 34) : max(position.y + 35, frame.minY + 34)
            guard y <= (fromGround ? floor + 240 : position.y + 190), y < frame.maxY - 25 else { continue }
            for side in [Edge.left, Edge.right] {
                let rawX = side == .left ? frame.minX - 20 : frame.maxX + 20
                let x = min(bounds.maxX - 28, max(bounds.minX + 28, rawX))
                if !fromGround && abs(x - position.x) > 300 { continue }
                let handX = side == .left ? frame.minX + 7 : frame.maxX - 7
                let hand = CGPoint(x: handX, y: y + 17)
                guard isExposed(hand, on: surface, surfaces: surfaces) else { continue }
                let score = abs(x - position.x) + (y - position.y) * 0.65 + CGFloat(index) * 35
                routes.append(Route(surface: surface, edge: side, point: CGPoint(x: x, y: y), score: score))
            }
        }
        return routes.min { $0.score < $1.score }
    }

    private func isExposed(_ point: CGPoint, on surface: Surface, surfaces: [Surface]) -> Bool {
        for other in surfaces {
            if other.id == surface.id { return true }
            if other.frame.contains(point) { return false }
        }
        return false
    }
}

public enum Coordinates {
    public static func localWindowFrame(_ quartz: CGRect, primaryHeight: CGFloat, screenFrame: CGRect) -> CGRect {
        CGRect(x: quartz.minX - screenFrame.minX,
               y: primaryHeight - quartz.maxY - screenFrame.minY,
               width: quartz.width, height: quartz.height)
    }
}
