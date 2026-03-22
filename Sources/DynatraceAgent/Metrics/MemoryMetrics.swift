import Foundation
import Darwin

final class MemoryMetrics {
    func collect(hostname: String) -> [MetricPoint] {
        let dims = ["host.name": hostname]
        let now = Date()

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return [] }

        var pageSizeValue: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSizeValue)
        let pageSize = UInt64(pageSizeValue)
        let active = Double(UInt64(stats.active_count) * pageSize)
        let wired = Double(UInt64(stats.wire_count) * pageSize)
        let compressed = Double(UInt64(stats.compressor_page_count) * pageSize)
        let free = Double(UInt64(stats.free_count) * pageSize)
        let inactive = Double(UInt64(stats.inactive_count) * pageSize)

        let totalPhysical = Double(ProcessInfo.processInfo.physicalMemory)
        let used = active + wired + compressed
        let usagePct = used / totalPhysical * 100

        return [
            MetricPoint(key: "macos.memory.total", dimensions: dims, value: totalPhysical, timestamp: now),
            MetricPoint(key: "macos.memory.used", dimensions: dims, value: used, timestamp: now),
            MetricPoint(key: "macos.memory.free", dimensions: dims, value: free + inactive, timestamp: now),
            MetricPoint(key: "macos.memory.active", dimensions: dims, value: active, timestamp: now),
            MetricPoint(key: "macos.memory.wired", dimensions: dims, value: wired, timestamp: now),
            MetricPoint(key: "macos.memory.compressed", dimensions: dims, value: compressed, timestamp: now),
            MetricPoint(key: "macos.memory.usage", dimensions: dims, value: usagePct, timestamp: now),
        ]
    }
}
