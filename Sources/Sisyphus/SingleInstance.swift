import AppKit
import Darwin

/// Keep the descriptor open for the lifetime of the game. The kernel releases
/// the lock on quit or crash; a file left by a prior run is harmless.
final class SingleInstance {
    private let fd: Int32
    init?(lockURL: URL, precedingCopy: Bool = false) {
        guard !precedingCopy else { return nil }
        let opened = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard opened >= 0 else { return nil }
        guard flock(opened, LOCK_EX | LOCK_NB) == 0 else { close(opened); return nil }
        fd = opened
    }
    deinit { close(fd) }

    static func claimGame() -> SingleInstance? {
        let me = NSRunningApplication.current
        // Builds before 0.4 have no lock. Respect an already running installed copy.
        let olderCopy = NSRunningApplication.runningApplications(withBundleIdentifier: "studio.leosnow.sisyphus").contains {
            guard $0.processIdentifier != me.processIdentifier, !$0.isTerminated,
                  let other = $0.launchDate, let mine = me.launchDate else { return false }
            return other < mine || (other == mine && $0.processIdentifier < me.processIdentifier)
        }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("studio.leosnow.sisyphus.instance.lock")
        return SingleInstance(lockURL: path, precedingCopy: olderCopy)
    }
}
