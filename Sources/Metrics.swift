// Metriche di sistema: CPU, memoria, rete, disco, GPU, sensori, batteria.
// Ogni lettore tiene il campione precedente e calcola la differenza tra due chiamate.
import Foundation
import IOKit
import IOKit.ps
import Darwin

// ================================================================ CPU
final class CPUReader {
    private var previous: [(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)] = []
    private(set) var perCore: [Double] = []      // 0...1
    private(set) var user = 0.0, system = 0.0    // 0...1 sul totale
    var total: Double { perCore.isEmpty ? 0 : min(1, user + system) }
    let coreCount = ProcessInfo.processInfo.activeProcessorCount
    lazy var performanceCores: Int = sysctlInt("hw.perflevel0.logicalcpu") ?? coreCount
    lazy var efficiencyCores: Int = sysctlInt("hw.perflevel1.logicalcpu") ?? 0

    func sample() {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)) }
        var now: [(UInt64, UInt64, UInt64, UInt64)] = []
        for i in 0..<Int(count) {
            let b = Int(CPU_STATE_MAX) * i
            now.append((UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_USER)])),
                        UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_SYSTEM)])),
                        UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_IDLE)])),
                        UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_NICE)]))))
        }
        if previous.count == now.count {
            var cores: [Double] = [], u = 0.0, s = 0.0, all = 0.0
            for (p, n) in zip(previous, now) {
                let du = Double(n.0 &- p.user), ds = Double(n.1 &- p.system)
                let di = Double(n.2 &- p.idle), dn = Double(n.3 &- p.nice)
                let t = du + ds + di + dn
                cores.append(t > 0 ? (du + ds + dn) / t : 0)
                u += du + dn; s += ds; all += t
            }
            perCore = cores
            user = all > 0 ? u / all : 0; system = all > 0 ? s / all : 0
        }
        previous = now.map { (user: $0.0, system: $0.1, idle: $0.2, nice: $0.3) }
    }
}

func sysctlInt(_ name: String) -> Int? {
    var v: Int64 = 0, size = MemoryLayout<Int64>.size
    if sysctlbyname(name, &v, &size, nil, 0) == 0 { return size == 4 ? Int(Int32(truncatingIfNeeded: v)) : Int(v) }
    return nil
}

func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buf = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
    return String(cString: buf)
}

// ================================================================ memoria
struct MemoryInfo {
    var total: UInt64 = ProcessInfo.processInfo.physicalMemory
    var used: UInt64 = 0          // app + wired + compressa (come Monitoraggio Attività)
    var app: UInt64 = 0, wired: UInt64 = 0, compressed: UInt64 = 0, cached: UInt64 = 0
    var swapUsed: UInt64 = 0
    var pressure: Pressure = .normal
    enum Pressure: Int { case normal = 1, warning = 2, critical = 4 }
    var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func read() -> MemoryInfo {
        var m = MemoryInfo()
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        if kr == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            let internalPages = UInt64(stats.internal_page_count), purgeable = UInt64(stats.purgeable_count)
            m.app = (internalPages > purgeable ? internalPages - purgeable : 0) * page
            m.wired = UInt64(stats.wire_count) * page
            m.compressed = UInt64(stats.compressor_page_count) * page
            m.cached = (UInt64(stats.external_page_count) + purgeable) * page
            m.used = m.app + m.wired + m.compressed
        }
        var swap = xsw_usage(), size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 { m.swapUsed = swap.xsu_used }
        if let p = sysctlInt("kern.memorystatus_vm_pressure_level"), let pr = Pressure(rawValue: p) { m.pressure = pr }
        return m
    }
}

// ================================================================ rete
struct InterfaceStats { var name: String; var rx: UInt64; var tx: UInt64 }

final class NetworkReader {
    private var previous: [String: (UInt64, UInt64)] = [:]
    private var previousAt = Date()
    private(set) var down = 0.0, up = 0.0                 // byte/s, tutte le interfacce fisiche
    private(set) var perInterface: [String: (down: Double, up: Double)] = [:]
    private(set) var totalRx: UInt64 = 0, totalTx: UInt64 = 0

    func sample() {
        var now: [String: (UInt64, UInt64)] = [:]
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return }
        defer { freeifaddrs(ifap) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = p {
            defer { p = ifa.pointee.ifa_next }
            guard let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = ifa.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            let name = String(cString: ifa.pointee.ifa_name)
            // solo interfacce "vere": Ethernet/Wi-Fi (en*), tethering, VPN (utun) esclusi per non contare due volte
            guard name.hasPrefix("en") || name.hasPrefix("pdp_ip") else { continue }
            now[name] = (UInt64(data.pointee.ifi_ibytes), UInt64(data.pointee.ifi_obytes))
        }
        let dt = max(Date().timeIntervalSince(previousAt), 0.1)
        var d = 0.0, u = 0.0, per: [String: (Double, Double)] = [:]
        for (name, (rx, tx)) in now {
            if let (prx, ptx) = previous[name] {
                // i contatori sono a 32 bit su alcune interfacce: gestisce il riavvolgimento
                let drx = rx >= prx ? rx - prx : rx &+ (UInt64(UInt32.max) - prx)
                let dtx = tx >= ptx ? tx - ptx : tx &+ (UInt64(UInt32.max) - ptx)
                per[name] = (Double(drx) / dt, Double(dtx) / dt)
                d += Double(drx) / dt; u += Double(dtx) / dt
            }
        }
        down = d; up = u; perInterface = per.mapValues { (down: $0.0, up: $0.1) }
        totalRx = now.values.reduce(0) { $0 + $1.0 }; totalTx = now.values.reduce(0) { $0 + $1.1 }
        previous = now; previousAt = Date()
    }
}

