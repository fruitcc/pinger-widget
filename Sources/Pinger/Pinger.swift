import Foundation
import Darwin

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

/// Sends a single ICMP echo request over an unprivileged SOCK_DGRAM ICMP
/// socket (Apple's SimplePing approach). Works inside the App Sandbox with
/// the network-client entitlement — no subprocesses, no raw-socket privilege.
/// Supports IPv4 (ICMP) and IPv6 (ICMPv6); address family follows the
/// system's resolution preference for hostnames.
enum Pinger {
    static func ping(host: String, timeoutMs: Int, completion: @escaping (PingOutcome) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            completion(runPing(host: host, timeoutMs: timeoutMs))
        }
    }

    private static func runPing(host: String, timeoutMs: Int) -> PingOutcome {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_DGRAM
        var resolved: UnsafeMutablePointer<addrinfo>?
        let gaiResult = getaddrinfo(host, nil, &hints, &resolved)
        guard gaiResult == 0, let addr = resolved else {
            if gaiResult == EAI_NONAME || gaiResult == EAI_NODATA {
                return .error("cannot resolve \(host)")
            }
            return .error(String(cString: gai_strerror(gaiResult)))
        }
        defer { freeaddrinfo(resolved) }

        let isIPv6 = addr.pointee.ai_family == AF_INET6
        let fd = socket(addr.pointee.ai_family, SOCK_DGRAM, isIPv6 ? IPPROTO_ICMPV6 : IPPROTO_ICMP)
        guard fd >= 0 else {
            return .error("socket: \(String(cString: strerror(errno)))")
        }
        defer { close(fd) }

        // Echo request: 8-byte ICMP header + 16-byte payload. The kernel may
        // rewrite the identifier on datagram ICMP sockets, so replies are
        // matched on the sequence number plus a random payload token instead.
        let sequence = UInt16.random(in: 0...UInt16.max)
        let token = (0..<8).map { _ in UInt8.random(in: 0...UInt8.max) }
        var packet = [UInt8](repeating: 0, count: 24)
        packet[0] = isIPv6 ? 128 : 8 // echo request (ICMPv6 / ICMP)
        packet[6] = UInt8(sequence >> 8)
        packet[7] = UInt8(sequence & 0xFF)
        for (i, byte) in token.enumerated() { packet[8 + i] = byte }
        if !isIPv6 {
            // ICMPv6 checksums are computed by the kernel (they cover an IPv6
            // pseudo-header we can't build here); IPv4 ICMP is ours to fill.
            let checksum = icmpChecksum(packet)
            packet[2] = UInt8(checksum >> 8)
            packet[3] = UInt8(checksum & 0xFF)
        }

        // connect() the socket so replies count as return traffic on an
        // outgoing connection — required for the App Sandbox to deliver them
        // under the network-client entitlement alone.
        guard connect(fd, addr.pointee.ai_addr, addr.pointee.ai_addrlen) == 0 else {
            return .error("connect: \(String(cString: strerror(errno)))")
        }

        let start = DispatchTime.now()
        let sent = send(fd, packet, packet.count, 0)
        guard sent == packet.count else {
            return .error("send: \(String(cString: strerror(errno)))")
        }

        // Wait for the matching echo reply until the deadline.
        var buffer = [UInt8](repeating: 0, count: 2048)
        while true {
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            let remainingMs = Int32(Double(timeoutMs) - elapsedMs)
            if remainingMs <= 0 { return .timeout }

            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, remainingMs)
            if ready == 0 { return .timeout }
            if ready < 0 {
                if errno == EINTR { continue }
                return .error("poll: \(String(cString: strerror(errno)))")
            }

            let received = recv(fd, &buffer, buffer.count, 0)
            guard received > 0 else { continue }

            // IPv4 datagram ICMP replies arrive with the IP header attached;
            // ICMPv6 replies start directly at the ICMPv6 header.
            let headerLength = isIPv6 ? 0 : Int(buffer[0] & 0x0F) * 4
            guard received >= headerLength + 16 else { continue }
            let icmp = Array(buffer[headerLength..<received])

            guard icmp[0] == (isIPv6 ? 129 : 0) else { continue } // echo reply
            let replySequence = UInt16(icmp[6]) << 8 | UInt16(icmp[7])
            guard replySequence == sequence, Array(icmp[8..<16]) == token else { continue }

            let latency = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            return .success(latencyMs: latency)
        }
    }

    /// Standard internet checksum (RFC 1071) over the ICMP message.
    private static func icmpChecksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < bytes.count {
            sum &+= UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1])
            i += 2
        }
        if i < bytes.count { sum &+= UInt32(bytes[i]) << 8 }
        while sum > 0xFFFF { sum = (sum & 0xFFFF) &+ (sum >> 16) }
        return ~UInt16(sum & 0xFFFF)
    }
}
