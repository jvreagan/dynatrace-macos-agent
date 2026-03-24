import Foundation
import IOKit

final class GPUMetrics {
    func collect(hostname: String) -> [MetricPoint] {
        let dims = ["host.name": hostname]
        let now = Date()
        var metrics: [MetricPoint] = []

        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }

            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let perfStats = dict["PerformanceStatistics"] as? [String: Any] else {
                service = IOIteratorNext(iterator)
                continue
            }

            if let utilization = perfStats["Device Utilization %"] as? Int {
                metrics.append(MetricPoint(key: "macos.gpu.usage", dimensions: dims,
                    value: Double(utilization), timestamp: now))
            }

            if let memUsed = perfStats["vramUsedBytes"] as? UInt64 {
                metrics.append(MetricPoint(key: "macos.gpu.vram_used_bytes", dimensions: dims,
                    value: Double(memUsed), timestamp: now))
            }

            if let memFree = perfStats["vramFreeBytes"] as? UInt64 {
                metrics.append(MetricPoint(key: "macos.gpu.vram_free_bytes", dimensions: dims,
                    value: Double(memFree), timestamp: now))
            }

            service = IOIteratorNext(iterator)
        }

        return metrics
    }
}
