// Standalone smoke test - run with: swift Tests/SmokeTest.swift
// Verifies metric collection and MINT line serialization

import Foundation
import Darwin

// --- MetricPoint (copied for standalone test) ---
struct MetricPoint {
    let key: String
    let dimensions: [String: String]
    let value: Double
    let timestamp: UInt64

    init(key: String, dimensions: [String: String] = [:], value: Double, timestamp: Date = Date()) {
        self.key = key
        self.dimensions = dimensions
        self.value = value
        self.timestamp = UInt64(timestamp.timeIntervalSince1970 * 1000)
    }

    func toMINTLine() -> String {
        var line = key
        if !dimensions.isEmpty {
            let dims = dimensions
                .sorted { $0.key < $1.key }
                .map { "\(escapeDimensionKey($0.key))=\(escapeDimensionValue($0.value))" }
                .joined(separator: ",")
            line += ",\(dims)"
        }
        line += " gauge,\(formatValue(value)) \(timestamp)"
        return line
    }

    private func escapeDimensionKey(_ key: String) -> String {
        key.replacingOccurrences(of: " ", with: "_")
           .replacingOccurrences(of: ",", with: "_")
           .replacingOccurrences(of: "=", with: "_")
    }

    private func escapeDimensionValue(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        if escaped.contains(" ") || escaped.contains(",") || escaped.contains("=") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    private func formatValue(_ value: Double) -> String {
        if value == value.rounded() && value < 1e15 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }
}

// --- Tests ---
var passed = 0
var failed = 0

func assert(_ condition: Bool, _ message: String) {
    if condition {
        passed += 1
        print("  PASS: \(message)")
    } else {
        failed += 1
        print("  FAIL: \(message)")
    }
}

// 1. MINT line serialization
print("\n=== MINT Line Serialization ===")

let m1 = MetricPoint(key: "macos.cpu.usage", dimensions: ["host.name": "myhost"], value: 42.5)
let line1 = m1.toMINTLine()
assert(line1.hasPrefix("macos.cpu.usage,host.name=myhost gauge,42.50"), "Basic metric line: \(line1)")

let m2 = MetricPoint(key: "macos.memory.total", dimensions: [:], value: 17179869184)
let line2 = m2.toMINTLine()
assert(line2.hasPrefix("macos.memory.total gauge,17179869184"), "Large integer value: \(line2)")

let m3 = MetricPoint(key: "macos.disk.usage", dimensions: ["host.name": "my host", "device": "Macintosh HD"], value: 55.0)
let line3 = m3.toMINTLine()
assert(line3.contains("device=\"Macintosh HD\""), "Dimension value with space is quoted: \(line3)")
assert(line3.contains("host.name=\"my host\""), "Host with space is quoted: \(line3)")

let m4 = MetricPoint(key: "test.metric", dimensions: ["a": "1", "b": "2", "c": "3"], value: 100)
let line4 = m4.toMINTLine()
assert(line4.hasPrefix("test.metric,a=1,b=2,c=3 gauge,100"), "Dimensions sorted alphabetically: \(line4)")

// 2. CPU metrics (host_processor_info)
print("\n=== CPU Metrics ===")

func collectCPU() -> [MetricPoint] {
    var numCPUs: natural_t = 0
    var cpuInfo: processor_info_array_t?
    var numCPUInfo: mach_msg_type_number_t = 0
    let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &numCPUInfo)
    guard result == KERN_SUCCESS, let info = cpuInfo else { return [] }
    defer {
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                      vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<Int32>.stride))
    }
    var totalUser: UInt64 = 0, totalSystem: UInt64 = 0, totalIdle: UInt64 = 0, totalNice: UInt64 = 0
    for i in 0..<Int(numCPUs) {
        let offset = Int(CPU_STATE_MAX) * i
        totalUser += UInt64(info[offset + Int(CPU_STATE_USER)])
        totalSystem += UInt64(info[offset + Int(CPU_STATE_SYSTEM)])
        totalIdle += UInt64(info[offset + Int(CPU_STATE_IDLE)])
        totalNice += UInt64(info[offset + Int(CPU_STATE_NICE)])
    }
    let total = Double(totalUser + totalSystem + totalIdle + totalNice)
    assert(total > 0, "CPU ticks total > 0: \(total)")
    assert(numCPUs > 0, "Found \(numCPUs) CPUs")
    return [] // Just testing the syscall works
}
collectCPU()

// 3. Memory metrics (host_statistics64)
print("\n=== Memory Metrics ===")

