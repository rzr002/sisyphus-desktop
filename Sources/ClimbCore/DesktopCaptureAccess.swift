import Foundation

/// Consent is owned by macOS. These preferences only remember when the game
/// must wait for a user action before attempting to connect again.
public final class DesktopCaptureAccess {
    public enum State { case idle, needsPermission, connecting, streaming, needsReconnect }
    public enum Action { case none, start, requestPermission, openSettings }
    private let defaults: UserDefaults
    private let retryKey = "desktopCapture.requiresManualRetry"
    private let requestKey = "desktopCapture.didRequestPermission"
    public private(set) var state: State
    public var hasRequestedPermission: Bool { defaults.bool(forKey: requestKey) }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = defaults.bool(forKey: retryKey) ? .needsReconnect : .idle
    }

    /// Startup and ordinary resumes may check an existing grant, never ask for one.
    public func resume(check: () -> Bool) -> Action {
        guard state == .idle else { return .none }
        guard check() else { state = .needsPermission; return .none }
        return begin()
    }

    /// Only the character's context menu may initiate a consent request.
    public func enable(check: () -> Bool) -> Action {
        guard state != .connecting && state != .streaming else { return .none }
        if check() { return begin() }
        state = .needsPermission
        if hasRequestedPermission { return .openSettings }
        defaults.set(true, forKey: requestKey)
        return .requestPermission
    }

    public func receivedPermission(_ allowed: Bool) -> Action {
        guard state == .needsPermission, allowed else { return .none }
        return begin()
    }

    public func awaitSettings() {
        guard state != .streaming && state != .connecting else { return }
        // macOS may quit and reopen the app straight from System Settings.
        // Permit one new check even if it previously interrupted a connection.
        defaults.removeObject(forKey: retryKey)
        state = .needsPermission
    }

    private func begin() -> Action {
        // Persist before calling ScreenCaptureKit. A relaunch while a system
        // dialog is outstanding must not create another consent loop.
        defaults.set(true, forKey: retryKey)
        state = .connecting
        return .start
    }

    public func receivedFrame() {
        guard state == .connecting else { return }
        defaults.removeObject(forKey: retryKey)
        state = .streaming
    }

    public func failed() {
        defaults.set(true, forKey: retryKey)
        state = .needsReconnect
    }

    public func suspend() {
        if state == .streaming { state = .idle }
        else if state == .connecting { state = .needsReconnect }
    }
}
