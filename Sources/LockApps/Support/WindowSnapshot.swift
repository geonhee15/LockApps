import AppKit

/// Renders one of our own windows offscreen into a PNG (`cacheDisplay`), for the LOCKAPPS_SNAPSHOT* debug flags
/// that produce the README screenshots. No screen-recording permission needed; pair with `RenderMode.flat`
/// because backdrop blur and Liquid Glass are composited by the window server and do not render offscreen.
enum WindowSnapshot {
    @MainActor
    static func write(window: NSWindow, to path: String) {
        guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            NSLog("LockApps: snapshot failed (no content view)")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            NSLog("LockApps: snapshot written to \(path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
        } catch {
            NSLog("LockApps: snapshot failed: \(error)")
        }
    }
}
