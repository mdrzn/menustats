// Automazioni: notifiche, dettagli delle sessioni di Claude Code, riavvio automatico delle app
// oltre una soglia di memoria, "tieni sveglio" automatico.
import AppKit
import UserNotifications

// ================================================================ notifiche
enum NotifyKind: String, Codable, CaseIterable, Identifiable {
    case cpu, memory, disk, thermal, agentDone, serverDown, autoRestart
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cpu: L("App che usano molta CPU"); case .memory: L("Memoria sotto pressione"); case .disk: L("Disco quasi pieno")
        case .thermal: L("Mac molto caldo"); case .agentDone: L("Agente AI che ha finito o aspetta")
        case .serverDown: L("Server di sviluppo che si ferma"); case .autoRestart: L("Riavvio automatico di un'app")
        }
    }
}

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    private var lastSent: [String: Date] = [:]
    private var authorized = false

    func setup() {
        guard !Monitor.demoMode else { return }
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        c.requestAuthorization(options: [.alert, .sound]) { ok, _ in self.authorized = ok }
    }

    // Invia una notifica; la stessa chiave non si ripete prima di `cooldown` secondi
    func send(_ kind: NotifyKind, key: String, title: String, body: String, tab: String, cooldown: TimeInterval = 1800) {
        guard Prefs.shared.c.notify[kind.rawValue] ?? kind.defaultOn, !Monitor.demoMode else { return }
        if let last = lastSent[key], Date().timeIntervalSince(last) < cooldown { return }
        lastSent[key] = Date()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["tab": tab]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: key + "-\(Date().timeIntervalSince1970)", content: content, trigger: nil))
    }

    // Clic sulla notifica: apre il pannello sulla scheda giusta
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler done: @escaping () -> Void) {
        let tab = response.notification.request.content.userInfo["tab"] as? String ?? "home"
        DispatchQueue.main.async {
            Nav.shared.tab = tab
            AppDelegate.shared?.togglePopoverOpen()
        }
        done()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent n: UNNotification, withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }
}

extension NotifyKind {
    var defaultOn: Bool { self != .cpu }      // la CPU alta capita spesso: spenta di default
}

// ================================================================ sessioni di Claude Code
struct ClaudeSessionInfo {
    var file: String
    var model: String?
    var inputTokens = 0, outputTokens = 0, cacheReadTokens = 0, cacheWriteTokens = 0
    var lastText: String?
    var lastActivity: Date?
    var totalTokens: Int { inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens }
}

// Legge i log JSONL in ~/.claude/projects in modo incrementale (solo i byte aggiunti)
final class ClaudeSessions {
    static let shared = ClaudeSessions()
    private struct FileState { var offset: UInt64 = 0; var usage: [String: [Int]] = [:]; var info: ClaudeSessionInfo; var partial = Data() }
    private var files: [String: FileState] = [:]
    private let lock = NSLock()
    private let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")

    // Cartella dei log per una cartella di lavoro: ogni carattere non alfanumerico diventa "-"
    func projectDir(for cwd: String) -> URL {
        root.appendingPathComponent(String(cwd.map { $0.isLetter || $0.isNumber ? $0 : "-" }))
    }

    // Assegna a ogni sessione Claude Code il proprio file di log (il piu' recente non gia' preso)
    func attach(_ agents: inout [AgentSession]) {
        var taken = Set<String>()
        for i in agents.indices.sorted(by: { agents[$0].startedAt > agents[$1].startedAt }) where agents[i].kind == "Claude Code" {
            guard let cwd = agents[i].cwd else { continue }
            let dir = projectDir(for: cwd)
            let candidates = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
                .filter { $0.pathExtension == "jsonl" && !taken.contains($0.path) }
                .compactMap { u -> (URL, Date)? in
                    guard let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return nil }
                    return (u, d)
                }
                .filter { $0.1 >= agents[i].startedAt.addingTimeInterval(-60) }
                .sorted { $0.1 > $1.1 }
            guard let file = candidates.first?.0 else { continue }
            taken.insert(file.path)
            agents[i].claude = read(file)
        }
    }

    private func read(_ url: URL) -> ClaudeSessionInfo? {
        lock.lock(); defer { lock.unlock() }
        var st = files[url.path] ?? FileState(info: ClaudeSessionInfo(file: url.path))
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        if size < st.offset { st = FileState(info: ClaudeSessionInfo(file: url.path)) }     // file riscritto
        if size > st.offset {
            try? h.seek(toOffset: st.offset)
            let data = st.partial + (h.readDataToEndOfFile())
            st.offset = size
            var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
            st.partial = data.last == UInt8(ascii: "\n") ? Data() : Data(lines.removeLast())
            for line in lines where !line.isEmpty { parse(Data(line), into: &st) }
            // somma per id di messaggio (lo stesso messaggio puo' comparire su piu' righe)
            var i = 0, o = 0, cr = 0, cw = 0
            for u in st.usage.values { i += u[0]; o += u[1]; cr += u[2]; cw += u[3] }
            st.info.inputTokens = i; st.info.outputTokens = o; st.info.cacheReadTokens = cr; st.info.cacheWriteTokens = cw
        }
        files[url.path] = st
        return st.info
    }

    private func parse(_ line: Data, into st: inout FileState) {
        guard let d = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        if let ts = d["timestamp"] as? String, let date = iso.date(from: ts) { st.info.lastActivity = date }
        guard d["type"] as? String == "assistant", let m = d["message"] as? [String: Any] else { return }
        if let model = m["model"] as? String, !model.hasPrefix("<") { st.info.model = model }
        if let id = m["id"] as? String, let u = m["usage"] as? [String: Any] {
            st.usage[id] = [u["input_tokens"] as? Int ?? 0, u["output_tokens"] as? Int ?? 0,
                            u["cache_read_input_tokens"] as? Int ?? 0, u["cache_creation_input_tokens"] as? Int ?? 0]
        }
        if let content = m["content"] as? [[String: Any]],
           let text = content.last(where: { $0["type"] as? String == "text" })?["text"] as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            st.info.lastText = text
        }
    }
}

