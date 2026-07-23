// Extracts the menu-bar strip from the existing hero composite, recolors the
// green dot/ring to red, saves the strip crop, and prints geometry.
// Usage: swift extract-strip.swift <hero.png> <strip-out.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let img = NSImage(contentsOfFile: args[1]),
      let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
    print("usage: extract-strip.swift hero.png strip-out.png"); exit(1)
}
let W = rep.pixelsWide, H = rep.pixelsHigh
print("canvas: \(W)x\(H)")

// Strip is drawn at x=560, width 1900, top margin 60 (see make-menubar-screenshot.swift).
let stripX = 560, stripW = 1900
// Detect strip vertical extent: scan a column inside the strip (x=2300) from
// the top; strip rows are much brighter than the dark background.
func brightness(_ x: Int, _ y: Int) -> CGFloat {
    guard let c = rep.colorAt(x: x, y: y) else { return 0 }
    return (c.redComponent + c.greenComponent + c.blueComponent) / 3
}
var yTop = -1, yBottom = -1
for y in 0..<400 {
    let b = brightness(2300, y)
    if b > 0.5 && yTop < 0 { yTop = y }
    if yTop >= 0 && b < 0.4 && yBottom < 0 { yBottom = y; break }
}
guard yTop >= 0, yBottom > yTop else { print("strip not found"); exit(1) }
let stripH = yBottom - yTop
print("strip rows: \(yTop)..\(yBottom) height \(stripH)")

// Find the dot: greenest pixel cluster within the strip.
var sumX = 0.0, sumY = 0.0, n = 0.0
for y in yTop..<yBottom {
    for x in stripX..<(stripX + stripW) {
        guard let c = rep.colorAt(x: x, y: y) else { continue }
        if c.greenComponent > 0.55 && c.greenComponent > c.redComponent * 1.6 && c.greenComponent > c.blueComponent * 1.6 {
            sumX += Double(x); sumY += Double(y); n += 1
        }
    }
}
guard n > 50 else { print("dot not found (n=\(n))"); exit(1) }
let dotX = Int(sumX / n), dotY = Int(sumY / n)
print("dot center in canvas px: \(dotX),\(dotY)  -> in crop px: \(dotX - stripX)")

// Crop the strip and recolor green-hued pixels to red (dot + baked ring +
// the first dots of the connector). Only the dot/ring are green in the strip.
let crop = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: stripW, pixelsHigh: stripH,
                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
for y in 0..<stripH {
    for x in 0..<stripW {
        guard let c = rep.colorAt(x: x + stripX, y: y + yTop) else { continue }
        var out = c
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        c.usingColorSpace(.deviceRGB)?.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        // Green hues (~0.25-0.45) with real saturation -> shift to red.
        if s > 0.25, v > 0.2, h > 0.2, h < 0.48 {
            out = NSColor(calibratedHue: 0.995, saturation: min(1, s * 1.05), brightness: v, alpha: a)
        }
        crop.setColor(out, atX: x, y: y)
    }
}
try! crop.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2])")
