import SwiftUI

// MARK: - Left click: ping results

struct StatusPanelView: View {
    @ObservedObject var monitor: PingMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            eventList
            Text("Right-click the dot to switch destination or open settings")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(width: 320)
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
        if let lat = monitor.smoothedLatencyMs {
            var latency = String(format: "~%.0f", lat)
            if let jitter = monitor.smoothedJitterMs {
                latency += String(format: " ±%.0f", jitter)
            }
            parts.append(latency + " ms")
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
            destinationsSection
            Divider()
            profileSection
            detectionSection
            HStack {
                Text(draftProfile.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Apply & Close") {
                    apply()
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 400)
        .onAppear(perform: loadDraft)
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
        for (profile, preset) in Settings.presets where preset == params {
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
        VStack(alignment: .leading, spacing: 6) {
            row("Ping interval (s)", $interval, hint: "2")
            row("Timeout (ms)", $timeout, hint: "1000")
            row("Yellow > latency (ms)", $yellowLatency, hint: "150")
            row("Red > latency (ms)", $redLatency, hint: "500")
            row("Yellow > loss (%)", $yellowLoss, hint: "35")
            row("Red > loss (%)", $redLoss, hint: "60")
            row("Yellow > jitter (ms)", $yellowJitter, hint: "100")
            row("Red after consecutive fails", $failuresToDown, hint: "3")
            row("Recover after consecutive OKs", $successesToRecover, hint: "3")
            row("Reactivity (0.05–0.9)", $alpha, hint: "0.3")
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

    private func apply() {
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
    }
}

/// Formats a settings number for display; integers lose the trailing ".0".
/// Values are already clamped by Settings.sanitized(), but stay trap-safe anyway.
func formatNumber(_ value: Double) -> String {
    guard value.isFinite, abs(value) < 1e15 else { return "0" }
    return value == value.rounded() ? String(Int(value)) : String(value)
}
