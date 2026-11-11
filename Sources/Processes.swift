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
    private var pathCache: [pid_t: (start: Date, path: String)] = [:]

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
            let start = Date(timeIntervalSince1970: Double(bsd.pbi_start_tvsec))
            let path: String
            if let c = pathCache[pid], c.start == start { path = c.path } else { path = Self.path(pid); pathCache[pid] = (start, path) }
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
                                     startedAt: start))
        }
        previous = seen.mapValues { (time: $0.0, at: $0.1) }
        pathCache = pathCache.filter { seen[$0.key] != nil }
        return out
    }

    static func path(_ pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 { return String(cString: buf) }
        // a volte proc_pidpath fallisce (es. il processo principale di Chrome): ripiega
        // sul percorso di esecuzione registrato negli argomenti del processo
        return executablePath(pid) ?? ""
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
        // Chrome (e altri) eseguono il processo principale da una copia temporanea
        // ".../code_sign_clone/.../Google Chrome.app.bundle/...": la riportiamo all'app vera
        if let r = p.path.range(of: ".app.bundle/") {
            let name = (String(p.path[..<r.lowerBound]) as NSString).lastPathComponent + ".app"
            for dir in ["/Applications", NSHomeDirectory() + "/Applications"] where FileManager.default.fileExists(atPath: "\(dir)/\(name)") {
                return ("\(dir)/\(name)", "\(dir)/\(name)")
            }
        }
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

// Percorso dell'eseguibile dall'intestazione di KERN_PROCARGS2
func executablePath(_ pid: pid_t) -> String? {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return nil }
    var buf = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0, size > 4 else { return nil }
    var end = 4
    while end < size && buf[end] != 0 { end += 1 }
    let p = String(decoding: buf[4..<end], as: UTF8.self)
    return p.hasPrefix("/") ? p : nil
}

// Riga di comando completa (per riconoscere node/python e gli agenti AI).
// In cache per pid + avvio: gli argomenti di un processo non cambiano.
private var argsCache: [pid_t: (start: Date, args: [String])] = [:]
private let argsLock = NSLock()

func processArguments(_ pid: pid_t, startedAt: Date? = nil) -> [String] {
    if let start = startedAt {
        argsLock.lock(); defer { argsLock.unlock() }
        if let c = argsCache[pid], c.start == start { return c.args }
        let a = readProcessArguments(pid)
        argsCache[pid] = (start, a)
        if argsCache.count > 4000 { argsCache.removeAll() }
        return a
    }
    return readProcessArguments(pid)
}

private func readProcessArguments(_ pid: pid_t) -> [String] {
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
// Riavvio: chiusura normale (come ⌘Q), attesa della chiusura effettiva, riapertura.
// Se l'app non si chiude entro 15 s (documenti non salvati, dialoghi) non la forza e non la riapre.
func relaunch(_ g: AppGroup, done: @escaping (Bool) -> Void) {
    guard let path = g.bundlePath else { done(false); return }
    let url = URL(fileURLWithPath: path)
    let id = Bundle(url: url)?.bundleIdentifier
    var targets = id.map { NSRunningApplication.runningApplications(withBundleIdentifier: $0) } ?? []
    if targets.isEmpty, let a = NSRunningApplication(processIdentifier: g.mainPID) { targets = [a] }
    guard !targets.isEmpty else { done(false); return }
    targets.forEach { $0.terminate() }
    DispatchQueue.global().async {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline && targets.contains(where: { !$0.isTerminated }) { usleep(100_000) }
        let closed = targets.allSatisfy(\.isTerminated)
        DispatchQueue.main.async {
            guard closed else { done(false); return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, err in
                DispatchQueue.main.async { done(err == nil) }
            }
        }
    }
}

func terminate(_ g: AppGroup, force: Bool) {
    if let app = NSRunningApplication(processIdentifier: g.mainPID), app.bundleURL != nil {
        _ = force ? app.forceTerminate() : app.terminate()
    } else {
        for p in g.processes { kill(p.pid, force ? SIGKILL : SIGTERM) }
    }
}
