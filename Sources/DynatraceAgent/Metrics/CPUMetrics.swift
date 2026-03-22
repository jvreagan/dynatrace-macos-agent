import Foundation
import Darwin

final class CPUMetrics {
    private var previousTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?

    func collect(hostname: String) -> [MetricPoint] {
        let dims = ["host.name": hostname]
        let now = Date()

        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )

        guard result == KERN_SUCCESS, let info = cpuInfo else {
            return []
        }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<Int32>.stride)
            )
        }

        var totalUser: UInt64 = 0
        var totalSystem: UInt64 = 0
        var totalIdle: UInt64 = 0
        var totalNice: UInt64 = 0

        for i in 0..<Int(numCPUs) {
            let offset = Int(CPU_STATE_MAX) * i
            totalUser += UInt64(info[offset + Int(CPU_STATE_USER)])
            totalSystem += UInt64(info[offset + Int(CPU_STATE_SYSTEM)])
            totalIdle += UInt64(info[offset + Int(CPU_STATE_IDLE)])
            totalNice += UInt64(info[offset + Int(CPU_STATE_NICE)])
        }

        var metrics: [MetricPoint] = []

        if let prev = previousTicks {
            let deltaUser = totalUser - prev.user
            let deltaSystem = totalSystem - prev.system
            let deltaIdle = totalIdle - prev.idle
            let deltaNice = totalNice - prev.nice
            let totalDelta = Double(deltaUser + deltaSystem + deltaIdle + deltaNice)

            if totalDelta > 0 {
                let userPct = Double(deltaUser + deltaNice) / totalDelta * 100
                let systemPct = Double(deltaSystem) / totalDelta * 100
                let idlePct = Double(deltaIdle) / totalDelta * 100
                let usagePct = userPct + systemPct

                metrics = [
                    MetricPoint(key: "macos.cpu.usage", dimensions: dims, value: usagePct, timestamp: now),
                    MetricPoint(key: "macos.cpu.user", dimensions: dims, value: userPct, timestamp: now),
                    MetricPoint(key: "macos.cpu.system", dimensions: dims, value: systemPct, timestamp: now),
                    MetricPoint(key: "macos.cpu.idle", dimensions: dims, value: idlePct, timestamp: now),
                ]
            }
        }

        previousTicks = (user: totalUser, system: totalSystem, idle: totalIdle, nice: totalNice)
        return metrics
    }
}