func formatTokens(_ n: Int) -> String {
    let v = Double(n)
    if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
    if v >= 1_000 { return String(format: "%.0fK", v / 1_000) }
    return "\(n)"
}

// ================================================================ regole automatiche
final class Automations {
    static let shared = Automations()
    private var previousAlerts = Set<String>()
    private var agentBusySince: [pid_t: Date] = [:]
    private var agentIdleSince: [pid_t: Date] = [:]
    private var agentNotified = Set<pid_t>()
    private var previousPorts: [String: ListeningPort] = [:]
    private var restartedAt: [String: Date] = [:]
    var killedByUs = Set<pid_t>()            // porte chiuse da MenuStats: niente notifica "si è fermato"
    private var autoAwakeReason: String?

    func evaluate(_ m: Monitor) {
        let now = Date()
        // -------------------------------------------------- avvisi nuovi -> notifica
        let ids = Set(m.alerts.map(\.id))
        for a in m.alerts where !previousAlerts.contains(a.id) {
            let kind: NotifyKind? = a.id.hasPrefix("hog-") ? .cpu : a.id == "mem" ? .memory : a.id == "disk" ? .disk : a.id == "thermal" ? .thermal : nil
            if let kind { Notifier.shared.send(kind, key: a.id, title: a.title, body: a.detail, tab: kind == .cpu || kind == .memory ? "apps" : "system") }
        }
        previousAlerts = ids

        // -------------------------------------------------- agente che ha finito (al lavoro >= 20 s, poi fermo >= 10 s)
        for a in m.agents {
            if a.isBusy {
                if agentBusySince[a.pid] == nil { agentBusySince[a.pid] = now }
                agentIdleSince[a.pid] = nil
                agentNotified.remove(a.pid)
            } else {
                if agentIdleSince[a.pid] == nil { agentIdleSince[a.pid] = now }
                if let busy = agentBusySince[a.pid], let idle = agentIdleSince[a.pid],
                   idle.timeIntervalSince(busy) >= 20, now.timeIntervalSince(idle) >= 10, !agentNotified.contains(a.pid) {
                    agentNotified.insert(a.pid)
                    agentBusySince[a.pid] = nil
                    Notifier.shared.send(.agentDone, key: "agent-\(a.pid)-\(Int(now.timeIntervalSince1970))",
                                         title: L("%@ ha finito", a.kind),
                                         body: a.claude?.lastText.map { String($0.prefix(140)) } ?? L("In attesa in %@", a.project),
                                         tab: "agents", cooldown: 0)
                }
            }
        }
        let alive = Set(m.agents.map(\.pid))
        agentBusySince = agentBusySince.filter { alive.contains($0.key) }
        agentIdleSince = agentIdleSince.filter { alive.contains($0.key) }

        // -------------------------------------------------- server di sviluppo che si ferma da solo
        let current = Dictionary(m.devPorts.filter { $0.project != nil }.map { ("\($0.port)", $0) }, uniquingKeysWith: { a, _ in a })
        for (key, p) in previousPorts where current[key] == nil && !killedByUs.contains(p.pid) {
            Notifier.shared.send(.serverDown, key: "port-\(key)", title: L("Il server :%d si è fermato", p.port),
                                 body: [p.label, p.project].compactMap { $0 }.joined(separator: " · "), tab: "ports", cooldown: 120)
        }
        previousPorts = current

        // -------------------------------------------------- riavvio automatico oltre la soglia di memoria
        for g in m.apps {
            guard let path = g.bundlePath, let gb = m.settings.c.autoRestart[path], gb > 0 else { continue }
            let used = Double(g.memory) / 1_073_741_824
            guard used > gb, now.timeIntervalSince(restartedAt[path] ?? .distantPast) > 1800 else { continue }
            restartedAt[path] = now
            m.restart(g)
            Notifier.shared.send(.autoRestart, key: "restart-\(path)", title: L("%@ riavviata", g.name),
                                 body: L("Usava %@, oltre la soglia di %@", formatBytes(g.memory), String(format: "%.0f GB", gb)), tab: "apps", cooldown: 0)
        }

        // -------------------------------------------------- tieni sveglio automatico
        let c = m.settings.c
        var reason: String?
        if c.awakeWhenAgents, m.agents.contains(where: \.isBusy) { reason = L("un agente AI è al lavoro") }
        else if c.awakeWhenServers, !m.devPorts.filter({ $0.project != nil }).isEmpty { reason = L("c'è un server di sviluppo acceso") }
        else if c.awakeOnAC, (BatteryInfo.read()?.onAC ?? true) && c.awakeOnAC { reason = L("collegato all'alimentatore") }
        if reason != autoAwakeReason {
            autoAwakeReason = reason
            m.awake.setAuto(reason)
        }
    }
}
