import SwiftUI

// MARK: - Left click: ping results

struct StatusPanelView: View {
    @ObservedObject var monitor: PingMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            eventList
            Text("Right-click the dot for settings")
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
        if let avg = monitor.averageLatencyMs {
            parts.append(String(format: "avg %.0f ms", avg))
        }
        if !monitor.events.isEmpty {
            parts.append(String(format: "%.0f%% loss", monitor.lossPercent))
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
                    EventRow(event: event)
                }
            }
        }
    }
}

private struct EventRow: View {
    let event: PingEvent

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
        case .success: .green
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

// MARK: - Right click: settings + quit

struct SettingsPanelView: View {
    @ObservedObject var monitor: PingMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(.system(size: 13, weight: .semibold))
            SettingsForm(monitor: monitor)
            Divider()
            HStack {
                Spacer()
                Button("Quit Pinger") { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 320)
    }
}

private struct SettingsForm: View {
    @ObservedObject var monitor: PingMonitor

    @State private var host = ""
    @State private var interval = ""
    @State private var timeout = ""
    @State private var yellowLatency = ""
    @State private var redLatency = ""
    @State private var yellowLoss = ""
    @State private var redLoss = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Host", $host, hint: "8.8.8.8")
            row("Interval (s)", $interval, hint: "2")
            row("Timeout (ms)", $timeout, hint: "1000")
            row("Yellow > latency (ms)", $yellowLatency, hint: "150")
            row("Red > latency (ms)", $redLatency, hint: "500")
            row("Yellow > loss (%)", $yellowLoss, hint: "10")
            row("Red > loss (%)", $redLoss, hint: "40")
            HStack {
                Spacer()
                Button("Apply") { apply() }
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear(perform: load)
    }

    private func row(_ title: String, _ binding: Binding<String>, hint: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11))
            Spacer()
            TextField(hint, text: binding)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .frame(width: 110)
                .multilineTextAlignment(.trailing)
        }
    }

    private func load() {
        let s = monitor.settings
        host = s.host
        interval = formatNumber(s.intervalSeconds)
        timeout = String(s.timeoutMs)
        yellowLatency = formatNumber(s.yellowLatencyMs)
        redLatency = formatNumber(s.redLatencyMs)
        yellowLoss = formatNumber(s.yellowLossPercent)
        redLoss = formatNumber(s.redLossPercent)
    }

    private func apply() {
        var s = monitor.settings
        s.host = host
        if let v = Double(interval) { s.intervalSeconds = v }
        if let v = Int(timeout) { s.timeoutMs = v }
        if let v = Double(yellowLatency) { s.yellowLatencyMs = v }
        if let v = Double(redLatency) { s.redLatencyMs = v }
        if let v = Double(yellowLoss) { s.yellowLossPercent = v }
        if let v = Double(redLoss) { s.redLossPercent = v }
        monitor.settings = s.sanitized()
        load() // reflect sanitized values back into the fields
    }
}

/// Formats a settings number for display; integers lose the trailing ".0".
/// Values are already clamped by Settings.sanitized(), but stay trap-safe anyway.
func formatNumber(_ value: Double) -> String {
    guard value.isFinite, abs(value) < 1e15 else { return "0" }
    return value == value.rounded() ? String(Int(value)) : String(value)
}
