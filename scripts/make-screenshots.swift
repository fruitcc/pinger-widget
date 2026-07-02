// Composites window captures onto 2560x1600 App Store screenshot canvases.
// Usage: swift scripts/make-screenshots.swift <panel.png> <settings.png> <output-dir>
import AppKit

let args = CommandLine.arguments
guard args.count == 4 else { print("usage: make-screenshots.swift panel.png settings.png outdir"); exit(1) }
let panelPath = args[1], settingsPath = args[2], outDir = args[3]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let canvas = NSSize(width: 2560, height: 1600)

func compose(shot shotPath: String, title: String, subtitle: String, output: String) {
    guard let shot = NSImage(contentsOfFile: shotPath) else { fatalError("missing \(shotPath)") }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width), pixelsHigh: Int(canvas.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Background gradient (same family as the app icon).
    NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.27, alpha: 1),
        NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.10, alpha: 1),
    ])!.draw(in: NSRect(origin: .zero, size: canvas), angle: -75)

    // Soft green accent glow top-left.
    for (r, a) in [(900.0, 0.05), (600.0, 0.06), (350.0, 0.07)] {
        NSColor(calibratedRed: 0.22, green: 0.86, blue: 0.35, alpha: a).setFill()
        NSBezierPath(ovalIn: NSRect(x: 300 - r/2, y: 1250 - r/2, width: r, height: r)).fill()
    }

    // Title / subtitle on the left.
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 96, weight: .bold),
        .foregroundColor: NSColor.white,
    ]
    let subAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 44, weight: .regular),
        .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.72),
    ]
    let textX: CGFloat = 170
    var y: CGFloat = 1180
    for line in title.components(separatedBy: "\n") {
        (line as NSString).draw(at: NSPoint(x: textX, y: y), withAttributes: titleAttrs)
        y -= 118
    }
    y -= 20
    for line in subtitle.components(separatedBy: "\n") {
        (line as NSString).draw(at: NSPoint(x: textX, y: y), withAttributes: subAttrs)
        y -= 62
    }

    // Green dot chip next to the title for brand continuity.
    NSColor(calibratedRed: 0.25, green: 0.85, blue: 0.37, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: textX + 6, y: 1350, width: 56, height: 56)).fill()

    // The window capture, right side, with a drop shadow, at 2x its point size.
    let scale: CGFloat = 2.4
    let w = shot.size.width * scale
    let h = shot.size.height * scale
    let x = canvas.width - w - 220
    let shotY = (canvas.height - h) / 2
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
    shadow.shadowBlurRadius = 60
    shadow.shadowOffset = NSSize(width: 0, height: -20)
    NSGraphicsContext.current?.saveGraphicsState()
    shadow.set()
    shot.draw(in: NSRect(x: x, y: shotY, width: w, height: h),
              from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
    print("wrote \(output)")
}

compose(
    shot: panelPath,
    title: "Your internet,\nat a glance",
    subtitle: "A green, yellow, or red dot in your\nmenu bar — powered by live pings,\npacket loss, latency, and jitter.",
    output: "\(outDir)/screenshot-1.png"
)
compose(
    shot: settingsPath,
    title: "Tune it\nyour way",
    subtitle: "Destinations, thresholds, and\nSensitive / Balanced / Steady\ndetection profiles.",
    output: "\(outDir)/screenshot-2.png"
)