func collectMemory() {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &stats) { ptr in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
            host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
        }
    }
    assert(result == KERN_SUCCESS, "host_statistics64 succeeded")

    var pageSizeValue: vm_size_t = 0
    host_page_size(mach_host_self(), &pageSizeValue)
    let pageSize = UInt64(pageSizeValue)
    assert(pageSize > 0, "Page size: \(pageSize)")

    let active = UInt64(stats.active_count) * pageSize
    let wired = UInt64(stats.wire_count) * pageSize
    let compressed = UInt64(stats.compressor_page_count) * pageSize
    let free = UInt64(stats.free_count) * pageSize
    let totalPhysical = ProcessInfo.processInfo.physicalMemory

    assert(active > 0, "Active memory: \(active / 1024 / 1024) MB")
    assert(wired > 0, "Wired memory: \(wired / 1024 / 1024) MB")
    assert(totalPhysical > 0, "Total physical: \(totalPhysical / 1024 / 1024) MB")

    let used = active + wired + compressed
    let usagePct = Double(used) / Double(totalPhysical) * 100
    assert(usagePct > 0 && usagePct <= 100, "Memory usage: \(String(format: "%.1f", usagePct))%")
}
collectMemory()

// 4. Disk metrics (FileManager)
print("\n=== Disk Metrics ===")

func collectDisk() {
    let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey,
                                      .volumeAvailableCapacityForImportantUsageKey,
                                      .volumeIsLocalKey, .volumeIsInternalKey]
    guard let volumes = FileManager.default.mountedVolumeURLs(
        includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) else {
        assert(false, "Failed to get mounted volumes")
        return
    }
    assert(!volumes.isEmpty, "Found \(volumes.count) volumes")

    var foundInternal = false
    for volume in volumes {
        guard let values = try? volume.resourceValues(forKeys: keys),
              values.volumeIsLocal == true, values.volumeIsInternal == true,
              let name = values.volumeName, let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { continue }
        foundInternal = true
        let totalGB = Double(total) / 1e9
        let availGB = Double(available) / 1e9
        assert(total > 0, "Disk '\(name)': \(String(format: "%.1f", totalGB)) GB total, \(String(format: "%.1f", availGB)) GB available")
    }
    assert(foundInternal, "Found at least one internal volume")
}
collectDisk()

// 5. Network metrics (getifaddrs)
print("\n=== Network Metrics ===")

func collectNetwork() {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    let result = getifaddrs(&ifaddr)
    assert(result == 0, "getifaddrs succeeded")
    guard result == 0, let firstAddr = ifaddr else { return }
    defer { freeifaddrs(ifaddr) }

    var interfaces: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
    while let addr = cursor {
        let name = String(cString: addr.pointee.ifa_name)
        if addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK) && name != "lo0" {
            let data = unsafeBitCast(addr.pointee.ifa_data, to: UnsafeMutablePointer<if_data>.self)
            let bytesIn = UInt64(data.pointee.ifi_ibytes)
            let bytesOut = UInt64(data.pointee.ifi_obytes)
            let existing = interfaces[name] ?? (0, 0)
            interfaces[name] = (existing.bytesIn + bytesIn, existing.bytesOut + bytesOut)
        }
        cursor = addr.pointee.ifa_next
    }
    assert(!interfaces.isEmpty, "Found \(interfaces.count) network interfaces")
    for (name, bytes) in interfaces.sorted(by: { $0.key < $1.key }) {
        print("    \(name): in=\(bytes.bytesIn / 1024)KB out=\(bytes.bytesOut / 1024)KB")
    }
}
collectNetwork()

// 6. Load averages
print("\n=== Load Averages ===")

func collectLoad() {
    var loadavg = [Double](repeating: 0, count: 3)
    let count = getloadavg(&loadavg, 3)
    assert(count == 3, "getloadavg returned 3 values")
    assert(loadavg[0] >= 0, "Load 1m: \(String(format: "%.2f", loadavg[0]))")
    assert(loadavg[1] >= 0, "Load 5m: \(String(format: "%.2f", loadavg[1]))")
    assert(loadavg[2] >= 0, "Load 15m: \(String(format: "%.2f", loadavg[2]))")
}
collectLoad()

// 7. Swap
print("\n=== Swap Metrics ===")

func collectSwap() {
    var swapUsage = xsw_usage()
    var size = MemoryLayout<xsw_usage>.size
    let result = sysctlbyname("vm.swapusage", &swapUsage, &size, nil, 0)
    assert(result == 0, "sysctlbyname vm.swapusage succeeded")
    let totalMB = Double(swapUsage.xsu_total) / 1e6
    let usedMB = Double(swapUsage.xsu_used) / 1e6
    assert(swapUsage.xsu_total >= 0, "Swap total: \(String(format: "%.0f", totalMB)) MB, used: \(String(format: "%.0f", usedMB)) MB")
}
collectSwap()

// Summary
print("\n=== Results ===")
print("\(passed) passed, \(failed) failed")
if failed > 0 {
    exit(1)
}
