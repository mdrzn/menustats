// Strumenti per sviluppatori: porte in ascolto, sessioni di agenti AI, Docker, rete per app.
import AppKit
import Darwin

// Esegue un comando e ne ritorna l'output (con timeout, per non bloccare mai l'interfaccia)
func run(_ exe: String, _ args: [String], timeout: TimeInterval = 4) -> String? {
    guard FileManager.default.isExecutableFile(atPath: exe) else { return nil }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return nil }
    let deadline = Date().addingTimeInterval(timeout)
    var data = Data()
    let h = out.fileHandleForReading
    // legge mentre il processo gira, cosi' un output grande non lo blocca
    while p.isRunning && Date() < deadline {
        let chunk = h.availableData
        if chunk.isEmpty { usleep(20_000) } else { data.append(chunk) }
    }
    if p.isRunning { p.terminate() }
    data.append(h.readDataToEndOfFile())
    return String(data: data, encoding: .utf8)
}

// ================================================================ porte in ascolto
struct ListeningPort: Identifiable, Hashable {
    var id: String { "\(pid):\(port)" }
    let port: Int
    let pid: pid_t
    let command: String
    let address: String       // "*" = tutte le interfacce, "127.0.0.1" = solo locale
    var label = ""            // es. "next dev"
    var project: String?      // cartella di lavoro (ultimo componente)
    var owner: String?        // chi l'ha avviato: Claude Code, Terminale, Docker…
    var orphan = false        // server di sviluppo il cui genitore non c'e' piu'
    var isLocalOnly: Bool { address.hasPrefix("127.") || address == "[::1]" || address == "localhost" }
}

func readListeningPorts() -> [ListeningPort] {
    guard let out = run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]) else { return [] }
    var res: [String: ListeningPort] = [:]
    var pid: pid_t = 0, cmd = ""
    for line in out.split(separator: "\n") {
        guard let f = line.first else { continue }
        let v = String(line.dropFirst())
        switch f {
        case "p": pid = pid_t(v) ?? 0
        case "c": cmd = v
        case "n":
            guard let colon = v.lastIndex(of: ":"), let port = Int(v[v.index(after: colon)...]) else { continue }
            let addr = String(v[..<colon])
            let key = "\(pid):\(port)"
            // IPv4 + IPv6 sulla stessa porta: una riga sola, preferendo l'indirizzo piu' "aperto"
            if let old = res[key], old.address == "*" { continue }
            res[key] = ListeningPort(port: port, pid: pid, command: cmd, address: addr)
        default: break
        }
    }
    return res.values.sorted { $0.port < $1.port }
}

// Descrive cosa sta servendo un processo: "node next dev" -> "next dev", "python -m http.server" -> "http.server"
func describeCommand(_ pid: pid_t, fallback: String) -> String {
    let args = processArguments(pid)
    guard let exe = args.first else { return fallback }
    let base = (exe as NSString).lastPathComponent
    let interpreters = ["node", "bun", "deno", "python", "python3", "ruby", "php", "java", "npm", "npx", "pnpm", "yarn"]
    if interpreters.contains(where: { base.hasPrefix($0) }) {
        let rest = args.dropFirst().filter { !$0.hasPrefix("-") }
        if let script = rest.first {
            var name = (script as NSString).lastPathComponent
            // node_modules/.bin/next dev -> "next dev"; .../vite/bin/vite.js -> "vite"
            if script.contains("node_modules/") {
                let parts = script.components(separatedBy: "node_modules/").last?.split(separator: "/") ?? []
                if let pkg = parts.first, pkg != ".bin" { name = String(pkg) } else if parts.count > 1 { name = String(parts[1]) }
            }
            name = name.replacingOccurrences(of: ".js", with: "").replacingOccurrences(of: ".mjs", with: "")
            if let sub = rest.dropFirst().first, sub.count < 16, !sub.contains("/") { name += " " + sub }
            return name
        }
    }
    return base
}

// ================================================================ agenti AI
struct AgentKind {
    let name: String
    let match: (_ exe: String, _ args: [String]) -> Bool
}

