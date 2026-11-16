import AppKit
import ClimbCore

#if DEBUG
if CommandLine.arguments.contains("--verify-spider-poses") {
    let checks = NativeChecks.spiderPoses()
    for name in checks.keys.sorted() { print("\(checks[name] == true ? "PASS" : "FAIL")  \(name)") }
    exit(checks.values.allSatisfy { $0 } ? 0 : 1)
}
#endif
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
