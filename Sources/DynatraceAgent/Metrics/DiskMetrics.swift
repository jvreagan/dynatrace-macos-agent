import Foundation

final class DiskMetrics {
    func collect(hostname: String) -> [MetricPoint] {
        let now = Date()
        var metrics: [MetricPoint] = []

        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsLocalKey,
            .volumeIsInternalKey
        ]

        guard let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]
        ) else {
            return []
        }

        for volume in volumes {
            guard let values = try? volume.resourceValues(forKeys: keys),
                  values.volumeIsLocal == true,
                  values.volumeIsInternal == true,
                  let name = values.volumeName,
                  let total = values.volumeTotalCapacity,
                  let available = values.volumeAvailableCapacityForImportantUsage else {
                continue
            }

            let totalBytes = Double(total)
            let availableBytes = Double(available)
            let usedBytes = totalBytes - availableBytes
            let usagePct = totalBytes > 0 ? usedBytes / totalBytes * 100 : 0

            let dims: [String: String] = [
                "host.name": hostname,
                "device": name
            ]

            metrics.append(contentsOf: [
                MetricPoint(key: "macos.disk.total", dimensions: dims, value: totalBytes, timestamp: now),
                MetricPoint(key: "macos.disk.used", dimensions: dims, value: usedBytes, timestamp: now),
                MetricPoint(key: "macos.disk.available", dimensions: dims, value: availableBytes, timestamp: now),
                MetricPoint(key: "macos.disk.usage", dimensions: dims, value: usagePct, timestamp: now),
            ])
        }

        return metrics
    }
}
