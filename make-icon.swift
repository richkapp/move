// Renders Move's app icon (AppIcon.iconset) from code. Run: swift make-icon.swift <outdir>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)

    // macOS icon grid: 824/1024 body, centered, with a soft shadow.
    let inset = s * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = s * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.set()
    NSColor.black.setFill(); path.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Calm green to teal gradient.
    NSGradient(colors: [NSColor(srgbRed: 0.33, green: 0.86, blue: 0.60, alpha: 1),
                        NSColor(srgbRed: 0.05, green: 0.55, blue: 0.58, alpha: 1)])!
        .draw(in: path, angle: -60)

    // Thin progress ring, about three quarters full.
    let c = NSPoint(x: s / 2, y: s / 2), r = body.width * 0.36
    let track = NSBezierPath(); track.appendArc(withCenter: c, radius: r, startAngle: 0, endAngle: 360)
    track.lineWidth = s * 0.028
    NSColor.white.withAlphaComponent(0.22).setStroke(); track.stroke()
    let arc = NSBezierPath()
    arc.appendArc(withCenter: c, radius: r, startAngle: 90, endAngle: -180, clockwise: true)
    arc.lineWidth = s * 0.028; arc.lineCapStyle = .round
    NSColor.white.setStroke(); arc.stroke()

    // Walking figure.
    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.36, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let fig = NSImage(systemSymbolName: "figure.walk", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let sz = fig.size
        fig.draw(in: NSRect(x: c.x - sz.width / 2, y: c.y - sz.height / 2, width: sz.width, height: sz.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
print("icon rendered")
