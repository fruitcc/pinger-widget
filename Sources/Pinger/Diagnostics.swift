import Foundation
import SystemConfiguration

/// Result of the automatic "where's the problem?" check that runs when the
/// status turns yellow or red: probes the default gateway and a well-known
/// internet host to localize the failure.
struct Diagnosis: Equatable {
    let date: Date
    let gatewayIP: String?
    let gatewayOutcome: PingOutcome?
    let referenceHost: String
    let referenceOutcome: PingOutcome
    let verdict: String
}

enum Diagnostics {
    /// Runs the gateway + reference probes off the main thread and delivers
    /// the diagnosis on completion. `monitoredHost` is the destination whose
    /// trouble triggered the check.
    static func run(monitoredHost: String, timeoutMs: Int, completion: @escaping (Diagnosis) -> Void) {
        let gatewayIP = defaultGatewayIPv4()
        // A second opinion on "is the internet reachable at all" — never the
        // same host we're already monitoring.
        let referenceHost = monitoredHost == "1.1.1.1" ? "8.8.8.8" : "1.1.1.1"
        let probeTimeout = min(timeoutMs, 1500)

        let group = DispatchGroup()
        var gatewayOutcome: PingOutcome?
        var referenceOutcome: PingOutcome = .timeout

        if let gatewayIP {
            group.enter()
            Pinger.ping(host: gatewayIP, timeoutMs: probeTimeout) { outcome in
                gatewayOutcome = outcome
                group.leave()
            }
        }
        group.enter()
        Pinger.ping(host: referenceHost, timeoutMs: probeTimeout) { outcome in
            referenceOutcome = outcome
            group.leave()
        }

        group.notify(queue: .global(qos: .utility)) {
            let diagnosis = Diagnosis(
                date: Date(),
                gatewayIP: gatewayIP,
                gatewayOutcome: gatewayOutcome,
                referenceHost: referenceHost,
                referenceOutcome: referenceOutcome,
                verdict: verdict(monitoredHost: monitoredHost, gatewayIP: gatewayIP,
                                 gateway: gatewayOutcome, reference: referenceOutcome)
            )
            completion(diagnosis)
        }
    }

    private static func verdict(monitoredHost: String, gatewayIP: String?,
                                gateway: PingOutcome?, reference: PingOutcome) -> String {
        let gatewayOK = { if case .success = gateway { return true } else { return false } }()
        let referenceOK = { if case .success = reference { return true } else { return false } }()

        if gatewayIP == nil {
            return "No default gateway — this Mac isn't connected to any network."
        }
        if !gatewayOK {
            return "Your router isn't responding — the problem looks local (Wi-Fi or router)."
        }
        if referenceOK {
            return "Router and internet are reachable — the trouble looks specific to \(monitoredHost)."
        }
        return "Router is fine but the internet isn't reachable — looks like an ISP or upstream problem."
    }

    /// Default IPv4 gateway from the system routing configuration.
    /// Works inside the App Sandbox (read-only SystemConfiguration state).
    static func defaultGatewayIPv4() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "Pinger" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let router = value["Router"] as? String, !router.isEmpty else {
            return nil
        }
        return router
    }
}
