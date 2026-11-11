// Storico lungo (1 h / 24 h) salvato su disco, totali di rete per giorno, periferiche Bluetooth,
// Wi-Fi, VPN e test di velocita'.
import Foundation
import CoreWLAN

// ================================================================ storico al minuto
struct MinuteSample: Codable {
    var t: Date
    var cpu: Double
    var mem: Double
    var down: Double        // byte/s medi
    var up: Double
    var temp: Double?
}

final class HistoryStore {
    static let shared = HistoryStore()
    private(set) var minutes: [MinuteSample] = []
    var daily: [String: [Double]] = [:]        // "2026-11-11" -> [byte ricevuti, byte inviati]
    private var acc = (cpu: 0.0, mem: 0.0, down: 0.0, up: 0.0, temp: 0.0, tempN: 0, n: 0)
    private var minuteStart = Date()
    private var lastSave = Date()
    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MenuStats")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()
    private let dayFormat: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()

    private struct Saved: Codable { var minutes: [MinuteSample]; var daily: [String: [Double]] }

    init() {
        guard !Monitor.demoMode, let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Saved.self, from: d) else { return }
        minutes = s.minutes.filter { Date().timeIntervalSince($0.t) < 86_400 }
        daily = s.daily
    }

    // Chiamato a ogni campione: accumula e chiude un minuto quando e' passato
    func add(cpu: Double, mem: Double, down: Double, up: Double, temp: Double?, dt: Double) {
        acc.cpu += cpu; acc.mem += mem; acc.down += down; acc.up += up; acc.n += 1
        if let temp { acc.temp += temp; acc.tempN += 1 }
        let day = dayFormat.string(from: Date())
        var d = daily[day] ?? [0, 0]
        d[0] += down * dt; d[1] += up * dt
        daily[day] = d
        if Date().timeIntervalSince(minuteStart) >= 60, acc.n > 0 {
            let n = Double(acc.n)
            minutes.append(MinuteSample(t: Date(), cpu: acc.cpu / n, mem: acc.mem / n, down: acc.down / n, up: acc.up / n,
                                        temp: acc.tempN > 0 ? acc.temp / Double(acc.tempN) : nil))
            if minutes.count > 1440 { minutes.removeFirst(minutes.count - 1440) }
            acc = (0, 0, 0, 0, 0, 0, 0)
            minuteStart = Date()
        }
        if Date().timeIntervalSince(lastSave) > 300 { save() }
    }

    func save() {
        guard !Monitor.demoMode else { return }
        lastSave = Date()
        // tiene al massimo ~13 mesi di totali giornalieri
        if daily.count > 400 { for k in daily.keys.sorted().prefix(daily.count - 400) { daily[k] = nil } }
        if let d = try? JSONEncoder().encode(Saved(minutes: minutes, daily: daily)) { try? d.write(to: url, options: .atomic) }
    }

    // Serie per i grafici: ultima ora (al minuto) o 24 ore (medie di 10 minuti)
    func series(_ key: KeyPath<MinuteSample, Double>, hours: Int) -> [Double] {
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        let pts = minutes.filter { $0.t >= cutoff }.map { $0[keyPath: key] }
        guard hours > 1, pts.count > 144 else { return pts }
        let step = Int(ceil(Double(pts.count) / 144))
        return stride(from: 0, to: pts.count, by: step).map { i in
            let chunk = pts[i..<min(i + step, pts.count)]
            return chunk.reduce(0, +) / Double(chunk.count)
        }
    }

    var today: (rx: Double, tx: Double) {
        let d = daily[dayFormat.string(from: Date())] ?? [0, 0]
        return (d[0], d[1])
    }
    var thisMonth: (rx: Double, tx: Double) {
        let prefix = String(dayFormat.string(from: Date()).prefix(7))
        return daily.filter { $0.key.hasPrefix(prefix) }.values.reduce((0.0, 0.0)) { ($0.0 + $1[0], $0.1 + $1[1]) }
    }
}

// ================================================================ periferiche Bluetooth
struct Peripheral: Identifiable {
    var id: String { name + (part ?? "") }
    let name: String
    let part: String?           // "sinistra", "destra", "custodia" per gli auricolari
    let percent: Double
}

