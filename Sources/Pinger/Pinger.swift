import Foundation

enum PingOutcome: Equatable {
    case success(latencyMs: Double)
    case timeout
    case error(String)
}

struct PingEvent: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let outcome: PingOutcome
}

/// Runs a single ICMP ping by invoking /sbin/ping (avoids raw-socket entitlements).
enum Pinger {
    static func ping(host: String, timeoutMs: Int, completion: @escaping (PingOutcome) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let outcome = runPing(host: host, timeoutMs: timeoutMs)
            completion(outcome)
        }
    }

    private static func runPing(host: String, timeoutMs: Int) -> PingOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        // -c 1: single ping; -W: ms to wait for the reply;
        // -t: overall deadline in seconds so DNS stalls can't hang the run.
        let deadlineSeconds = max(1, Int((Double(timeoutMs) / 1000).rounded(.up)) + 1)
        process.arguments = ["-c", "1", "-W", String(timeoutMs), "-t", String(deadlineSeconds), host]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return .error("failed to run ping: \(error.localizedDescription)")
        }

        // Drain both pipes before waiting for exit: if the child fills a pipe
        // buffer it blocks on write and waitUntilExit would deadlock.
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errData = stderr.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        let output = String(data: outData, encoding: .utf8) ?? ""
        let errOutput = String(data: errData, encoding: .utf8) ?? ""

        if process.terminationStatus == 0, let ms = parseLatency(from: output) {
            return .success(latencyMs: ms)
        }
        if output.contains("Request timeout") || process.terminationStatus == 2 {
            return .timeout
        }
        let reason = firstMeaningfulLine(of: errOutput) ?? firstMeaningfulLine(of: output) ?? "exit code \(process.terminationStatus)"
        return .error(reason)
    }

    /// Extracts "time=23.4 ms" from ping output.
    static func parseLatency(from output: String) -> Double? {
        guard let range = output.range(of: #"time=([0-9.]+) ms"#, options: .regularExpression) else {
            return nil
        }
        let match = output[range]
        let number = match.dropFirst("time=".count).dropLast(" ms".count)
        return Double(number)
    }

    private static func firstMeaningfulLine(of text: String) -> String? {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
            .map { line in
                // Strip the "ping: " prefix for a cleaner message.
                line.hasPrefix("ping: ") ? String(line.dropFirst("ping: ".count)) : line
            }
    }
}
