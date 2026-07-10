import SwiftUI
import ServiceManagement
import UserNotifications

// MARK: - Left click: ping results

struct StatusPanelView: View {
    @ObservedObject var monitor: PingMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if monitor.status == .down || monitor.status == .degraded {
                Divider()
                diagnosticsSection
            }
            Divider()
            eventList
            if monitor.settings.logOutages && !monitor.outages.isEmpty {
                Divider()
                outagesSection
            }
            Text("Right-click the dot to switch destination or open settings")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(width: 320)
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Diagnostics")
                .font(.system(size: 12, weight: .semibold))
            if let d = monitor.diagnosis {
                Text(d.verdict)
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
                if let gatewayIP = d.gatewayIP {
                    ProbeRow(label: "Router (\(gatewayIP))", outcome: d.gatewayOutcome)
                }
                ProbeRow(label: "Internet (\(d.referenceHost))", outcome: d.referenceOutcome)
            } else {
                Text("Running diagnostics…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var outagesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent outages")
                .font(.system(size: 12, weight: .semibold))
            ForEach(monitor.outages.prefix(5)) { outage in
                OutageRow(outage: outage)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(monitor.status.color)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(monitor.status.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(statsLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var statsLine: String {
        var parts: [String] = ["\(monitor.settings.host) every \(formatNumber(monitor.settings.intervalSeconds))s"]
        if let latency = monitor.latencySummary {
            parts.append(latency)
        }
        if !monitor.events.isEmpty {
            parts.append(String(format: "~%.0f%% loss", monitor.smoothedLossPercent))
        }
        return parts.joined(separator: " · ")
    }

    private var eventList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last \(PingMonitor.historySize) pings")
                .font(.system(size: 12, weight: .semibold))
            if monitor.events.isEmpty {
                Text("Waiting for first ping…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(monitor.events) { event in
                    EventRow(event: event, slowThresholdMs: monitor.settings.yellowLatencyMs)
                }
            }
        }
    }
}

private struct ProbeRow: View {
    let label: String
    let outcome: PingOutcome?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Text(result)
                .font(.system(size: 11, design: .monospaced))
        }
    }

    private var dotColor: Color {
        switch outcome {
        case .success: .green
        case .timeout, .error: .red
        case nil: .gray
        }
    }

    private var result: String {
        switch outcome {
        case .success(let ms): String(format: "%.1f ms", ms)
        case .timeout: "timed out"
        case .error(let message): message
        case nil: "—"
        }
    }
}

private struct OutageRow: View {
    let outage: Outage

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var label: String {
        let start = Self.timeFormatter.string(from: outage.start)
        if let duration = outage.duration {
            return "\(start) · down \(PingMonitor.formatDuration(duration))"
        }
        return "\(start) · ongoing"
    }
}

private struct EventRow: View {
    let event: PingEvent
    /// Successful pings slower than this get a yellow dot (latency spike).
    let slowThresholdMs: Double

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(Self.timeFormatter.string(from: event.date))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
    }

    private var dotColor: Color {
        switch event.outcome {
        case .success(let ms): ms > slowThresholdMs ? .yellow : .green
        case .timeout: .red
        case .error: .orange
        }
    }

    private var label: String {
        switch event.outcome {
        case .success(let ms): String(format: "%.1f ms", ms)
        case .timeout: "timed out"
        case .error(let message): message
        }
    }
}

// MARK: - Settings window

struct SettingsWindowView: View {
    @ObservedObject var monitor: PingMonitor
    /// Called after Apply commits, to close the hosting window.
    var onClose: () -> Void = {}