let agentKinds: [AgentKind] = [
    AgentKind(name: "Claude Code") { exe, args in exe == "claude" || args.contains { $0.contains("@anthropic-ai/claude-code") || $0.hasSuffix("/claude") || $0.contains("/claude/versions/") } },
    AgentKind(name: "Codex") { exe, args in exe == "codex" || args.contains { $0.contains("@openai/codex") || $0.hasSuffix("/codex") } },
    AgentKind(name: "Gemini CLI") { exe, args in exe == "gemini" || args.contains { $0.contains("@google/gemini-cli") } },
    AgentKind(name: "Aider") { exe, args in exe == "aider" || args.contains { $0.hasSuffix("/aider") } },
    AgentKind(name: "OpenCode") { exe, args in exe == "opencode" || args.contains { $0.hasSuffix("/opencode") } },
    AgentKind(name: "Cursor Agent") { exe, _ in exe == "cursor-agent" },
    AgentKind(name: "Amp") { exe, args in exe == "amp" || args.contains { $0.contains("@sourcegraph/amp") } },
    AgentKind(name: "Goose") { exe, _ in exe == "goose" },
]

struct AgentSession: Identifiable {
    var id: pid_t { pid }
    let pid: pid_t
    let kind: String
    let cwd: String?
    let startedAt: Date
    var cpu: Double            // processo + figli
    var memory: UInt64
    var children: Int
    var ports: [Int]
    var terminal: String?      // iTerm2, Terminale, VS Code…
    var project: String { cwd.map { ($0 as NSString).lastPathComponent } ?? "?" }
    var isBusy: Bool { cpu > 3 }
}

// Albero dei processi: figli per pid
func childrenMap(_ list: [ProcessSample]) -> [pid_t: [ProcessSample]] {
    Dictionary(grouping: list, by: \.ppid)
}

func descendants(of pid: pid_t, in kids: [pid_t: [ProcessSample]]) -> [ProcessSample] {
    var out: [ProcessSample] = [], stack = [pid]
    while let p = stack.popLast() {
        for c in kids[p] ?? [] { out.append(c); stack.append(c.pid) }
    }
    return out
}

// App "terminale" che contiene un processo, risalendo i genitori. Legge pid e percorso
// direttamente (anche i processi di root come login, che non compaiono nell'elenco).
func parentPID(_ pid: pid_t) -> pid_t {
    // sysctl funziona anche sui processi di root (proc_pidinfo no), come fa ps
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.size
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    return sysctl(&mib, 4, &info, &size, nil, 0) == 0 && size > 0 ? info.kp_eproc.e_ppid : 0
}

func hostApp(of pid: pid_t, in byPID: [pid_t: ProcessSample] = [:]) -> String? {
    var cur = parentPID(pid), hops = 0
    while cur > 1, hops < 30 {
        let path = byPID[cur]?.path ?? ProcessReader.path(cur)
        if let r = path.range(of: ".app/") {
            let app = ((String(path[..<r.lowerBound]) as NSString).lastPathComponent)
            return app == "Terminal" ? "Terminale" : app
        }
        cur = parentPID(cur); hops += 1
    }
    return nil
}

