// Renders the app's real StatusPanelView with staged outage data and captures
// it to a PNG (used for the red App Store hero screenshot). This file supplies
// main() and a stand-in PingMonitor with the same read surface as the real one.
// Build: swiftc -o render-red-panel scripts/render-red-panel.swift \
//        Sources/Pinger/{PanelViews,StatusAppearance,Settings,Diagnostics,Pinger}.swift
// Usage: ./render-red-panel <output.png>
import AppKit
import SwiftUI

enum ConnectionStatus {
    case unknown, good, degraded, down
}

struct Outage: Codable, Equatable, Identifiable {
    let start: Date
    var end: Date?
    var id: Date { start }
    var duration: TimeInterval? { end.map { $0.timeIntervalSince(start) } }
}

@MainActor
final class PingMonitor: ObservableObject {
    static let historySize = 10
    @Published var events: [PingEvent] = []
    @Published var status: ConnectionStatus = .down
    @Published var outages: [Outage] = []
    @Published var diagnosis: Diagnosis?
    @Published var settings = Settings.default
    var latencySummary: String? = "~96 ±3 ms"

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }
    var smoothedLossPercent: Double = 88
}

func time(_ h: Int, _ m: Int, _ s: Int) -> Date {
    var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    c.hour = h; c.minute = m; c.second = s
    return Calendar.current.date(from: c)!
}

@main
enum RenderRedPanel {
    static func main() {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "red-panel.png"
        MainActor.assumeIsolated {
            run(out: out)
            NSApplication.shared.run()
        }
    }

    @MainActor
    static func run(out: String) {
    let app = NSApplication.shared
    _ = app
    app.setActivationPolicy(.accessory)
    app.appearance = NSAppearance(named: .aqua)  // match the light-mode hero shot

    let monitor = PingMonitor()
    monitor.events = [
        PingEvent(date: time(13, 7, 13), outcome: .timeout),
        PingEvent(date: time(13, 7, 11), outcome: .timeout),
        PingEvent(date: time(13, 7, 9), outcome: .timeout),
        PingEvent(date: time(13, 7, 7), outcome: .timeout),
        PingEvent(date: time(13, 7, 5), outcome: .timeout),
        PingEvent(date: time(13, 7, 3), outcome: .timeout),
        PingEvent(date: time(13, 7, 1), outcome: .success(latencyMs: 97.2)),
        PingEvent(date: time(13, 6, 59), outcome: .success(latencyMs: 95.8)),
        PingEvent(date: time(13, 6, 57), outcome: .success(latencyMs: 98.3)),
        PingEvent(date: time(13, 6, 55), outcome: .success(latencyMs: 96.4)),
    ]
    monitor.outages = [
        Outage(start: time(13, 7, 3), end: nil),
        Outage(start: time(9, 14, 2), end: time(9, 17, 14)),
    ]
    monitor.diagnosis = Diagnosis(
        date: Date(),
        gatewayIP: "192.168.1.1",
        gatewayOutcome: .success(latencyMs: 2.4),
        referenceHost: "1.1.1.1",
        referenceOutcome: .timeout,
        verdict: "Router is fine but the internet isn't reachable — looks like an ISP or upstream problem."
    )

    let hosting = NSHostingController(
        rootView: StatusPanelView(monitor: monitor)
            .background(Color(white: 0.93), in: RoundedRectangle(cornerRadius: 12))
    )
    hosting.sizingOptions = [.preferredContentSize]

    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
    panel.contentViewController = hosting
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .statusBar
    panel.setContentSize(hosting.view.fittingSize)
    panel.layoutIfNeeded()
    panel.setFrameOrigin(NSPoint(x: 200, y: 300))
    panel.orderFrontRegardless()

    // Give SwiftUI + the material a beat to render, then capture our own window.
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
        let v = hosting.view
        var image: CGImage?
        if let bmp = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
            v.cacheDisplay(in: v.bounds, to: bmp)
            image = bmp.cgImage
        }
        guard let cg = image else { fputs("capture failed\n", stderr); exit(2) }
        let rep = NSBitmapImageRep(cgImage: cg)
        // Point size = pixels/2 so the composite scales it like a retina capture.
        rep.size = NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
        print("wrote \(out) (\(cg.width)x\(cg.height) px)")
        exit(0)
    }
    }
}
