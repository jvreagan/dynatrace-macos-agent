import Foundation
import IOKit.ps

final class BatteryMetrics {
    func collect(hostname: String) -> [MetricPoint] {
        let dims = ["host.name": hostname]
        let now = Date()
        var metrics: [MetricPoint] = []

        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return []
        }

        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let type = desc[kIOPSTypeKey] as? String,
                  type == kIOPSInternalBatteryType else { continue }

            if let capacity = desc[kIOPSCurrentCapacityKey] as? Int,
               let maxCapacity = desc[kIOPSMaxCapacityKey] as? Int,
               maxCapacity > 0 {
                metrics.append(MetricPoint(key: "macos.battery.level", dimensions: dims,
                    value: Double(capacity) / Double(maxCapacity) * 100, timestamp: now))
            }

            if let isCharging = desc[kIOPSIsChargingKey] as? Bool {
                metrics.append(MetricPoint(key: "macos.battery.charging", dimensions: dims,
                    value: isCharging ? 1 : 0, timestamp: now))
            }

            if let cycleCount = desc["Cycle Count"] as? Int {
                metrics.append(MetricPoint(key: "macos.battery.cycle_count", dimensions: dims,
                    value: Double(cycleCount), timestamp: now))
            }

            if let timeRemaining = desc[kIOPSTimeToEmptyKey] as? Int, timeRemaining > 0 {
                metrics.append(MetricPoint(key: "macos.battery.time_remaining_minutes", dimensions: dims,
                    value: Double(timeRemaining), timestamp: now))
            }
        }

        return metrics
    }
}
