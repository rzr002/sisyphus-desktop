import AppKit
import CoreGraphics
import ClimbCore

final class WindowTracker {
    var testWindowIDs: Set<UInt32> = []

    /// WindowServer metadata only: never request pixels, window titles, or AX access.
    func surfaces(on screen: NSScreen) -> [Surface] {
        guard let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return rows.compactMap { row in
            guard let id = row[kCGWindowNumber as String] as? UInt32,
                  let pid = row[kCGWindowOwnerPID as String] as? Int32,
                  let layer = row[kCGWindowLayer as String] as? Int,
                  (NSWindow.Level.normal.rawValue...NSWindow.Level.floating.rawValue).contains(layer),
                  let dictionary = row[kCGWindowBounds as String] as? [String: Any],
                  let quartz = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                  (row[kCGWindowAlpha as String] as? Double ?? 1) > 0.1 else { return nil }
            if pid == ownPID && !testWindowIDs.contains(id) { return nil }
            let frame = Coordinates.localWindowFrame(quartz, primaryHeight: primaryHeight, screenFrame: screen.frame)
            guard frame.width >= 120, frame.height >= 90,
                  frame.intersects(CGRect(origin: .zero, size: screen.frame.size)) else { return nil }
            let name = testWindowIDs.contains(id) ? "Test fixture" : NSRunningApplication(processIdentifier: pid)?.localizedName ?? "窗口"
            return Surface(id: id, name: name, frame: frame)
        }
    }
}
