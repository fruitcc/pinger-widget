import Foundation
import Combine

enum ConnectionStatus {
    case unknown  // not enough data yet
    case good     // green
    case degraded // yellow
    case down     // red
}

/// Health detection strategy, built for fast reaction without flip-flopping:
///
/// 1. **Recency-weighted scoring (EWMA)** — loss and latency are exponentially
///    weighted moving averages, so the last few pings dominate and old samples
///    fade instead of lingering for a full fixed window.
/// 2. **Failure fast path** — N consecutive failures force red immediately,
///    without waiting for the average to drift there.
/// 3. **Sticky recovery** — leaving red requires M consecutive successes, so a
///    single lucky ping during an outage can't flash green. On recovery the
///    EWMAs are reset, so green appears right away instead of waiting for a
///    high loss average to decay.
/// 4. **Adaptive burst probing** — at the first sign of a transition (a failure
///    while up, or a success while down) the ping rate quadruples until the
///    state is confirmed, so verdicts arrive in seconds without raising the
///    steady-state ping rate.
@MainActor
final class PingMonitor: ObservableObject {
    static let historySize = 10

    @Published private(set) var events: [PingEvent] = []  // newest first
    @Published private(set) var status: ConnectionStatus = .unknown
    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            if settings.host != oldValue.host {
                // Only a destination change invalidates old samples.
                restart()
            } else {
                status = evaluate()
                scheduleNext(after: nextDelay())
            }
        }
    }

    /// Smoothed latency over recent successful pings (nil until one succeeds).
    private(set) var smoothedLatencyMs: Double?
    /// Smoothed loss fraction (0...1) over recent pings.
    private(set) var smoothedLossFraction: Double = 0
    /// RTP-style jitter: EWMA of each sample's deviation from the smoothed
    /// latency. A single 900 ms spike on a 30 ms baseline registers instantly
    /// (alpha × 870 ms) and decays over the next few good pings; sustained
    /// oscillation keeps it high. Nil until two successes.
    private(set) var smoothedJitterMs: Double?

    private var consecutiveFailures = 0
    private var consecutiveSuccesses = 0
    private var hasSamples = false

    private var nextTimer: Timer?
    private var pingInFlight = false
    /// Bumped on every restart; in-flight pings from an older generation are discarded.
    private var generation = 0

    init() {
        settings = Settings.load()
    }

    func start() {
        restart()
    }

    private func restart() {
        generation += 1
        pingInFlight = false
        nextTimer?.invalidate()
        events.removeAll()
        smoothedLatencyMs = nil
        smoothedLossFraction = 0
        smoothedJitterMs = nil
        consecutiveFailures = 0
        consecutiveSuccesses = 0
        hasSamples = false
        status = .unknown
        tick()
    }

    private func tick() {
        // Don't stack pings if one is still waiting (slow DNS, long timeout).
        guard !pingInFlight else { return }
        pingInFlight = true
        let generation = self.generation
        Pinger.ping(host: settings.host, timeoutMs: settings.timeoutMs) { [weak self] outcome in
            Task { @MainActor in
                guard let self else { return }
                // Discard results that started before the last restart.
                guard generation == self.generation else { return }
                self.pingInFlight = false
                self.record(PingEvent(date: Date(), outcome: outcome))
                self.scheduleNext(after: self.nextDelay())
            }
        }
    }

    private func scheduleNext(after delay: TimeInterval) {
        nextTimer?.invalidate()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // .common so the timer keeps firing while menus/panels are open.
        RunLoop.main.add(timer, forMode: .common)
        nextTimer = timer
    }

    /// Quadruple the probe rate while a transition is suspected but unconfirmed.
    private func nextDelay() -> TimeInterval {
        let suspectingOutage = status != .down && consecutiveFailures > 0
        let suspectingRecovery = status == .down && consecutiveSuccesses > 0
        if suspectingOutage || suspectingRecovery {
            return max(0.5, settings.intervalSeconds / 4)
        }
        return settings.intervalSeconds
    }

    private func record(_ event: PingEvent) {
        events.insert(event, at: 0)
        if events.count > Self.historySize {
            events.removeLast(events.count - Self.historySize)
        }

        let alpha = settings.detection.ewmaAlpha
        let lossSample: Double
        if case .success(let ms) = event.outcome {
            consecutiveSuccesses += 1
            consecutiveFailures = 0
            if let baseline = smoothedLatencyMs {
                // Deviation from the pre-update baseline is the jitter sample.
                // Seed at alpha weight too (prior jitter treated as 0), so one
                // early spike can't set the whole EWMA to its full deviation.
                let deviation = abs(ms - baseline)
                smoothedJitterMs = alpha * deviation + (1 - alpha) * (smoothedJitterMs ?? 0)
                smoothedLatencyMs = alpha * ms + (1 - alpha) * baseline
            } else {
                smoothedLatencyMs = ms
            }
            lossSample = 0
        } else {
            consecutiveFailures += 1
            consecutiveSuccesses = 0
            lossSample = 1
        }
        smoothedLossFraction = hasSamples ? alpha * lossSample + (1 - alpha) * smoothedLossFraction : lossSample
        hasSamples = true

        if status == .down && consecutiveSuccesses >= settings.detection.successesToRecover {
            // Recovery achieved: drop the outage-era averages *before* scoring,
            // so evaluate() judges the link's current quality (a comeback at
            // 900 ms latency scores red/yellow, not a blind green) instead of
            // waiting for a ~100% loss EWMA to decay.
            smoothedLossFraction = 0
            smoothedJitterMs = nil
            if case .success(let ms) = event.outcome { smoothedLatencyMs = ms }
        }
        status = evaluate()
    }

    var smoothedLossPercent: Double { smoothedLossFraction * 100 }

    /// Display string for the smoothed latency and jitter, e.g. "~19 ±7 ms",
    /// shared by the panel header and the menu bar tooltip.
    var latencySummary: String? {
        guard let lat = smoothedLatencyMs else { return nil }
        var summary = String(format: "~%.0f", lat)
        if let jitter = smoothedJitterMs {
            summary += String(format: " ±%.0f", jitter)
        }
        return summary + " ms"
    }

    private func evaluate() -> ConnectionStatus {
        guard hasSamples else { return .unknown }
        let d = settings.detection

        // Fast path: sustained failures mean down, no matter what the average says.
        if consecutiveFailures >= d.failuresToDown { return .down }

        // Sticky recovery: only consecutive successes can lift a red status.
        // Once recovery is achieved the tick falls through to normal scoring
        // (record() has already reset the outage-era averages), so a link that
        // came back slow or lossy shows yellow/red rather than a false green.
        if status == .down && consecutiveSuccesses < d.successesToRecover {
            return .down
        }

        if smoothedLossPercent > d.redLossPercent { return .down }
        if let lat = smoothedLatencyMs, lat > settings.redLatencyMs { return .down }
        // No success yet at all (e.g. first pings after launch are failing).
        if smoothedLatencyMs == nil { return .down }
        if smoothedLossPercent > d.yellowLossPercent { return .degraded }
        if let lat = smoothedLatencyMs, lat > settings.yellowLatencyMs { return .degraded }
        // Latency spikes/instability degrade quality even when the average
        // looks fine; jitter alone never causes red.
        if let jitter = smoothedJitterMs, jitter > d.yellowJitterMs { return .degraded }
        return .good
    }
}
