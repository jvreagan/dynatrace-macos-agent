import Foundation
import Darwin

final class SwapMetrics {
    func collect(hostname: String) -> [MetricPoint] {
        let dims = ["host.name": hostname]
        let now = Date()

        var swapUsage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size

        let result = sysctlbyname("vm.swapusage", &swapUsage, &size, nil, 0)
        guard result == 0 else { return [] }

        let total = Double(swapUsage.xsu_total)
        let used = Double(swapUsage.xsu_used)
        let usagePct = total > 0 ? used / total * 100 : 0

        return [
            MetricPoint(key: "macos.swap.total", dimensions: dims, value: total, timestamp: now),
            MetricPoint(key: "macos.swap.used", dimensions: dims, value: used, timestamp: now),
            MetricPoint(key: "macos.swap.usage", dimensions: dims, value: usagePct, timestamp: now),
        ]
    }
}