    @State private var newHost = ""
    @State private var launchAtLogin = false
    // Draft fields, committed by Apply.
    @State private var interval = ""
    @State private var timeout = ""
    @State private var yellowLatency = ""
    @State private var redLatency = ""
    @State private var yellowLoss = ""
    @State private var redLoss = ""
    @State private var yellowJitter = ""
    @State private var failuresToDown = ""
    @State private var successesToRecover = ""
    @State private var alpha = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            generalSection
            Divider()
            destinationsSection
            Divider()
            profileSection
            detectionSection
            HStack {
                Text(draftProfile.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                // No .defaultAction shortcut: Return must stay usable inside
                // the text fields (notably Add host) without closing the window.
                Button("Apply & Close", action: applyAndClose)
            }
        }
        .padding(16)
        .frame(width: 400)
        .onAppear(perform: loadDraft)
    }

    // MARK: General (applied immediately)

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("General")
                .font(.system(size: 12, weight: .semibold))
            Toggle("Launch at login", isOn: launchAtLoginBinding)
            Toggle("Log outages in the panel", isOn: settingBinding(\.logOutages))
            Toggle("Notify when the connection drops or recovers", isOn: notifyBinding)
        }
        .font(.system(size: 12))
        .toggleStyle(.checkbox)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    NSLog("launch-at-login change failed: \(error)")
                }
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        )
    }

    private func settingBinding(_ keyPath: WritableKeyPath<Settings, Bool>) -> Binding<Bool> {
        Binding(
            get: { monitor.settings[keyPath: keyPath] },
            set: { value in commit { $0[keyPath: keyPath] = value } }
        )
    }

    private var notifyBinding: Binding<Bool> {
        Binding(
            get: { monitor.settings.notifyOutages },
            set: { enabled in
                commit { $0.notifyOutages = enabled }
                if enabled, Bundle.main.bundleIdentifier != nil {
                    // Surface the system permission prompt right away rather
                    // than at the first outage.
                    UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound]) { _, _ in }
                }
            }
        )
    }

    // MARK: Destinations (applied immediately)

    private var destinationsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Destinations")
                .font(.system(size: 12, weight: .semibold))
            ForEach(monitor.settings.hosts, id: \.self) { host in
                HStack(spacing: 6) {
                    Button {
                        commit { $0.host = host }
                    } label: {
                        Image(systemName: host == monitor.settings.host ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(host == monitor.settings.host ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Ping this destination")
                    Text(host)
                        .font(.system(size: 12, design: .monospaced))
                    Spacer()
                    Button {
                        commit { $0.hosts.removeAll { $0 == host } }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(monitor.settings.hosts.count == 1)
                }
            }
            HStack {
                TextField("host or IP (e.g. 1.1.1.1)", text: $newHost)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit(addHost)
                Button("Add", action: addHost)
                    .disabled(newHost.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Switch quickly from the dot's right-click menu.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private func addHost() {
        let host = newHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }
        commit { if !$0.hosts.contains(host) { $0.hosts.append(host) } }
        newHost = ""
    }

    private func commit(_ change: (inout Settings) -> Void) {
        var s = monitor.settings
        change(&s)
        monitor.settings = s.sanitized()
    }

    // MARK: Detection profile + numbers (draft, committed by Apply)

    private var profileSection: some View {
        Picker("Profile", selection: Binding(
            get: { draftProfile },
            set: { applyPreset($0) }
        )) {
            ForEach(DetectionProfile.allCases) { profile in
                Text(profile.title).tag(profile)
            }
        }
        .pickerStyle(.segmented)
        .font(.system(size: 12))
    }

    /// Derived from the draft fields: matches a preset exactly, or Custom.
    private var draftProfile: DetectionProfile {
        guard let params = draftDetectionParams() else { return .custom }
        for (profile, preset) in Settings.presets where preset.approximatelyEquals(params) {
            return profile
        }
        return .custom
    }

    private func draftDetectionParams() -> DetectionParams? {
        guard let a = Double(alpha), let f = Int(failuresToDown), let s = Int(successesToRecover),
              let yl = Double(yellowLoss), let rl = Double(redLoss),
              let yj = Double(yellowJitter) else { return nil }
        return DetectionParams(ewmaAlpha: a, failuresToDown: f, successesToRecover: s,
                               yellowLossPercent: yl, redLossPercent: rl, yellowJitterMs: yj)
    }

    private func applyPreset(_ profile: DetectionProfile) {
        guard let preset = Settings.presets[profile] else { return } // Custom: keep fields
        alpha = formatNumber(preset.ewmaAlpha)
        failuresToDown = String(preset.failuresToDown)
        successesToRecover = String(preset.successesToRecover)
        yellowLoss = formatNumber(preset.yellowLossPercent)
        redLoss = formatNumber(preset.redLossPercent)
        yellowJitter = formatNumber(preset.yellowJitterMs)
    }

    private var detectionSection: some View {
        // Hints show the defaults; derive them so they can't drift.
        let def = Settings.default
        return VStack(alignment: .leading, spacing: 6) {
            row("Ping interval (s)", $interval, hint: formatNumber(def.intervalSeconds))
            row("Timeout (ms)", $timeout, hint: String(def.timeoutMs))
            row("Yellow > latency (ms)", $yellowLatency, hint: formatNumber(def.yellowLatencyMs))
            row("Red > latency (ms)", $redLatency, hint: formatNumber(def.redLatencyMs))
            row("Yellow > loss (%)", $yellowLoss, hint: formatNumber(def.detection.yellowLossPercent))
            row("Red > loss (%)", $redLoss, hint: formatNumber(def.detection.redLossPercent))
            row("Yellow > jitter (ms)", $yellowJitter, hint: formatNumber(def.detection.yellowJitterMs))
            row("Red after consecutive fails", $failuresToDown, hint: String(def.detection.failuresToDown))
            row("Recover after consecutive OKs", $successesToRecover, hint: String(def.detection.successesToRecover))
            row("Reactivity (0.05–0.9)", $alpha, hint: formatNumber(def.detection.ewmaAlpha))
        }
    }

    private func row(_ title: String, _ binding: Binding<String>, hint: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
            Spacer()
            TextField(hint, text: binding)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .frame(width: 110)
                .multilineTextAlignment(.trailing)
        }
    }

    private func loadDraft() {
        let s = monitor.settings
        interval = formatNumber(s.intervalSeconds)
        timeout = String(s.timeoutMs)
        yellowLatency = formatNumber(s.yellowLatencyMs)
        redLatency = formatNumber(s.redLatencyMs)
        yellowLoss = formatNumber(s.detection.yellowLossPercent)
        redLoss = formatNumber(s.detection.redLossPercent)
        yellowJitter = formatNumber(s.detection.yellowJitterMs)
        failuresToDown = String(s.detection.failuresToDown)
        successesToRecover = String(s.detection.successesToRecover)
        alpha = formatNumber(s.detection.ewmaAlpha)
    }

    private func applyAndClose() {
        let typed = draftSnapshot()
        commit { s in
            if let v = Double(interval) { s.intervalSeconds = v }
            if let v = Int(timeout) { s.timeoutMs = v }
            if let v = Double(yellowLatency) { s.yellowLatencyMs = v }
            if let v = Double(redLatency) { s.redLatencyMs = v }
            if let v = Double(yellowLoss) { s.detection.yellowLossPercent = v }
            if let v = Double(redLoss) { s.detection.redLossPercent = v }
            if let v = Double(yellowJitter) { s.detection.yellowJitterMs = v }
            if let v = Int(failuresToDown) { s.detection.failuresToDown = v }
            if let v = Int(successesToRecover) { s.detection.successesToRecover = v }
            if let v = Double(alpha) { s.detection.ewmaAlpha = v }
        }
        loadDraft() // reflect sanitized values back into the fields
        // Close only if everything was accepted as typed; if something was
        // rejected or clamped, stay open so the corrected values are visible.
        if draftSnapshot() == typed {
            onClose()
        }
    }

    private func draftSnapshot() -> [String] {
        [interval, timeout, yellowLatency, redLatency,
         yellowLoss, redLoss, yellowJitter, failuresToDown, successesToRecover, alpha]
    }
}

/// Formats a settings number for display; integers lose the trailing ".0".
/// Values are already clamped by Settings.sanitized(), but stay trap-safe anyway.
func formatNumber(_ value: Double) -> String {
    guard value.isFinite, abs(value) < 1e15 else { return "0" }
    if value == value.rounded() { return String(Int(value)) }
    // %g trims representation noise (0.449999988… → "0.45").
    return String(format: "%g", value)
}
