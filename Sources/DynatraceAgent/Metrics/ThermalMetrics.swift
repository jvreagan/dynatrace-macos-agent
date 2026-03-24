import Foundation

final class ThermalMetrics {
    func collect(hostname: String) -> [MetricPoint] {
        let dims = ["host.name": hostname]
        let now = Date()

        let thermalValue: Double = switch ProcessInfo.processInfo.thermalState {
        case .nominal:  0
        case .fair:     1
        case .serious:  2
        case .critical: 3
        @unknown default: 0
        }

        return [
            MetricPoint(key: "macos.thermal.state", dimensions: dims, value: thermalValue, timestamp: now),
            MetricPoint(key: "macos.system.uptime_seconds", dimensions: dims,
                value: ProcessInfo.processInfo.systemUptime, timestamp: now),
        ]
    }
}
