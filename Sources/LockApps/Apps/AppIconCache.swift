import AppKit

@MainActor
enum AppIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(path: String, size: CGFloat = 32) -> NSImage {
        let key = "\(path)@\(Int(size))"
        if let cached = cache[key] { return cached }
        let base: NSImage
        if FileManager.default.fileExists(atPath: path) {
            base = NSWorkspace.shared.icon(forFile: path)
        } else {
            base = NSWorkspace.shared.icon(for: .applicationBundle)
        }
        let result = (base.copy() as? NSImage) ?? base
        result.size = NSSize(width: size, height: size)
        if cache.count >= 600 { cache.removeAll(keepingCapacity: true) }
        cache[key] = result
        return result
    }
}
