// Composites the "lives in your menu bar" App Store hero screenshot:
// a real menu bar strip with the dot highlighted, and the results panel
// hanging beneath it like the opened popover.
// Usage: swift scripts/make-menubar-screenshot.swift <strip.png> <dotCenterXInStripPx> <panel.png> <output.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 5, let dotXInStrip = Double(args[2]) else {
    print("usage: make-menubar-screenshot.swift strip.png dotCenterXpx panel.png out.png"); exit(1)
}
guard let strip = NSImage(contentsOfFile: args[1]), let panel = NSImage(contentsOfFile: args[3]) else {
    fatalError("missing input images")
}
let outPath = args[4]

let canvas = NSSize(width: 2560, height: 1600)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width), pixelsHigh: Int(canvas.height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background gradient + soft green accent (matches the other screenshots).
NSGradient(colors: [
    NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.27, alpha: 1),
    NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.10, alpha: 1),
])!.draw(in: NSRect(origin: .zero, size: canvas), angle: -75)
for (r, a) in [(900.0, 0.05), (600.0, 0.06), (350.0, 0.07)] {
    NSColor(calibratedRed: 0.22, green: 0.86, blue: 0.35, alpha: a).setFill()
    NSBezierPath(ovalIn: NSRect(x: 250 - r/2, y: 1100 - r/2, width: r, height: r)).fill()
}

let green = NSColor(calibratedRed: 0.25, green: 0.85, blue: 0.37, alpha: 1)

// Menu bar strip along the top.
let stripScale: CGFloat = 1900 / strip.size.width
let stripW: CGFloat = 1900
let stripH = strip.size.height * stripScale
let stripX: CGFloat = 560
let stripY = canvas.height - 60 - stripH
let stripRect = NSRect(x: stripX, y: stripY, width: stripW, height: stripH)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
shadow.shadowBlurRadius = 40
shadow.shadowOffset = NSSize(width: 0, height: -14)
NSGraphicsContext.current?.saveGraphicsState()
shadow.set()
NSBezierPath(roundedRect: stripRect, xRadius: 18, yRadius: 18).setClip()
strip.draw(in: stripRect, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.current?.restoreGraphicsState()

// Highlight ring around the dot in the strip.
// dotXInStrip is in strip PIXELS; strip.size is in points (2x image → /2).
let dotCanvasX = stripX + dotXInStrip / 2 * stripScale
let dotCanvasY = stripY + stripH / 2
let ringR: CGFloat = 46
let ring = NSBezierPath(ovalIn: NSRect(x: dotCanvasX - ringR, y: dotCanvasY - ringR, width: 2 * ringR, height: 2 * ringR))
ring.lineWidth = 6
green.setStroke()
ring.stroke()

// Panel hanging under the dot, connected like the real popover.
let panelScale: CGFloat = 2.8
let panelW = panel.size.width * panelScale
let panelH = panel.size.height * panelScale
let panelX = dotCanvasX - panelW / 2
let panelTop = stripY - 160
let panelRect = NSRect(x: panelX, y: panelTop - panelH, width: panelW, height: panelH)

// Connector from the ring to the panel.
let line = NSBezierPath()
line.move(to: NSPoint(x: dotCanvasX, y: dotCanvasY - ringR))
line.line(to: NSPoint(x: dotCanvasX, y: panelTop))
line.lineWidth = 5
line.setLineDash([2, 10], count: 2, phase: 0)
line.lineCapStyle = .round
green.withAlphaComponent(0.85).setStroke()
line.stroke()

NSGraphicsContext.current?.saveGraphicsState()
shadow.set()
panel.draw(in: panelRect, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.current?.restoreGraphicsState()

// Title + subtitle, left column.
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 76, weight: .bold),
    .foregroundColor: NSColor.white,
]
let subAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 38, weight: .regular),
    .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.75),
]
var y: CGFloat = 1060
for line in ["Lives in your", "menu bar"] {
    (line as NSString).draw(at: NSPoint(x: 130, y: y), withAttributes: titleAttrs)
    y -= 96
}
y -= 40
let bullets: [(NSColor, String)] = [
    (green, "Green — connected"),
    (NSColor(calibratedRed: 0.95, green: 0.8, blue: 0.2, alpha: 1), "Yellow — degraded"),
    (NSColor(calibratedRed: 0.92, green: 0.3, blue: 0.25, alpha: 1), "Red — down"),
]
for (color, text) in bullets {
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: 134, y: y + 12, width: 30, height: 30)).fill()
    (text as NSString).draw(at: NSPoint(x: 186, y: y), withAttributes: subAttrs)
    y -= 68
}
y -= 24
("Click the dot for live details." as NSString).draw(at: NSPoint(x: 130, y: y), withAttributes: subAttrs)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
