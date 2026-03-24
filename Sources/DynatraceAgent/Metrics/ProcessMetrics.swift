import Foundation
import Darwin

final class ProcessMetrics {
    func collect(hostname: String) -> [MetricPoint] {
        let dims = ["host.name": hostname]
        let now = Date()
        var metrics: [MetricPoint] = []

        // Total process count
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        metrics.append(MetricPoint(key: "macos.process.count", dimensions: dims,
            value: Double(count), timestamp: now))

        // Collect per-process memory usage
        var pids = [pid_t](repeating: 0, count: Int(count) + 16)
        let actual = proc_listallpids(&pids, Int32(pids.count) * Int32(MemoryLayout<pid_t>.size))

        var infos: [(name: String, memory: UInt64)] = []
        for i in 0..<Int(actual) {
            let pid = pids[i]
            guard pid > 0 else { continue }

            var taskInfo = proc_taskinfo()
            let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo,
                Int32(MemoryLayout<proc_taskinfo>.size))
            guard ret == Int32(MemoryLayout<proc_taskinfo>.size) else { continue }

            var nameBuf = [CChar](repeating: 0, count: Int(MAXCOMLEN) + 1)
            proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            let name = String(cString: nameBuf)
            guard !name.isEmpty else { continue }

            infos.append((name: name, memory: taskInfo.pti_resident_size))
        }

        // Top 5 processes by memory
        let top5 = infos.sorted { $0.memory > $1.memory }.prefix(5)
        for (rank, proc) in top5.enumerated() {
            let procDims = ["host.name": hostname, "process": proc.name, "rank": "\(rank + 1)"]
            metrics.append(MetricPoint(key: "macos.process.top_memory_bytes", dimensions: procDims,
                value: Double(proc.memory), timestamp: now))
        }

        return metrics
    }
}
