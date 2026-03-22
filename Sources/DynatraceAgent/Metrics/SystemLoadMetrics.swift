import Foundation
import Darwin

final class SystemLoadMetrics {
    func collect(hostname: String) -> [MetricPoint] {
        let dims = ["host.name": hostname]
        let now = Date()

        var loadavg = [Double](repeating: 0, count: 3)
        let count = getloadavg(&loadavg, 3)

        guard count == 3 else { return [] }

        return [
            MetricPoint(key: "macos.load.1m", dimensions: dims, value: loadavg[0], timestamp: now),
            MetricPoint(key: "macos.load.5m", dimensions: dims, value: loadavg[1], timestamp: now),
            MetricPoint(key: "macos.load.15m", dimensions: dims, value: loadavg[2], timestamp: now),
        ]
    }
}