func readPeripherals() -> [Peripheral] {
    var out: [Peripheral] = []
    // Mouse, tastiere e trackpad Apple: chiave BatteryPercent nel registro IOKit
    if let io = run("/usr/sbin/ioreg", ["-r", "-l", "-k", "BatteryPercent"], timeout: 3) {
        var name: String?
        for line in io.split(separator: "\n") {
            if line.contains("\"Product\" = ") { name = line.components(separatedBy: "= ").last?.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) }
            if line.contains("\"BatteryPercent\" = "), let v = Double(line.components(separatedBy: "= ").last?.trimmingCharacters(in: .whitespaces) ?? ""),
               let n = name {
                out.append(Peripheral(name: n, part: nil, percent: v / 100)); name = nil
            }
        }
    }
    // Auricolari e cuffie: livelli riportati da system_profiler (es. AirPods: sinistra/destra/custodia)
    if let sp = run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"], timeout: 8),
       let json = try? JSONSerialization.jsonObject(with: Data(sp.utf8)) as? [String: Any],
       let controllers = json["SPBluetoothDataType"] as? [[String: Any]] {
        let parts: [(String, String?)] = [("device_batteryLevelMain", nil), ("device_batteryLevelLeft", L("sinistra")),
                                          ("device_batteryLevelRight", L("destra")), ("device_batteryLevelCase", L("custodia"))]
        for c in controllers {
            for dev in (c["device_connected"] as? [[String: Any]]) ?? [] {
                for (name, v) in dev {
                    guard let info = v as? [String: Any], !out.contains(where: { $0.name == name }) else { continue }
                    for (key, part) in parts {
                        if let s = info[key] as? String, let p = Double(s.replacingOccurrences(of: "%", with: "")) {
                            out.append(Peripheral(name: name, part: part, percent: p / 100))
                        }
                    }
                }
            }
        }
    }
    return out
}

// ================================================================ Wi-Fi e VPN
struct WiFiInfo {
    var ssid: String?           // nil se macOS non lo concede (serve il permesso Posizione)
    var rssi: Int
    var noise: Int
    var txRate: Double          // Mbit/s
    var band: String?
    var quality: Double { min(max(Double(rssi + 90) / 50, 0), 1) }    // -90 dBm = 0, -40 dBm = 1
}

func readWiFi() -> WiFiInfo? {
    guard let i = CWWiFiClient.shared().interface(), i.powerOn(), i.rssiValue() != 0 else { return nil }
    var band: String?
    switch i.wlanChannel()?.channelBand {
    case .band2GHz: band = "2,4 GHz"
    case .band5GHz: band = "5 GHz"
    case .band6GHz: band = "6 GHz"
    default: band = nil
    }
    return WiFiInfo(ssid: i.ssid(), rssi: i.rssiValue(), noise: i.noiseMeasurement(), txRate: i.transmitRate(), band: band)
}

// Interfacce VPN attive: tunnel (utun, ipsec, ppp) con un indirizzo IPv4
func activeVPNs() -> [(iface: String, ip: String)] {
    var out: [(String, String)] = []
    var ifap: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifap) == 0, let first = ifap else { return [] }
    defer { freeifaddrs(ifap) }
    var p: UnsafeMutablePointer<ifaddrs>? = first
    while let ifa = p {
        defer { p = ifa.pointee.ifa_next }
        guard let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
        let name = String(cString: ifa.pointee.ifa_name)
        guard name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") else { continue }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
            out.append((name, String(cString: host)))
        }
    }
    return out
}

// ================================================================ test di velocita' (networkQuality, incluso in macOS)
struct SpeedResult { let down: Double; let up: Double; let responsiveness: Double?; let date: Date }   // bit/s, RPM

func runSpeedTest() -> SpeedResult? {
    guard let out = run("/usr/bin/networkQuality", ["-c"], timeout: 60),
          let json = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any],
          let dl = json["dl_throughput"] as? Double, let ul = json["ul_throughput"] as? Double else { return nil }
    let rpm = (json["responsiveness"] as? Double) ?? (json["dl_responsiveness"] as? Double)
    return SpeedResult(down: dl, up: ul, responsiveness: rpm, date: Date())
}

func formatBits(_ bps: Double) -> String {
    bps >= 1_000_000_000 ? String(format: "%.2f Gbit/s", bps / 1e9) : String(format: "%.0f Mbit/s", bps / 1e6)
}
