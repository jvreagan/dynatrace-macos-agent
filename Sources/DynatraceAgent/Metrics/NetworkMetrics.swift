import Foundation
import Darwin

final class NetworkMetrics {
    private var previousBytes: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]

    func collect(hostname: String) -> [MetricPoint] {
        let now = Date()
        var metrics: [MetricPoint] = []

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return []
        }
        defer { freeifaddrs(ifaddr) }

        // Aggregate bytes per interface name
        var currentBytes: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = cursor {
            let name = String(cString: addr.pointee.ifa_name)

            // Only AF_LINK (data link layer) has byte counts
            if addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK) {
                // Skip loopback
                if name != "lo0" {
                    let data = unsafeBitCast(addr.pointee.ifa_data, to: UnsafeMutablePointer<if_data>.self)
                    let bytesIn = UInt64(data.pointee.ifi_ibytes)
                    let bytesOut = UInt64(data.pointee.ifi_obytes)

                    let existing = currentBytes[name] ?? (bytesIn: 0, bytesOut: 0)
                    currentBytes[name] = (
                        bytesIn: existing.bytesIn + bytesIn,
                        bytesOut: existing.bytesOut + bytesOut
                    )
                }
            }

            cursor = addr.pointee.ifa_next
        }

        // Compute deltas
        for (iface, current) in currentBytes {
            if let prev = previousBytes[iface] {
                let deltaIn = current.bytesIn >= prev.bytesIn ? current.bytesIn - prev.bytesIn : current.bytesIn
                let deltaOut = current.bytesOut >= prev.bytesOut ? current.bytesOut - prev.bytesOut : current.bytesOut

                let dims: [String: String] = [
                    "host.name": hostname,
                    "interface": iface
                ]

                metrics.append(contentsOf: [
                    MetricPoint(key: "macos.network.bytes_in", dimensions: dims, value: Double(deltaIn), timestamp: now),
                    MetricPoint(key: "macos.network.bytes_out", dimensions: dims, value: Double(deltaOut), timestamp: now),
                ])
            }
        }

        previousBytes = currentBytes
        return metrics
    }
}
