import AppKit
import ClimbCore

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
#if DEBUG
if CommandLine.arguments.contains("--diagnose-desktop") {
    app.finishLaunching()
    NativeChecks.diagnoseDesktop()
}
if CommandLine.arguments.contains("--verify-native") {
    app.finishLaunching()
    NativeChecks.run()
}
#endif
let delegate = AppDelegate()
app.delegate = delegate
withExtendedLifetime(delegate) { app.run() }
