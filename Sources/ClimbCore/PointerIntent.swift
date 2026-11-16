import Foundation

public struct PointerResponse {
    public let freeze: Bool
    public let disturb: Bool
}

public struct PointerIntent {
    private var entered: Double?
    private var protectedUntil: Double = 0
    public init() {}
    public mutating func update(inside: Bool, now: Double, interacting: Bool = false) -> PointerResponse {
        if interacting { protect(after: now); return PointerResponse(freeze: true, disturb: false) }
        if inside {
            if entered == nil { entered = now }
            return PointerResponse(freeze: true, disturb: false)
        }
        let duration = entered.map { now - $0 }
        entered = nil
        return PointerResponse(freeze: false, disturb: now >= protectedUntil && duration.map { $0 < 0.4 } == true)
    }
    public mutating func protect(after now: Double) { entered = nil; protectedUntil = now + 0.8 }
}
