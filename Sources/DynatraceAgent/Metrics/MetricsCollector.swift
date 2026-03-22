import Foundation

final class MetricsCollector {
    private let cpuMetrics = CPUMetrics()
    private let memoryMetrics = MemoryMetrics()
    private let diskMetrics = DiskMetrics()
    private let networkMetrics = NetworkMetrics()
    private let systemLoadMetrics = SystemLoadMetrics()
    private let swapMetrics = SwapMetrics()

    private let logManager: LogManager
    private let hostname: @Sendable () -> String

    init(logManager: LogManager, hostnameProvider: @escaping @Sendable () -> String = {
        Host.current().localizedName ?? "unknown"
    }) {
        self.logManager = logManager
        self.hostname = hostnameProvider
    }

    func collect() -> [MetricPoint] {
        let host = hostname()
        var allMetrics: [MetricPoint] = []

        allMetrics.append(contentsOf: cpuMetrics.collect(hostname: host))
        allMetrics.append(contentsOf: memoryMetrics.collect(hostname: host))
        allMetrics.append(contentsOf: diskMetrics.collect(hostname: host))
        allMetrics.append(contentsOf: networkMetrics.collect(hostname: host))
        allMetrics.append(contentsOf: systemLoadMetrics.collect(hostname: host))
        allMetrics.append(contentsOf: swapMetrics.collect(hostname: host))

        return allMetrics
    }
}
