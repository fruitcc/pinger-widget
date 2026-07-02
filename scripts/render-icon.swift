// Renders the Pinger app icon: dark rounded square with a glowing green dot.
// Usage: swift scripts/render-icon.swift <output-dir>
import AppKit

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-build"
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

func renderMaster(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    // macOS HIG grid: the rounded square fills ~82% of the canvas.
    let inset = s * 0.09
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = rect.width * 0.225
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Background: deep navy-to-charcoal vertical gradient.
    let bgGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.22, alpha: 1),
        NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 1),
    ])!
    bgGradient.draw(in: squircle, angle: -90)

    // Faint menu-bar strip near the top for context.
    NSGraphicsContext.current?.saveGraphicsState()
    squircle.addClip()
    let barHeight = rect.height * 0.12
    let bar = NSRect(x: rect.minX, y: rect.maxY - barHeight, width: rect.width, height: barHeight)
    NSColor(calibratedWhite: 1, alpha: 0.08).setFill()
    bar.fill()
    NSColor(calibratedWhite: 1, alpha: 0.12).setFill()
    NSBezierPath(rect: NSRect(x: rect.minX, y: rect.maxY - barHeight - s * 0.002, width: rect.width, height: s * 0.002)).fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // Glowing green dot, centered in the area below the strip.
    let dotCenter = NSPoint(x: rect.midX, y: rect.midY - barHeight * 0.4)
    let dotRadius = rect.width * 0.17

    // Outer glow: layered translucent circles.
    for (multiplier, alpha) in [(2.6, 0.05), (2.1, 0.09), (1.7, 0.14), (1.35, 0.22)] {
        let r = dotRadius * CGFloat(multiplier)
        NSColor(calibratedRed: 0.22, green: 0.86, blue: 0.35, alpha: CGFloat(alpha)).setFill()
        NSBezierPath(ovalIn: NSRect(x: dotCenter.x - r, y: dotCenter.y - r, width: 2 * r, height: 2 * r)).fill()
    }

    // Dot body with a radial-style highlight.
    let dotRect = NSRect(x: dotCenter.x - dotRadius, y: dotCenter.y - dotRadius, width: 2 * dotRadius, height: 2 * dotRadius)
    let dotGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.55, green: 0.98, blue: 0.6, alpha: 1),
        NSColor(calibratedRed: 0.13, green: 0.78, blue: 0.3, alpha: 1),
    ])!
    let dotPath = NSBezierPath(ovalIn: dotRect)
    dotGradient.draw(in: dotPath, relativeCenterPosition: NSPoint(x: -0.2, y: 0.35))

    // Small specular highlight.
    let hlRadius = dotRadius * 0.32
    let hlCenter = NSPoint(x: dotCenter.x - dotRadius * 0.3, y: dotCenter.y + dotRadius * 0.38)
    NSColor(calibratedWhite: 1, alpha: 0.55).setFill()
    NSBezierPath(ovalIn: NSRect(x: hlCenter.x - hlRadius, y: hlCenter.y - hlRadius, width: 2 * hlRadius, height: 2 * hlRadius)).fill()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to path: String, pixels: Int) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
               from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let master = renderMaster(size: 1024)
let iconset = "\(outputDir)/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    writePNG(master, to: "\(iconset)/icon_\(size)x\(size).png", pixels: size)
    writePNG(master, to: "\(iconset)/icon_\(size)x\(size)@2x.png", pixels: size * 2)
}
print("wrote \(iconset)")
