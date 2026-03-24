import Foundation
import IOKit

final class DiskIOMetrics {
    private var previousStats: [String: (read: UInt64, written: UInt64)] = [:]

    func collect(hostname: String) -> [MetricPoint] {
        let now = Date()
        var metrics: [MetricPoint] = []

        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOBlockStorageDriver")
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
                  let stats = dict["Statistics"] as? [String: Any] else {
                service = IOIteratorNext(iterator)
                continue
            }

            let bytesRead = stats["Bytes (Read)"] as? UInt64 ?? 0
            let bytesWritten = stats["Bytes (Written)"] as? UInt64 ?? 0

            // Get device name from parent entry
            var parent: io_registry_entry_t = 0
            IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent)
            var nameBuf = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(parent, &nameBuf)
            IOObjectRelease(parent)
            let name = String(cString: nameBuf)

            let dims = ["host.name": hostname, "device": name]

            if let prev = previousStats[name] {
                let deltaRead = bytesRead >= prev.read ? bytesRead - prev.read : bytesRead
                let deltaWritten = bytesWritten >= prev.written ? bytesWritten - prev.written : bytesWritten
                metrics.append(MetricPoint(key: "macos.disk.io.read_bytes", dimensions: dims,
                    value: Double(deltaRead), timestamp: now))
                metrics.append(MetricPoint(key: "macos.disk.io.write_bytes", dimensions: dims,
                    value: Double(deltaWritten), timestamp: now))
            }

            previousStats[name] = (read: bytesRead, written: bytesWritten)
            service = IOIteratorNext(iterator)
        }

        return metrics
    }
}
