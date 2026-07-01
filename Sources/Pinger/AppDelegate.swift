import AppKit
import SwiftUI
import Combine

/// Borderless panel that can take keyboard focus (for the settings text fields)
/// without activating the app.
private final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = PingMonitor()
    private var statusItem: NSStatusItem!
    private var statusPanel: StatusPanel!   // left click: ping results
    private var settingsPanel: StatusPanel! // right click: settings + quit
    private var cancellables = Set<AnyCancellable>()
    private var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Pinger"
        }

        statusPanel = makePanel(rootView: StatusPanelView(monitor: monitor))
        settingsPanel = makePanel(rootView: SettingsPanelView(monitor: monitor))

        // @Published delivers synchronously on the main actor; the initial
        // value arrives on subscribe, so no manual first update is needed.
        monitor.$status
            .removeDuplicates()
            .sink { [weak self] status in self?.updateIcon(for: status) }
            .store(in: &cancellables)
        monitor.$events
            .sink { [weak self] _ in self?.updateTooltip() }
            .store(in: &cancellables)

        monitor.start()
    }

    // MARK: - Panels

    private func makePanel<Content: View>(rootView: Content) -> StatusPanel {
        let hosting = NSHostingController(
            rootView: rootView.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        )
        hosting.sizingOptions = [.preferredContentSize]

        let panel = StatusPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.contentViewController = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        // Content height changes (events fill in, fields resize): keep the
        // panel's top edge pinned under the menu bar instead of growing upward.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
        ) { [weak self, weak panel] _ in
            MainActor.assumeIsolated {
                guard let self, let panel, panel.isVisible else { return }
                self.pinBelowStatusItem(panel)
            }
        }
        return panel
    }

    @objc private func statusItemClicked() {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
        let target: StatusPanel = isRightClick ? settingsPanel : statusPanel
        let other: StatusPanel = isRightClick ? statusPanel : settingsPanel

        if target.isVisible {
            closePanels()
        } else {
            other.orderOut(nil)
            open(target)
        }
    }

    private func open(_ panel: StatusPanel) {
        panel.layoutIfNeeded()
        pinBelowStatusItem(panel)
        panel.makeKeyAndOrderFront(nil)

        // Dismiss when the user clicks anywhere outside (global monitors only
        // see events of other apps, so clicks on our own panels don't fire).
        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                Task { @MainActor in self?.closePanels() }
            }
        }
    }

    private func closePanels() {
        statusPanel.orderOut(nil)
        settingsPanel.orderOut(nil)
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }

    /// Places the panel so its top edge sits just below the menu bar,
    /// horizontally centered on the status item (clamped to the screen).
    private func pinBelowStatusItem(_ panel: StatusPanel) {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.frame // screen coordinates, y-up
        let size = panel.frame.size
        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? buttonFrame

        var x = buttonFrame.midX - size.width / 2
        x = min(x, visible.maxX - size.width - 8)
        x = max(x, visible.minX + 8)
        let top = buttonFrame.minY - 6 // just below the menu bar
        panel.setFrameOrigin(NSPoint(x: x, y: top - size.height))
    }

    // MARK: - Menu bar icon

    private static let dotImages: [ConnectionStatus: NSImage] = {
        var images: [ConnectionStatus: NSImage] = [:]
        for status in [ConnectionStatus.unknown, .good, .degraded, .down] {
            images[status] = dotImage(color: status.nsColor)
        }
        return images
    }()

    private func updateIcon(for status: ConnectionStatus) {
        statusItem.button?.image = Self.dotImages[status]
    }

    private func updateTooltip() {
        var parts = ["Pinger — \(monitor.status.title)"]
        if let avg = monitor.averageLatencyMs {
            parts.append(String(format: "avg %.0f ms", avg))
        }
        parts.append(String(format: "%.0f%% loss", monitor.lossPercent))
        statusItem.button?.toolTip = parts.joined(separator: ", ")
    }

    private static func dotImage(color: NSColor, diameter: CGFloat = 11) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let dotRect = NSRect(
                x: (rect.width - diameter) / 2,
                y: (rect.height - diameter) / 2,
                width: diameter,
                height: diameter
            )
            color.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            // Subtle rim so the yellow dot stays visible on light menu bars.
            NSColor.black.withAlphaComponent(0.2).setStroke()
            let rim = NSBezierPath(ovalIn: dotRect.insetBy(dx: 0.5, dy: 0.5))
            rim.lineWidth = 1
            rim.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }
}
