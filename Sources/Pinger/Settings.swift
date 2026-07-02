import Foundation

enum DetectionProfile: String, CaseIterable, Identifiable {
    case sensitive, balanced, steady, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .sensitive: "Sensitive"
        case .balanced: "Balanced"
        case .steady: "Steady"
        case .custom: "Custom"
        }
    }

    var summary: String {
        switch self {
        case .sensitive: "Reacts within 2–3 s of an outage; may blink on a single lost ping."
        case .balanced: "Good mix of speed and stability."
        case .steady: "Ignores brief hiccups; needs sustained failures to change."
        case .custom: "Your own tuning."
        }
    }
}

/// The knobs the detection profiles preset.
struct DetectionParams: Equatable {
    /// EWMA weight of the newest sample (higher = more reactive).
    var ewmaAlpha: Double
    /// Consecutive failures that force red immediately.
    var failuresToDown: Int
    /// Consecutive successes required to leave red.
    var successesToRecover: Int
    /// Smoothed loss (%) above which status degrades to yellow.
    var yellowLossPercent: Double
    /// Smoothed loss (%) above which status degrades to red.
    var redLossPercent: Double
    /// Smoothed jitter (ms) above which status degrades to yellow.
    /// Jitter is the EWMA of each sample's deviation from the smoothed
    /// latency, so isolated huge spikes register immediately and decay.
    var yellowJitterMs: Double
}

/// User-configurable settings, persisted in UserDefaults.
struct Settings: Equatable {
    /// Quick-switch destination list (right-click menu).
    var hosts: [String]
    /// The destination currently being pinged.
    var host: String
    var intervalSeconds: Double
    var timeoutMs: Int
    /// Smoothed latency (ms) above which status degrades to yellow.
    var yellowLatencyMs: Double
    /// Smoothed latency (ms) above which status degrades to red.
    var redLatencyMs: Double
    var detection: DetectionParams

    static let presets: [DetectionProfile: DetectionParams] = [
        // A single failure spikes the loss EWMA to alpha*100%, so yellowLoss
        // relative to alpha decides whether one dropped ping blinks yellow:
        // sensitive blinks by design; balanced and steady need 2+ failures.
        .sensitive: DetectionParams(ewmaAlpha: 0.45, failuresToDown: 2, successesToRecover: 2, yellowLossPercent: 15, redLossPercent: 50, yellowJitterMs: 60),
        .balanced: DetectionParams(ewmaAlpha: 0.30, failuresToDown: 3, successesToRecover: 3, yellowLossPercent: 35, redLossPercent: 60, yellowJitterMs: 100),
        .steady: DetectionParams(ewmaAlpha: 0.18, failuresToDown: 5, successesToRecover: 4, yellowLossPercent: 40, redLossPercent: 70, yellowJitterMs: 150),
    ]

    /// The profile is derived from the values, not stored: if the detection
    /// params match a preset exactly, that's the profile; otherwise Custom.
    var detectionProfile: DetectionProfile {
        for (profile, params) in Self.presets where params == detection {
            return profile
        }
        return .custom
    }

    static let `default` = Settings(
        hosts: ["8.8.8.8", "1.1.1.1"],
        host: "8.8.8.8",
        intervalSeconds: 2,
        timeoutMs: 1000,
        yellowLatencyMs: 150,
        redLatencyMs: 500,
        detection: presets[.balanced]!
    )

    private enum Key {
        static let hosts = "hosts"
        static let host = "host"
        static let interval = "intervalSeconds"
        static let timeout = "timeoutMs"
        static let yellowLatency = "yellowLatencyMs"
        static let redLatency = "redLatencyMs"
        static let alpha = "ewmaAlpha"
        static let failuresToDown = "failuresToDown"
        static let successesToRecover = "successesToRecover"
        static let yellowLoss = "yellowLossPercent"
        static let redLoss = "redLossPercent"
        static let yellowJitter = "yellowJitterMs"
    }

