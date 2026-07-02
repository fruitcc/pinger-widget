import AppKit
import SwiftUI
import Combine

/// Borderless panel that can take keyboard focus without activating the app.
private final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = PingMonitor()
    private var statusItem: NSStatusItem!
    private var statusPanel: StatusPanel!   // left click: ping results
    private var settingsWindow: NSWindow?   // opened from the right-click menu
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

        statusPanel = makeStatusPanel()

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

    // MARK: - Click routing

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            closeStatusPanel()
            showMenu()
        } else if statusPanel.isVisible {
            closeStatusPanel()
        } else {
            openStatusPanel()
        }
    }

    // MARK: - Right click: destination menu

    private func showMenu() {
        let menu = NSMenu()
        let header = NSMenuItem(title: "Ping Destination", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for host in monitor.settings.hosts {
            let item = NSMenuItem(title: host, action: #selector(selectHost(_:)), keyEquivalent: "")
            item.target = self
            item.state = host == monitor.settings.host ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettingsWindow), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Pinger", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Assigning statusItem.menu makes the next click show the menu instead
        // of firing the action; clear it afterwards so left-clicks keep working.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func selectHost(_ sender: NSMenuItem) {
        var s = monitor.settings
        s.host = sender.title
        monitor.settings = s.sanitized()
    }

    // MARK: - Settings window

    @objc private func openSettingsWindow() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsWindowView(monitor: monitor))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Pinger Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.center()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Left click: results panel

    private func makeStatusPanel() -> StatusPanel {
        let hosting = NSHostingController(
            rootView: StatusPanelView(monitor: monitor)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
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

        // Content height changes (events fill in): keep the panel's top edge
        // pinned under the menu bar instead of growing upward.
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

    private func openStatusPanel() {
        statusPanel.layoutIfNeeded()
        pinBelowStatusItem(statusPanel)
        statusPanel.makeKeyAndOrderFront(nil)

        // Dismiss when the user clicks anywhere outside (global monitors only
        // see events of other apps, so clicks on our own panel don't fire).
        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                Task { @MainActor in self?.closeStatusPanel() }
            }
        }
    }

    private func closeStatusPanel() {
        statusPanel.orderOut(nil)
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
        if let lat = monitor.smoothedLatencyMs {
            parts.append(String(format: "~%.0f ms", lat))
        }
        parts.append(String(format: "~%.0f%% loss", monitor.smoothedLossPercent))
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
