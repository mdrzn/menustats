// Processi via libproc: CPU% (delta del tempo CPU), memoria (phys_footprint, come Monitoraggio
// Attività), raggruppati per l'app (.app piu' esterna nel percorso) a cui appartengono.
import AppKit
import Darwin
import Security

struct ProcessSample: Identifiable, Hashable {
    let pid: pid_t
    var id: pid_t { pid }
    let ppid: pid_t
    let name: String
    let path: String
    var cpu: Double          // % di un core (100 = un core pieno)
    var memory: UInt64
    var threads: Int
    var cpuTime: Double      // secondi totali
    let startedAt: Date
}

struct AppGroup: Identifiable {
    var id: String { key }
    let key: String          // percorso dell'app o nome del processo
    let name: String
    let bundlePath: String?
    var processes: [ProcessSample]
    var cpu: Double { processes.reduce(0) { $0 + $1.cpu } }
    var memory: UInt64 { processes.reduce(0) { $0 + $1.memory } }
    var mainPID: pid_t { processes.min { $0.pid < $1.pid }?.pid ?? 0 }
}

final class ProcessReader {
    private var previous: [pid_t: (time: Double, at: Double)] = [:]
    private static let timebase: Double = {
        var tb = mach_timebase_info(); mach_timebase_info(&tb)
        return Double(tb.numer) / Double(tb.denom) / 1e9      // tick mach -> secondi
    }()
    private var nameCache: [String: String] = [:]

    func sample() -> [ProcessSample] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(n) + 64)
        let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        let now = ProcessInfo.processInfo.systemUptime
        var out: [ProcessSample] = []
        var seen: [pid_t: (Double, Double)] = [:]
        for pid in pids.prefix(Int(got)) where pid > 0 {
            var ru = rusage_info_v4()
            let ok = withUnsafeMutablePointer(to: &ru) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            guard ok == 0 else { continue }       // processi di altri utenti: non leggibili senza root
            var bsd = proc_bsdinfo()
            let bsdSize = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, Int32(MemoryLayout<proc_bsdinfo>.size))
            var task = proc_taskinfo()
            let taskSize = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, Int32(MemoryLayout<proc_taskinfo>.size))
            let cpuTime = Double(ru.ri_user_time + ru.ri_system_time) * Self.timebase
            var cpu = 0.0
            if let p = previous[pid], now > p.at { cpu = max(0, (cpuTime - p.time) / (now - p.at) * 100) }
            seen[pid] = (cpuTime, now)
            let path = Self.path(pid)
            var name = withUnsafeBytes(of: bsd.pbi_name) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            // alcuni CLI installano binari chiamati come la versione (es. claude -> versions/2.1.314)
            if name.isEmpty || name.allSatisfy({ $0.isNumber || $0 == "." }) {
                let comm = withUnsafeBytes(of: bsd.pbi_comm) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
                name = comm.isEmpty || comm.allSatisfy({ $0.isNumber || $0 == "." }) ? (path as NSString).lastPathComponent : comm
            }
            if path.contains("/claude/versions/") { name = "Claude Code" }
            out.append(ProcessSample(pid: pid, ppid: bsdSize > 0 ? pid_t(bsd.pbi_ppid) : 0, name: name, path: path,
                                     cpu: cpu, memory: ru.ri_phys_footprint,
                                     threads: taskSize > 0 ? Int(task.pti_threadnum) : 0, cpuTime: cpuTime,
                                     startedAt: Date(timeIntervalSince1970: Double(bsd.pbi_start_tvsec))))
        }
        previous = seen.mapValues { (time: $0.0, at: $0.1) }
        return out
    }

    static func path(_ pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 4096)
        return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : ""
    }

    // Raggruppa per app: Chrome Helper, renderer, XPC dentro "Google Chrome.app" contano come Chrome
    func group(_ list: [ProcessSample]) -> [AppGroup] {
        var groups: [String: AppGroup] = [:]
        for p in list {
            let (key, bundle) = Self.appKey(p)
            if groups[key] == nil {
                groups[key] = AppGroup(key: key, name: displayName(key: key, bundle: bundle, fallback: p.name), bundlePath: bundle, processes: [])
            }
            groups[key]!.processes.append(p)
        }
        return Array(groups.values)
    }

    static func appKey(_ p: ProcessSample) -> (String, String?) {
        if let r = p.path.range(of: ".app/") ?? (p.path.hasSuffix(".app") ? p.path.range(of: ".app") : nil) {
            let bundle = String(p.path[..<r.upperBound]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let full = bundle.hasPrefix("/") ? bundle : "/" + bundle
            return (full, full)
        }
        return (p.name, nil)
    }

    private func displayName(key: String, bundle: String?, fallback: String) -> String {
        if let n = nameCache[key] { return n }
        var n = fallback
        if let b = bundle {
            let bundleObj = Bundle(path: b)
            n = (bundleObj?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundleObj?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? ((b as NSString).lastPathComponent as NSString).deletingPathExtension
        }
        nameCache[key] = n
        return n
    }
}

// Riga di comando completa (per riconoscere node/python e gli agenti AI)
func processArguments(_ pid: pid_t) -> [String] {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
    var buf = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0, size > 4 else { return [] }
    let argc = Int(buf.withUnsafeBytes { $0.load(as: Int32.self) })
    var i = 4
    while i < size && buf[i] != 0 { i += 1 }          // percorso dell'eseguibile
    while i < size && buf[i] == 0 { i += 1 }          // padding
    var args: [String] = []
    while i < size && args.count < argc {
        let start = i
        while i < size && buf[i] != 0 { i += 1 }
        args.append(String(decoding: buf[start..<i], as: UTF8.self))
        i += 1
    }
    return args
}

// Cartella di lavoro di un processo
func processCwd(_ pid: pid_t) -> String? {
    var info = proc_vnodepathinfo()
    let r = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, Int32(MemoryLayout<proc_vnodepathinfo>.size))
    guard r > 0 else { return nil }
    return withUnsafeBytes(of: info.pvi_cdir.vip_path) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
}

