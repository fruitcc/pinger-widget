import Foundation
import Combine

enum ConnectionStatus {
    case unknown  // not enough data yet
    case good     // green
    case degraded // yellow
    case down     // red
}

@MainActor
final class PingMonitor: ObservableObject {
    static let historySize = 10

    @Published private(set) var events: [PingEvent] = []  // newest first
    @Published private(set) var status: ConnectionStatus = .unknown
    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            // Only host/interval/timeout changes invalidate old samples;
            // threshold edits just need the current window re-scored.
            let needsRestart = settings.host != oldValue.host
                || settings.intervalSeconds != oldValue.intervalSeconds
                || settings.timeoutMs != oldValue.timeoutMs
            if needsRestart {
                restart()
            } else {
                status = evaluate()
            }
        }
    }

    private var timer: Timer?
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
        timer?.invalidate()
        events.removeAll()
        status = .unknown
        tick()
        let timer = Timer(timeInterval: settings.intervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // .common so the timer keeps firing while menus/panels are open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
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
            }
        }
    }

    private func record(_ event: PingEvent) {
        events.insert(event, at: 0)
        if events.count > Self.historySize {
            events.removeLast(events.count - Self.historySize)
        }
        status = evaluate()
    }

    // MARK: - Health evaluation

    var lossPercent: Double {
        guard !events.isEmpty else { return 0 }
        let failures = events.filter {
            if case .success = $0.outcome { return false }
            return true
        }.count
        return Double(failures) / Double(events.count) * 100
    }

    var averageLatencyMs: Double? {
        let latencies = events.compactMap { event -> Double? in
            if case .success(let ms) = event.outcome { return ms }
            return nil
        }
        guard !latencies.isEmpty else { return nil }
        return latencies.reduce(0, +) / Double(latencies.count)
    }

    private func evaluate() -> ConnectionStatus {
        guard !events.isEmpty else { return .unknown }
        // No successful pings in the window at all.
        guard let avg = averageLatencyMs else { return .down }
        let loss = lossPercent
        if loss > settings.redLossPercent || avg > settings.redLatencyMs { return .down }
        if loss > settings.yellowLossPercent || avg > settings.yellowLatencyMs { return .degraded }
        return .good
    }
}
