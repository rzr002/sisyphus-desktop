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
guard let instance = SingleInstance.claimGame() else { exit(0) }
let delegate = AppDelegate()
app.delegate = delegate
withExtendedLifetime((delegate, instance)) { app.run() }