// Indirizzo IP e nome della rete attiva (per la scheda Rete)
func primaryAddresses() -> [(iface: String, ip: String)] {
    var out: [(String, String)] = []
    var ifap: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifap) == 0, let first = ifap else { return [] }
    defer { freeifaddrs(ifap) }
    var p: UnsafeMutablePointer<ifaddrs>? = first
    while let ifa = p {
        defer { p = ifa.pointee.ifa_next }
        guard let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
              (ifa.pointee.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
        let name = String(cString: ifa.pointee.ifa_name)
        guard name.hasPrefix("en") else { continue }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
            out.append((name, String(cString: host)))
        }
    }
    return out
}

// ================================================================ disco
struct DiskInfo {
    var total: Int64 = 0, free: Int64 = 0
    var fraction: Double { total > 0 ? Double(total - free) / Double(total) : 0 }
    static func read() -> DiskInfo {
        let url = URL(fileURLWithPath: "/")
        let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        return DiskInfo(total: Int64(v?.volumeTotalCapacity ?? 0), free: v?.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}

// ================================================================ GPU (IOAccelerator, API pubblica)
func gpuUtilization() -> Double? {
    var iter: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(iter) }
    var best: Double?
    while case let s = IOIteratorNext(iter), s != 0 {
        defer { IOObjectRelease(s) }
        if let stats = IORegistryEntryCreateCFProperty(s, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any],
           let u = (stats["Device Utilization %"] ?? stats["GPU Activity(%)"]) as? NSNumber {
            best = max(best ?? 0, u.doubleValue / 100)
        }
    }
    return best
}

// ================================================================ sensori (sperimentale)
struct SensorReading: Identifiable { var id: String { name }; let name: String; let value: Double }

struct SensorInfo {
    var temperatures: [SensorReading] = []
    var fans: [(actual: Double, min: Double, max: Double)] = []
    var systemPower: Double?            // W (PSTR)
    // Temperatura "del chip": media dei sensori del die della CPU
    var socTemperature: Double? {
        let die = temperatures.filter { $0.name.contains("tdie") || $0.name.hasPrefix("pACC") || $0.name.hasPrefix("eACC") }
        let src = die.isEmpty ? temperatures.filter { !$0.name.contains("NAND") && !$0.name.contains("Battery") } : die
        return src.isEmpty ? nil : src.map(\.value).max()
    }
    var ssdTemperature: Double? { temperatures.first { $0.name.contains("NAND") }?.value }
    var batteryTemperature: Double? { temperatures.first { $0.name.lowercased().contains("battery") || $0.name.contains("gas gauge") }?.value }

    static func read(fans readFans: Bool = true) -> SensorInfo {
        var s = SensorInfo()
        if let arr = ms_copy_temperatures() as? [[String: Any]] {
            s.temperatures = arr.compactMap { d in
                guard let n = d["name"] as? String, let v = d["value"] as? Double else { return nil }
                return SensorReading(name: n, value: v)
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        guard readFans else { return s }
        var n = 0.0
        if ms_smc_read_number("FNum", &n) == 0, n > 0 {
            for i in 0..<Int(n) {
                var a = 0.0, mn = 0.0, mx = 0.0
                _ = ms_smc_read_number("F\(i)Ac", &a); _ = ms_smc_read_number("F\(i)Mn", &mn); _ = ms_smc_read_number("F\(i)Mx", &mx)
                s.fans.append((a, mn, mx))
            }
        }
        var p = 0.0
        if ms_smc_read_number("PSTR", &p) == 0, p > 0 { s.systemPower = p }
        return s
    }
}

// ================================================================ batteria
struct BatteryInfo {
    var percent: Double            // 0...1
    var charging: Bool
    var onAC: Bool
    var minutesLeft: Int?
    static func read() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let charging = d[kIOPSIsChargingKey] as? Bool ?? false
            let tte = d[kIOPSTimeToEmptyKey] as? Int, ttf = d[kIOPSTimeToFullChargeKey] as? Int
            let left = charging ? ttf : tte
            return BatteryInfo(percent: Double(cur) / Double(max), charging: charging,
                               onAC: (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue,
                               minutesLeft: (left ?? -1) > 0 ? left : nil)
        }
        return nil
    }
}

// ================================================================ varie
var systemUptime: TimeInterval {
    var tv = timeval(), size = MemoryLayout<timeval>.size
    guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 else { return ProcessInfo.processInfo.systemUptime }
    return Date().timeIntervalSince1970 - Double(tv.tv_sec)
}

var chipName: String {
    sysctlString("machdep.cpu.brand_string")?.replacingOccurrences(of: "Apple ", with: "") ?? "Mac"
}

// Utilizzo di questo stesso processo (per il piè di pagina "self")
final class SelfUsage {
    private var lastCPU: Double = 0, lastAt = Date()
    private(set) var cpu = 0.0
    var memory: UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }
    func sample() {
        var r = rusage(); getrusage(RUSAGE_SELF, &r)
        let t = Double(r.ru_utime.tv_sec) + Double(r.ru_utime.tv_usec) / 1e6 + Double(r.ru_stime.tv_sec) + Double(r.ru_stime.tv_usec) / 1e6
        let now = Date(), dt = now.timeIntervalSince(lastAt)
        if dt > 0 && lastCPU > 0 { cpu = (t - lastCPU) / dt }
        lastCPU = t; lastAt = now
    }
}
