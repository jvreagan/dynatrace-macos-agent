import Foundation
import Darwin

final class NetworkMetrics {
    private var previousBytes: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private var previousErrors: [String: (errorsIn: UInt64, errorsOut: UInt64, dropsIn: UInt64, dropsOut: UInt64)] = [:]

    func collect(hostname: String) -> [MetricPoint] {
        let now = Date()
        var metrics: [MetricPoint] = []

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return []
        }
        defer { freeifaddrs(ifaddr) }

        // Aggregate stats per interface name
        var currentBytes: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
        var currentErrors: [String: (errorsIn: UInt64, errorsOut: UInt64, dropsIn: UInt64, dropsOut: UInt64)] = [:]

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = cursor {
            let name = String(cString: addr.pointee.ifa_name)

            if addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK), !NetworkMetrics.isVirtualInterface(name) {
                let data = unsafeBitCast(addr.pointee.ifa_data, to: UnsafeMutablePointer<if_data>.self)
                let d = data.pointee

                let existing = currentBytes[name] ?? (bytesIn: 0, bytesOut: 0)
                currentBytes[name] = (
                    bytesIn: existing.bytesIn + UInt64(d.ifi_ibytes),
                    bytesOut: existing.bytesOut + UInt64(d.ifi_obytes)
                )

                let existingErr = currentErrors[name] ?? (errorsIn: 0, errorsOut: 0, dropsIn: 0, dropsOut: 0)
                currentErrors[name] = (
                    errorsIn: existingErr.errorsIn + UInt64(d.ifi_ierrors),
                    errorsOut: existingErr.errorsOut + UInt64(d.ifi_oerrors),
                    dropsIn: existingErr.dropsIn + UInt64(d.ifi_iqdrops),
                    dropsOut: 0
                )
            }

            cursor = addr.pointee.ifa_next
        }

        // Compute deltas
        for (iface, current) in currentBytes {
            let dims: [String: String] = ["host.name": hostname, "interface": iface]

            if let prev = previousBytes[iface] {
                let deltaIn = current.bytesIn >= prev.bytesIn ? current.bytesIn - prev.bytesIn : current.bytesIn
                let deltaOut = current.bytesOut >= prev.bytesOut ? current.bytesOut - prev.bytesOut : current.bytesOut
                metrics.append(MetricPoint(key: "macos.network.bytes_in", dimensions: dims, value: Double(deltaIn), timestamp: now))
                metrics.append(MetricPoint(key: "macos.network.bytes_out", dimensions: dims, value: Double(deltaOut), timestamp: now))
            }

            if let prevErr = previousErrors[iface], let currErr = currentErrors[iface] {
                let deltaErrIn = currErr.errorsIn >= prevErr.errorsIn ? currErr.errorsIn - prevErr.errorsIn : currErr.errorsIn
                let deltaErrOut = currErr.errorsOut >= prevErr.errorsOut ? currErr.errorsOut - prevErr.errorsOut : currErr.errorsOut
                let deltaDropIn = currErr.dropsIn >= prevErr.dropsIn ? currErr.dropsIn - prevErr.dropsIn : currErr.dropsIn
                metrics.append(MetricPoint(key: "macos.network.errors_in", dimensions: dims, value: Double(deltaErrIn), timestamp: now))
                metrics.append(MetricPoint(key: "macos.network.errors_out", dimensions: dims, value: Double(deltaErrOut), timestamp: now))
                metrics.append(MetricPoint(key: "macos.network.drops_in", dimensions: dims, value: Double(deltaDropIn), timestamp: now))
            }
        }

        previousBytes = currentBytes
        previousErrors = currentErrors
        return metrics
    }

    // Loopback, VPN tunnels, AirDrop, Sidecar, bridges, and other virtual interfaces
    private static let virtualPrefixes = ["lo", "utun", "awdl", "llw", "bridge", "gif", "stf", "ap"]

    private static func isVirtualInterface(_ name: String) -> Bool {
        virtualPrefixes.contains(where: { name.hasPrefix($0) })
    }
}
