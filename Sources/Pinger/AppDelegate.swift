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
    // SwiftUI content exists only while its window is visible. A hidden
    // NSHostingView still re-renders on every ping, and on macOS 26 each of
    // those renders permanently leaks observation-tracking state — after days
    // of uptime the accumulated state made every render take seconds and
    // pegged the main thread at 100% CPU. So the hosting view is attached on
    // open and torn down on close. The panel shell is reused (an orderOut'd
    // window stays retained by AppKit anyway); the settings window is closed
    // for real, which lets the whole window deallocate.
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
        // updateTooltip reads the monitor's other properties, and @Published
        // fires on willSet — hop to the next main-loop turn so the read
        // happens after record() has finished updating all metrics.
        monitor.$events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateTooltip() }
            .store(in: &cancellables)

        monitor.start()

        // First launch: open the results panel once so a brand-new user (and
        // App Review) can see what the app does without hunting for the dot.
        let firstLaunchKey = "didShowFirstLaunchPanel"
        if !UserDefaults.standard.bool(forKey: firstLaunchKey) {
            UserDefaults.standard.set(true, forKey: firstLaunchKey)
            openStatusPanel()
        }
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
            let window = NSWindow(contentViewController: makeSettingsHosting())
            window.title = "Pinger Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self  // windowWillClose releases window + content
            settingsWindow = window
        }
        settingsWindow?.center()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsHosting() -> NSViewController {
        NSHostingController(rootView: SettingsWindowView(monitor: monitor) { [weak self] in
            self?.settingsWindow?.performClose(nil)
        })
    }

    // MARK: - Left click: results panel

    private func makeStatusPanel() -> StatusPanel {
        let panel = StatusPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
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
        let hosting = NSHostingController(
            rootView: StatusPanelView(monitor: monitor)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        )
        hosting.sizingOptions = [.preferredContentSize]
        statusPanel.contentViewController = hosting

        // preferredContentSize can be delivered a runloop turn later; size the
        // panel synchronously so it isn't shown undersized and repositioned.
        statusPanel.setContentSize(hosting.view.fittingSize)
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
        statusPanel.contentViewController = nil  // release the SwiftUI hosting view
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
        if let latency = monitor.latencySummary {
            parts.append(latency)
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

extension AppDelegate: NSWindowDelegate {
    /// Only the settings window has a close button; the borderless status
    /// panel never gets here. Closing discards unapplied edits (standard
    /// dialog semantics): the reference is dropped immediately, so a reopen
    /// always builds a fresh window, and the closed window's SwiftUI content
    /// is detached explicitly — not left to window dealloc, which anything
    /// holding the window would defeat — so it can't keep re-rendering
    /// hidden. The detach is deferred one turn because performClose can be
    /// initiated by the view's own "Apply & Close" button, and the hosting
    /// view must not be released while that action is still on the stack.
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == settingsWindow else { return }
        settingsWindow = nil
        DispatchQueue.main.async {
            window.contentViewController = nil
        }
    }
}
