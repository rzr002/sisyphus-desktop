import Foundation
import ClimbCore

func checkDesktopCaptureAccess() {
    func withDefaults(_ test: (UserDefaults) throws -> Void) throws {
        let suite = "sisyphus.tests.capture." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try test(defaults)
    }
    check("A missing screen grant stays quiet on startup, on resume and across launches") {
        try withDefaults { store in
            for _ in 0..<4 {
                let access = DesktopCaptureAccess(defaults: store)
                var checks = 0
                for _ in 0..<120 {
                    access.suspend()
                    try expect(access.resume { checks += 1; return false } == .none, "No automatic permission request or capture")
                }
                try expect(checks == 1 && access.state == .needsPermission, "A negative preflight must park the app")
            }
        }
    }
    check("One deliberate request is remembered after denial; settings can enable capture") {
        try withDefaults { store in
            let first = DesktopCaptureAccess(defaults: store)
            try expect(first.enable { false } == .requestPermission, "The first menu click may ask")
            try expect(first.receivedPermission(false) == .none, "Dismissal must not also open settings or retry")
            let again = DesktopCaptureAccess(defaults: store)
            try expect(again.enable { false } == .openSettings, "Subsequent clicks go straight to settings")
            again.awaitSettings()
            try expect(again.receivedPermission(true) == .start, "A new actual grant starts one stream")
            try expect(again.receivedPermission(true) == .none, "Returning again cannot start a duplicate stream")
        }
    }
    check("Stale positive preflight and quit during startup cannot re-prompt on relaunch") {
        try withDefaults { store in
            let first = DesktopCaptureAccess(defaults: store)
            try expect(first.resume { true } == .start, "A pre-existing grant can connect automatically")
            for attempt in 0..<4 {
                if attempt == 1 { first.failed() }
                first.suspend()
                let reopened = DesktopCaptureAccess(defaults: store)
                try expect(reopened.resume { true } == .none && reopened.state == .needsReconnect, "A failed or interrupted connection requires a deliberate retry")
            }
            let recovered = DesktopCaptureAccess(defaults: store)
            recovered.awaitSettings()
            let restartedBySystem = DesktopCaptureAccess(defaults: store)
            try expect(restartedBySystem.resume { true } == .start, "System Settings may relaunch after an explicit grant")
            restartedBySystem.receivedFrame()
            restartedBySystem.suspend()
            try expect(restartedBySystem.resume { true } == .start, "A successful stream may resume after a drag or pause")
            restartedBySystem.receivedFrame()
            try expect(DesktopCaptureAccess(defaults: store).resume { true } == .start, "A healthy grant survives ordinary relaunches")
        }
    }
    check("Stopping capture from Control Center stays stopped through wake and menu activity") {
        try withDefaults { store in
            let access = DesktopCaptureAccess(defaults: store)
            _ = access.resume { true }; access.receivedFrame(); access.failed()
            for _ in 0..<5 { access.suspend(); try expect(access.resume { true } == .none, "No automatic restart after an explicit system stop") }
            try expect(access.enable { true } == .start && access.enable { true } == .none, "An explicit reconnect starts just once")
        }
    }
}
