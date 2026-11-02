// Generates AppIcon.icns: indigo glass gradient rounded square with a white "lock.fill" SF Symbol.
// Usage: swift Scripts/make-icon.swift <output.icns>
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"

func render(px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high

    let s = CGFloat(px)
    let inset = s * 0.09
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.225
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Base gradient: sky blue → deep indigo.
    NSGradient(colors: [
        NSColor(calibratedRed: 0.36, green: 0.62, blue: 1.00, alpha: 1),
        NSColor(calibratedRed: 0.22, green: 0.30, blue: 0.86, alpha: 1),
        NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.40, alpha: 1),
    ], atLocations: [0, 0.55, 1], colorSpace: .deviceRGB)!.draw(in: path, angle: -70)

    // Glass highlight across the top half.
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    let shine = NSBezierPath(ovalIn: NSRect(x: rect.minX - rect.width * 0.2, y: rect.midY - rect.height * 0.05,
                                            width: rect.width * 1.4, height: rect.height * 0.9))
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0.0)])!
        .draw(in: shine, relativeCenterPosition: NSPoint(x: 0, y: 0.6))
    NSGraphicsContext.restoreGraphicsState()

    // Hairline rim.
    NSColor.white.withAlphaComponent(0.35).setStroke()
    let rim = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.006, dy: s * 0.006), xRadius: radius, yRadius: radius)
    rim.lineWidth = max(1, s * 0.008)
    rim.stroke()

    let config = NSImage.SymbolConfiguration(pointSize: rect.width * 0.46, weight: .semibold)
    if let symbol = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let tinted = NSImage(size: symbol.size, flipped: false) { r in
            symbol.draw(in: r)
            NSColor.white.set()
            r.fill(using: .sourceAtop)
            return true
        }
        let h = rect.width * 0.54
        let symSize = NSSize(width: h * (symbol.size.width / symbol.size.height), height: h)
        let origin = NSPoint(x: rect.midX - symSize.width / 2, y: rect.midY - symSize.height / 2 - rect.height * 0.01)
        // Soft shadow under the glyph.
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = s * 0.03
        shadow.shadowOffset = NSSize(width: 0, height: -s * 0.015)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        tinted.draw(in: NSRect(origin: origin, size: symSize))
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("LockApps-AppIcon.iconset")
try? FileManager.default.removeItem(at: tmp)
try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(px: base).write(to: tmp.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(px: base * 2).write(to: tmp.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", tmp.path, "-o", output]
try! task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: tmp)
print(task.terminationStatus == 0 ? "wrote \(output)" : "iconutil failed")
exit(task.terminationStatus)
