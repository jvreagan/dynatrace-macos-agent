// End-to-end test: collect real metrics → format as MINT → POST to Dynatrace
import Foundation
import Darwin

let dtURL = ProcessInfo.processInfo.environment["DT_URL"] ?? "https://YOUR_ENV.live.dynatrace.com/api/v2/metrics/ingest"
let dtToken = ProcessInfo.processInfo.environment["DT_API_TOKEN"] ?? ""
let hostname = Host.current().localizedName ?? "unknown"
let now = UInt64(Date().timeIntervalSince1970 * 1000)

var lines: [String] = []

func quoteDimValue(_ v: String) -> String {
    let escaped = v.replacingOccurrences(of: "\\", with: "\\\\")
                   .replacingOccurrences(of: "\"", with: "\\\"")
    let needsQuoting = escaped.contains { c in
        !(c.isASCII && (c.isLetter || c.isNumber || c == "_" || c == "." || c == "/" || c == "-"))
    }
    return needsQuoting ? "\"\(escaped)\"" : escaped
}

func addMetric(_ key: String, _ value: Double, extraDims: [String: String] = [:]) {
    var dims = "host.name=\(quoteDimValue(hostname))"
    for (k, v) in extraDims.sorted(by: { $0.key < $1.key }) {
        dims += ",\(k)=\(quoteDimValue(v))"
    }
    let formatted = value == value.rounded() && value < 1e15
        ? String(format: "%.0f", value)
        : String(format: "%.2f", value)
    lines.append("\(key),\(dims) gauge,\(formatted) \(now)")
}

// --- CPU ---
var numCPUs: natural_t = 0
var cpuInfo: processor_info_array_t?
var numCPUInfo: mach_msg_type_number_t = 0
if host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &numCPUInfo) == KERN_SUCCESS,
   let info = cpuInfo {
    var user: UInt64 = 0, sys: UInt64 = 0, idle: UInt64 = 0, nice: UInt64 = 0
    for i in 0..<Int(numCPUs) {
        let off = Int(CPU_STATE_MAX) * i
        user += UInt64(info[off + Int(CPU_STATE_USER)])
        sys += UInt64(info[off + Int(CPU_STATE_SYSTEM)])
        idle += UInt64(info[off + Int(CPU_STATE_IDLE)])
        nice += UInt64(info[off + Int(CPU_STATE_NICE)])
    }
    let total = Double(user + sys + idle + nice)
    if total > 0 {
        addMetric("macos.cpu.user", Double(user + nice) / total * 100)
        addMetric("macos.cpu.system", Double(sys) / total * 100)
        addMetric("macos.cpu.idle", Double(idle) / total * 100)
        addMetric("macos.cpu.usage", Double(user + nice + sys) / total * 100)
    }
    vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                  vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<Int32>.stride))
}

// --- Memory ---
var vmStats = vm_statistics64()
var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
let vmResult = withUnsafeMutablePointer(to: &vmStats) { ptr in
    ptr.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { intPtr in
        host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &vmCount)
    }
}
if vmResult == KERN_SUCCESS {
    var pageSize: vm_size_t = 0
    host_page_size(mach_host_self(), &pageSize)
    let ps = UInt64(pageSize)
    let active = Double(UInt64(vmStats.active_count) * ps)
    let wired = Double(UInt64(vmStats.wire_count) * ps)
    let compressed = Double(UInt64(vmStats.compressor_page_count) * ps)
    let free = Double(UInt64(vmStats.free_count) * ps)
    let inactive = Double(UInt64(vmStats.inactive_count) * ps)
    let totalPhysical = Double(ProcessInfo.processInfo.physicalMemory)
    let used = active + wired + compressed
    addMetric("macos.memory.total", totalPhysical)
    addMetric("macos.memory.used", used)
    addMetric("macos.memory.free", free + inactive)
    addMetric("macos.memory.active", active)
    addMetric("macos.memory.wired", wired)
    addMetric("macos.memory.compressed", compressed)
    addMetric("macos.memory.usage", used / totalPhysical * 100)
}

// --- Disk ---
let diskKeys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey,
    .volumeAvailableCapacityForImportantUsageKey, .volumeIsLocalKey, .volumeIsInternalKey]
if let volumes = FileManager.default.mountedVolumeURLs(
    includingResourceValuesForKeys: Array(diskKeys), options: [.skipHiddenVolumes]) {
    for vol in volumes {
        guard let v = try? vol.resourceValues(forKeys: diskKeys),
              v.volumeIsLocal == true, v.volumeIsInternal == true,
              let name = v.volumeName, let total = v.volumeTotalCapacity,
              let avail = v.volumeAvailableCapacityForImportantUsage else { continue }
        let t = Double(total), a = Double(avail), u = t - a
        addMetric("macos.disk.total", t, extraDims: ["device": name])
        addMetric("macos.disk.used", u, extraDims: ["device": name])
        addMetric("macos.disk.available", a, extraDims: ["device": name])
        addMetric("macos.disk.usage", u / t * 100, extraDims: ["device": name])
    }
}

// --- Load ---
var loadavg = [Double](repeating: 0, count: 3)
if getloadavg(&loadavg, 3) == 3 {
    addMetric("macos.load.1m", loadavg[0])
    addMetric("macos.load.5m", loadavg[1])
    addMetric("macos.load.15m", loadavg[2])
}

// --- Swap ---
var swapUsage = xsw_usage()
var swapSize = MemoryLayout<xsw_usage>.size
if sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0) == 0 {
    let total = Double(swapUsage.xsu_total)
    let used = Double(swapUsage.xsu_used)
    addMetric("macos.swap.total", total)
    addMetric("macos.swap.used", used)
    addMetric("macos.swap.usage", total > 0 ? used / total * 100 : 0)
}

// --- Send to Dynatrace ---
let body = lines.joined(separator: "\n")
print("Sending \(lines.count) metrics to Dynatrace...\n")
for line in lines {
    print("  \(line)")
}
print("")

var request = URLRequest(url: URL(string: dtURL)!)
request.httpMethod = "POST"
request.setValue("Api-Token \(dtToken)", forHTTPHeaderField: "Authorization")
request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
request.httpBody = body.data(using: .utf8)

let sem = DispatchSemaphore(value: 0)
let task = URLSession.shared.dataTask(with: request) { data, response, error in
    if let error = error {
        print("ERROR: \(error.localizedDescription)")
    } else if let http = response as? HTTPURLResponse {
        let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        print("HTTP \(http.statusCode): \(body)")
        if http.statusCode == 202 {
            print("\nMetrics accepted by Dynatrace!")
            print("View them in Data Explorer: Explore data → filter by 'macos.'")
        }
    }
    sem.signal()
}
task.resume()
sem.wait()