// ================================================================ ispezione della firma
struct SignatureInfo {
    var signer: String = "Non firmato"
    var identifier: String?
    var teamID: String?
    var hardenedRuntime = false
    var sandboxed = false
    var appleSigned = false
    var architecture: String?
}

func signatureInfo(pid: pid_t) -> SignatureInfo {
    var s = SignatureInfo()
    var code: SecCode?
    let attrs = [kSecGuestAttributePid: pid] as CFDictionary
    guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess, let code else { return s }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return s }
    var infoRef: CFDictionary?
    let flags = SecCSFlags(rawValue: kSecCSSigningInformation | kSecCSRequirementInformation)
    guard SecCodeCopySigningInformation(staticCode, flags, &infoRef) == errSecSuccess, let info = infoRef as? [String: Any] else { return s }
    s.identifier = info[kSecCodeInfoIdentifier as String] as? String
    s.teamID = info[kSecCodeInfoTeamIdentifier as String] as? String
    if let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate], let leaf = certs.first {
        s.signer = (SecCertificateCopySubjectSummary(leaf) as String?) ?? "Firmato"
        s.appleSigned = s.signer.hasPrefix("Software Signing") || s.signer.hasPrefix("Apple")
    } else if info[kSecCodeInfoIdentifier as String] != nil {
        s.signer = "Firma ad hoc"
    }
    if let f = info[kSecCodeInfoFlags as String] as? UInt32 { s.hardenedRuntime = f & 0x10000 != 0 }
    if let ent = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any] {
        s.sandboxed = ent["com.apple.security.app-sandbox"] as? Bool ?? false
    }
    if let app = NSRunningApplication(processIdentifier: pid) {
        switch app.executableArchitecture {
        case NSBundleExecutableArchitectureARM64: s.architecture = "arm64"
        case NSBundleExecutableArchitectureX86_64: s.architecture = "x86_64 (Rosetta)"
        default: break
        }
    }
    return s
}

// ================================================================ azioni
func terminate(_ g: AppGroup, force: Bool) {
    if let app = NSRunningApplication(processIdentifier: g.mainPID), app.bundleURL != nil {
        _ = force ? app.forceTerminate() : app.terminate()
    } else {
        for p in g.processes { kill(p.pid, force ? SIGKILL : SIGTERM) }
    }
}