func detectAgents(_ list: [ProcessSample], ports: [ListeningPort]) -> [AgentSession] {
    let byPID = Dictionary(list.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
    let kids = childrenMap(list)
    var sessions: [AgentSession] = []
    var claimed = Set<pid_t>()
    for p in list.sorted(by: { $0.pid < $1.pid }) where !p.path.contains(".app/") && !claimed.contains(p.pid) {
        let args = processArguments(p.pid)
        // nome di lancio (argv[0]): il binario su disco puo' chiamarsi come la versione
        let base = ((args.first ?? p.path) as NSString).lastPathComponent
        let fileBase = (p.path as NSString).lastPathComponent
        guard ["node", "bun", "python"].contains(where: { fileBase.hasPrefix($0) || base.hasPrefix($0) })
                || agentKinds.contains(where: { $0.match(base, [p.path]) }) else { continue }
        guard let kind = agentKinds.first(where: { $0.match(base, args + [p.path]) }) else { continue }
        // un agente lanciato da un altro processo dello stesso tipo (wrapper) conta una volta sola
        if let parent = byPID[p.ppid], claimed.contains(parent.pid) { continue }
        let desc = descendants(of: p.pid, in: kids)
        desc.forEach { claimed.insert($0.pid) }
        claimed.insert(p.pid)
        let tree = Set([p.pid] + desc.map(\.pid))
        sessions.append(AgentSession(pid: p.pid, kind: kind.name, cwd: processCwd(p.pid), startedAt: p.startedAt,
                                     cpu: p.cpu + desc.reduce(0) { $0 + $1.cpu },
                                     memory: p.memory + desc.reduce(0) { $0 + $1.memory },
                                     children: desc.count,
                                     ports: ports.filter { tree.contains($0.pid) }.map(\.port),
                                     terminal: hostApp(of: p.pid, in: byPID)))
    }
    return sessions.sorted { $0.startedAt > $1.startedAt }
}

// Arricchisce le porte con etichetta, progetto, chi le ha avviate e se sono "orfane"
func annotate(_ ports: [ListeningPort], processes: [ProcessSample], agents: [AgentSession], containers: [Container]) -> [ListeningPort] {
    let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
    let kids = childrenMap(processes)
    var agentOf: [pid_t: String] = [:]
    for a in agents { for d in descendants(of: a.pid, in: kids) { agentOf[d.pid] = a.kind } }
    let devRuntimes = ["node", "bun", "deno", "python", "ruby", "php", "java"]
    return ports.map { var p = $0
        p.label = describeCommand(p.pid, fallback: p.command)
        if let cwd = processCwd(p.pid), cwd != "/" { p.project = (cwd as NSString).lastPathComponent }
        if let c = containers.first(where: { $0.hostPorts.contains(p.port) }) {
            p.owner = "Docker"; p.label = c.name; p.project = c.image
        } else if let a = agentOf[p.pid] {
            p.owner = a
        } else {
            p.owner = hostApp(of: p.pid, in: byPID) ?? byPID[p.pid].map { ProcessReader.appKey($0).1 == nil ? nil : (($0.path.components(separatedBy: ".app/").first ?? "") as NSString).lastPathComponent } ?? nil
        }
        let runtime = (byPID[p.pid]?.path as NSString?)?.lastPathComponent ?? p.command
        p.orphan = byPID[p.pid]?.ppid == 1 && devRuntimes.contains { runtime.hasPrefix($0) } && p.project != nil
        return p
    }
}

func killProcess(_ pid: pid_t, force: Bool = false) { kill(pid, force ? SIGKILL : SIGTERM) }

// ================================================================ Docker
struct Container: Identifiable {
    let id: String
    let name: String
    let image: String
    let status: String
    let running: Bool
    let ports: String
    var hostPorts: [Int]
}

let dockerCLI: String? = {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "\(home)/.docker/bin/docker", "\(home)/.orbstack/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker", "/Applications/OrbStack.app/Contents/MacOS/xbin/docker"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
}()

func readContainers() -> [Container]? {
    guard let cli = dockerCLI, let out = run(cli, ["ps", "-a", "--format", "{{json .}}"], timeout: 3) else { return nil }
    return out.split(separator: "\n").compactMap { line in
        guard let d = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
        let ports = d["Ports"] as? String ?? ""
        // "0.0.0.0:5432->5432/tcp, :::5432->5432/tcp" -> [5432]
        let host = Set(ports.components(separatedBy: ", ").compactMap { seg -> Int? in
            guard let arrow = seg.range(of: "->"), let colon = seg[..<arrow.lowerBound].lastIndex(of: ":") else { return nil }
            return Int(seg[seg.index(after: colon)..<arrow.lowerBound])
        })
        let state = (d["State"] as? String ?? "").lowercased()
        return Container(id: d["ID"] as? String ?? "", name: d["Names"] as? String ?? "", image: d["Image"] as? String ?? "",
                         status: d["Status"] as? String ?? "", running: state == "running", ports: ports, hostPorts: host.sorted())
    }
}

func dockerAction(_ verb: String, _ id: String) {
    guard let cli = dockerCLI else { return }
    DispatchQueue.global().async { _ = run(cli, [verb, id], timeout: 20) }
}

// ================================================================ rete per app (nettop)
struct AppTraffic: Identifiable { var id: String { name }; let name: String; var down: Double; var up: Double }

// Un secondo di misura: nettop -d da' le differenze del secondo campione
func readAppTraffic() -> [AppTraffic] {
    guard let out = run("/usr/bin/nettop", ["-P", "-d", "-L", "2", "-s", "1", "-x", "-J", "bytes_in,bytes_out"], timeout: 4) else { return [] }
    let blocks = out.components(separatedBy: ",bytes_in,bytes_out,\n")
    guard let last = blocks.last, blocks.count >= 3 else { return [] }
    var byName: [String: AppTraffic] = [:]
    for line in last.split(separator: "\n") {
        let f = line.split(separator: ",", omittingEmptySubsequences: false)
        guard f.count >= 3, let i = Double(f[1]), let o = Double(f[2]), i + o > 0 else { continue }
        var name = String(f[0])
        if let dot = name.lastIndex(of: "."), Int(name[name.index(after: dot)...]) != nil { name = String(name[..<dot]) }
        byName[name, default: AppTraffic(name: name, down: 0, up: 0)].down += i
        byName[name, default: AppTraffic(name: name, down: 0, up: 0)].up += o
    }
    return byName.values.sorted { $0.down + $0.up > $1.down + $1.up }
}