    static func load() -> Settings {
        let d = UserDefaults.standard
        var s = Settings.default
        if let hosts = d.stringArray(forKey: Key.hosts) { s.hosts = hosts }
        if let host = d.string(forKey: Key.host), !host.isEmpty { s.host = host }
        if d.object(forKey: Key.interval) != nil { s.intervalSeconds = d.double(forKey: Key.interval) }
        if d.object(forKey: Key.timeout) != nil { s.timeoutMs = d.integer(forKey: Key.timeout) }
        if d.object(forKey: Key.yellowLatency) != nil { s.yellowLatencyMs = d.double(forKey: Key.yellowLatency) }
        if d.object(forKey: Key.redLatency) != nil { s.redLatencyMs = d.double(forKey: Key.redLatency) }
        if d.object(forKey: Key.alpha) != nil { s.detection.ewmaAlpha = d.double(forKey: Key.alpha) }
        if d.object(forKey: Key.failuresToDown) != nil { s.detection.failuresToDown = d.integer(forKey: Key.failuresToDown) }
        if d.object(forKey: Key.successesToRecover) != nil { s.detection.successesToRecover = d.integer(forKey: Key.successesToRecover) }
        if d.object(forKey: Key.yellowLoss) != nil { s.detection.yellowLossPercent = d.double(forKey: Key.yellowLoss) }
        if d.object(forKey: Key.redLoss) != nil { s.detection.redLossPercent = d.double(forKey: Key.redLoss) }
        if d.object(forKey: Key.yellowJitter) != nil { s.detection.yellowJitterMs = d.double(forKey: Key.yellowJitter) }
        return s.sanitized()
    }

    func save() {
        let d = UserDefaults.standard
        d.set(hosts, forKey: Key.hosts)
        d.set(host, forKey: Key.host)
        d.set(intervalSeconds, forKey: Key.interval)
        d.set(timeoutMs, forKey: Key.timeout)
        d.set(yellowLatencyMs, forKey: Key.yellowLatency)
        d.set(redLatencyMs, forKey: Key.redLatency)
        d.set(detection.ewmaAlpha, forKey: Key.alpha)
        d.set(detection.failuresToDown, forKey: Key.failuresToDown)
        d.set(detection.successesToRecover, forKey: Key.successesToRecover)
        d.set(detection.yellowLossPercent, forKey: Key.yellowLoss)
        d.set(detection.redLossPercent, forKey: Key.redLoss)
        d.set(detection.yellowJitterMs, forKey: Key.yellowJitter)
    }

    /// Clamps every field into a safe range. Non-finite values (NaN/inf survive
    /// Double parsing and propagate through min/max) fall back to the default.
    func sanitized() -> Settings {
        var s = self
        s.hosts = s.hosts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        s.hosts = s.hosts.filter { seen.insert($0).inserted }
        if s.hosts.isEmpty { s.hosts = Settings.default.hosts }
        s.host = s.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.hosts.contains(s.host) { s.host = s.hosts[0] }

        s.intervalSeconds = Self.clamp(s.intervalSeconds, 0.5...3600, fallback: Settings.default.intervalSeconds)
        s.timeoutMs = min(max(s.timeoutMs, 100), 10_000)
        s.yellowLatencyMs = Self.clamp(s.yellowLatencyMs, 1...60_000, fallback: Settings.default.yellowLatencyMs)
        s.redLatencyMs = Self.clamp(s.redLatencyMs, s.yellowLatencyMs...60_000, fallback: max(Settings.default.redLatencyMs, s.yellowLatencyMs))
        s.detection.ewmaAlpha = Self.clamp(s.detection.ewmaAlpha, 0.05...0.9, fallback: Settings.default.detection.ewmaAlpha)
        s.detection.failuresToDown = min(max(s.detection.failuresToDown, 1), 20)
        s.detection.successesToRecover = min(max(s.detection.successesToRecover, 1), 20)
        s.detection.yellowLossPercent = Self.clamp(s.detection.yellowLossPercent, 0...100, fallback: Settings.default.detection.yellowLossPercent)
        s.detection.redLossPercent = Self.clamp(s.detection.redLossPercent, s.detection.yellowLossPercent...100, fallback: max(Settings.default.detection.redLossPercent, s.detection.yellowLossPercent))
        s.detection.yellowJitterMs = Self.clamp(s.detection.yellowJitterMs, 1...60_000, fallback: Settings.default.detection.yellowJitterMs)
        return s
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
