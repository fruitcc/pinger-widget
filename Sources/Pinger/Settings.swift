import Foundation

/// User-configurable settings, persisted in UserDefaults.
struct Settings: Equatable {
    var host: String
    var intervalSeconds: Double
    var timeoutMs: Int
    /// Latency (ms) above which status degrades to yellow.
    var yellowLatencyMs: Double
    /// Latency (ms) above which status degrades to red.
    var redLatencyMs: Double
    /// Packet loss (%) above which status degrades to yellow.
    var yellowLossPercent: Double
    /// Packet loss (%) above which status degrades to red.
    var redLossPercent: Double

    static let `default` = Settings(
        host: "8.8.8.8",
        intervalSeconds: 2,
        timeoutMs: 1000,
        yellowLatencyMs: 150,
        redLatencyMs: 500,
        yellowLossPercent: 10,
        redLossPercent: 40
    )

    private enum Key {
        static let host = "host"
        static let interval = "intervalSeconds"
        static let timeout = "timeoutMs"
        static let yellowLatency = "yellowLatencyMs"
        static let redLatency = "redLatencyMs"
        static let yellowLoss = "yellowLossPercent"
        static let redLoss = "redLossPercent"
    }

    static func load() -> Settings {
        let d = UserDefaults.standard
        var s = Settings.default
        if let host = d.string(forKey: Key.host), !host.isEmpty { s.host = host }
        if d.object(forKey: Key.interval) != nil { s.intervalSeconds = d.double(forKey: Key.interval) }
        if d.object(forKey: Key.timeout) != nil { s.timeoutMs = d.integer(forKey: Key.timeout) }
        if d.object(forKey: Key.yellowLatency) != nil { s.yellowLatencyMs = d.double(forKey: Key.yellowLatency) }
        if d.object(forKey: Key.redLatency) != nil { s.redLatencyMs = d.double(forKey: Key.redLatency) }
        if d.object(forKey: Key.yellowLoss) != nil { s.yellowLossPercent = d.double(forKey: Key.yellowLoss) }
        if d.object(forKey: Key.redLoss) != nil { s.redLossPercent = d.double(forKey: Key.redLoss) }
        return s.sanitized()
    }

    func save() {
        let d = UserDefaults.standard
        d.set(host, forKey: Key.host)
        d.set(intervalSeconds, forKey: Key.interval)
        d.set(timeoutMs, forKey: Key.timeout)
        d.set(yellowLatencyMs, forKey: Key.yellowLatency)
        d.set(redLatencyMs, forKey: Key.redLatency)
        d.set(yellowLossPercent, forKey: Key.yellowLoss)
        d.set(redLossPercent, forKey: Key.redLoss)
    }

    /// Clamps every field into a safe range. Non-finite values (NaN/inf survive
    /// Double parsing and propagate through min/max) fall back to the default.
    func sanitized() -> Settings {
        var s = self
        s.host = s.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.host.isEmpty { s.host = Settings.default.host }
        s.intervalSeconds = Self.clamp(s.intervalSeconds, 0.5...3600, fallback: Settings.default.intervalSeconds)
        s.timeoutMs = min(max(s.timeoutMs, 100), 10_000)
        s.yellowLatencyMs = Self.clamp(s.yellowLatencyMs, 1...60_000, fallback: Settings.default.yellowLatencyMs)
        s.redLatencyMs = Self.clamp(s.redLatencyMs, s.yellowLatencyMs...60_000, fallback: max(Settings.default.redLatencyMs, s.yellowLatencyMs))
        s.yellowLossPercent = Self.clamp(s.yellowLossPercent, 0...100, fallback: Settings.default.yellowLossPercent)
        s.redLossPercent = Self.clamp(s.redLossPercent, s.yellowLossPercent...100, fallback: max(Settings.default.redLossPercent, s.yellowLossPercent))
        return s
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
