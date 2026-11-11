// Configurazione salvata e modello centrale: campiona le metriche, tiene lo storico per i
// grafici e calcola gli avvisi "Da controllare".
import AppKit
import SwiftUI
import Combine
import CoreAudio

// ================================================================ configurazione
enum MenuModule: String, Codable, CaseIterable, Identifiable {
    case cpu, memory, network, gpu, temperature, power, disk, battery, ports, agents
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cpu: "CPU"; case .memory: "Memoria"; case .network: "Rete"; case .gpu: "GPU"
        case .temperature: "Temperatura"; case .power: "Consumo"; case .disk: "Disco"
        case .battery: "Batteria"; case .ports: "Porte"; case .agents: "Agenti AI"
        }
    }
    var symbol: String {
        switch self {
        case .cpu: "cpu"; case .memory: "memorychip"; case .network: "arrow.up.arrow.down"; case .gpu: "square.stack.3d.up"
        case .temperature: "thermometer.medium"; case .power: "bolt"; case .disk: "internaldrive"
        case .battery: "battery.75percent"; case .ports: "point.3.connected.trianglepath.dotted"; case .agents: "sparkles"
        }
    }
}

// Aspetto degli elementi nella barra dei menu
enum MenuLook: String, Codable, CaseIterable, Identifiable {
    case stacked, compact, graph, pill, outline, icons
    var id: String { rawValue }
    var title: String {
        switch self {
        case .stacked: "Impilato"; case .compact: "Compatto"; case .graph: "Grafico"
        case .pill: "Pillola"; case .outline: "Contorno"; case .icons: "Icone"
        }
    }
}

enum ValueColor: String, Codable, CaseIterable, Identifiable {
    case menuBar, accent, load
    var id: String { rawValue }
    var title: String { switch self { case .menuBar: "Come la barra"; case .accent: "Accento"; case .load: "Per carico" } }
}

enum FontStyle: String, Codable, CaseIterable, Identifiable {
    case system, rounded, mono
    var id: String { rawValue }
    var title: String { switch self { case .system: "Sistema"; case .rounded: "Arrotondato"; case .mono: "Monospaziato" } }
    var design: Font.Design { switch self { case .system: .default; case .rounded: .rounded; case .mono: .monospaced } }
}

// Accenti proposti: nomi e colori nostri
let accentPresets: [(name: String, hex: String)] = [
    ("Menta", "4FD1A5"), ("Laguna", "38BDF8"), ("Lavanda", "A78BFA"), ("Corallo", "FB7185"),
    ("Ambra", "F5B942"), ("Lime", "A3E635"), ("Ghiaccio", "E2E8F0"),
]

struct Config: Codable, Equatable {
    var modules: [MenuModule] = [.cpu, .memory, .network]
    var look: MenuLook = .stacked
    var valueColor: ValueColor = .menuBar
    var font: FontStyle = .system
    var accent = "4FD1A5"
    var interval = 2.0                       // secondi tra un campione e l'altro (popover chiuso)
    var fahrenheit = false
    var appVolumes: [String: Double] = [:]   // bundle id -> 0...1.5
    var lastTab = "home"
    var cpuAlert = 90.0                      // % di un core sostenuta che fa scattare l'avviso
    var hotkeyEnabled = true                 // ⌥⌘M apre il popover
    var perAppVolume = false                 // sperimentale: chiede il permesso di registrare l'audio

    static func load() -> Config {
        let base = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(Config()))) as? [String: Any] ?? [:]
        let saved = UserDefaults.standard.data(forKey: "config")
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let merged = base.merging(saved) { _, new in new }
        guard let data = try? JSONSerialization.data(withJSONObject: merged),
              let c = try? JSONDecoder().decode(Config.self, from: data) else { return Config() }
        return c
    }
    func save() { if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: "config") } }
}

final class Prefs: ObservableObject {
    static let shared = Prefs()
    static var persist = true                // false negli screenshot: non tocca le impostazioni vere
    @Published var c = Config.load() { didSet { if c != oldValue && Prefs.persist { c.save() } } }
    @Published var launchAtLogin = LoginItem.isOn { didSet { LoginItem.set(launchAtLogin) } }
    var accent: Color { Color(hex: c.accent) }
}

// Avvio al login tramite LaunchAgent utente
enum LoginItem {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/app.menustats.plist")
    static var isOn: Bool { FileManager.default.fileExists(atPath: url.path) }
    static func set(_ on: Bool) {
        if on, let exe = Bundle.main.executablePath {
            let plist: [String: Any] = ["Label": "app.menustats", "ProgramArguments": [exe], "RunAtLoad": true, "LimitLoadToSessionType": "Aqua"]
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            (plist as NSDictionary).write(to: url, atomically: true)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// ================================================================ storico per i grafici
struct History {
    var values: [Double] = []
    let capacity: Int
    init(_ capacity: Int = 90) { self.capacity = capacity }
    mutating func add(_ v: Double) { values.append(v); if values.count > capacity { values.removeFirst(values.count - capacity) } }
    var last: Double { values.last ?? 0 }
    var peak: Double { values.max() ?? 0 }
}

// ================================================================ avvisi
struct Alert: Identifiable {
    enum Action { case quitApp(AppGroup), killPorts([ListeningPort]), openTab(String) }
    let id: String
    let severity: Int             // 1 = attenzione, 2 = grave
    let title: String
    let detail: String
    let actionTitle: String?
    let action: Action?
}

// ================================================================ modello
final class Monitor: ObservableObject {
    static let shared = Monitor()
    let settings = Prefs.shared

    // lettori
    private let cpuReader = CPUReader()
    private let netReader = NetworkReader()
    private let procReader = ProcessReader()
    let selfUsage = SelfUsage()
    let awake = AwakeController()
    let mixer = AppVolumeMixer()

    // metriche veloci
    @Published var cpu = 0.0
    @Published var cpuUser = 0.0
    @Published var cpuSystem = 0.0
    @Published var perCore: [Double] = []
    @Published var memory = MemoryInfo()
    @Published var down = 0.0
    @Published var up = 0.0
    @Published var disk = DiskInfo()
    @Published var gpu: Double?
    @Published var sensors = SensorInfo()
    @Published var battery: BatteryInfo?
    @Published var thermal = ProcessInfo.ThermalState.nominal
    @Published var cpuHistory = History()
    @Published var memHistory = History()
    @Published var downHistory = History()
    @Published var upHistory = History()
    @Published var gpuHistory = History()
    @Published var tempHistory = History()
    @Published var powerHistory = History()

    // dettagli (solo a popover aperto)
    @Published var processes: [ProcessSample] = []
    @Published var apps: [AppGroup] = []
    @Published var ports: [ListeningPort] = []
    @Published var agents: [AgentSession] = []
    @Published var containers: [Container]? = nil       // nil = Docker non installato
    @Published var traffic: [AppTraffic] = []
    @Published var blockers: [SleepBlocker] = []
    @Published var alerts: [Alert] = []
    @Published var restarting: Set<String> = []          // app in fase di riavvio
    @Published var restartFailed: Set<String> = []       // non si sono chiuse da sole

    // audio
    @Published var audioApps: [AudioApp] = []
    @Published var outputDevices: [AudioDevice] = []
    @Published var inputDevices: [AudioDevice] = []
    @Published var outputID: AudioObjectID = 0
    @Published var inputID: AudioObjectID = 0
    @Published var outputVolume: Float = 0
    @Published var outputMuted = false

    @Published var detailed = false { didSet { if detailed != oldValue { reschedule(); if detailed { refreshDetails(); refreshAudio() } } } }
    @Published var trafficVisible = false { didSet { if trafficVisible { refreshTraffic() } } }

    private var timer: Timer?
    private var detailTick = 0
    private var hogStreak: [String: Int] = [:]
    private let work = DispatchQueue(label: "menustats.work", qos: .utility)
    private var busy = false

    static var demoMode = false              // screenshot: niente timer, audio o campionamenti
    var hostName = Host.current().localizedName ?? "Mac"
    var uptime: TimeInterval { Monitor.demoMode ? 3 * 86_400 + 4 * 3600 : systemUptime }

    init() {
        guard !Monitor.demoMode else { return }
        cpuReader.sample(); netReader.sample(); selfUsage.sample()
        _ = procReader.sample()
        tick()
        reschedule()
        observeAudio { [weak self] in self?.refreshAudio(rebuild: true) }
        refreshAudio()
        NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.thermal = ProcessInfo.processInfo.thermalState
        }
    }

    func reschedule() {
        guard !Monitor.demoMode else { return }
        timer?.invalidate()
        let t = Timer(timeInterval: detailed ? 1 : settings.c.interval, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    var needsSensors: Bool {
        detailed || settings.c.modules.contains(.temperature) || settings.c.modules.contains(.power)
    }

    func tick() {
        cpuReader.sample(); netReader.sample(); selfUsage.sample()
        cpu = cpuReader.total; cpuUser = cpuReader.user; cpuSystem = cpuReader.system; perCore = cpuReader.perCore
        memory = .read()
        down = netReader.down; up = netReader.up
        cpuHistory.add(cpu); memHistory.add(memory.fraction); downHistory.add(down); upHistory.add(up)
        if detailed || settings.c.modules.contains(.gpu) { gpu = gpuUtilization(); gpuHistory.add(gpu ?? 0) }
        if needsSensors {
            sensors = .read(fans: detailed || settings.c.modules.contains(.power))
            if let t = sensors.socTemperature { tempHistory.add(t) }
            if let p = sensors.systemPower { powerHistory.add(p) }
        }
        if detailed || settings.c.modules.contains(.battery) { battery = .read() }
        if detailed || settings.c.modules.contains(.disk) { disk = .read() }
        thermal = ProcessInfo.processInfo.thermalState
        detailTick += 1
        if detailed && detailTick % 3 == 0 { refreshDetails() }
        else if !detailed && detailTick % 15 == 0 && (settings.c.modules.contains(.ports) || settings.c.modules.contains(.agents)) { refreshDetails() }
        if detailed && trafficVisible && detailTick % 3 == 0 { refreshTraffic() }
        if detailed { refreshAudioLevels() }
    }

    // Processi, porte, agenti, Docker: in background
    func refreshDetails() {
        guard !busy, !Monitor.demoMode else { return }
        busy = true
        let threshold = settings.c.cpuAlert
        work.async { [weak self] in
            guard let self else { return }
            let procs = self.procReader.sample()
            let groups = self.procReader.group(procs).sorted { $0.cpu > $1.cpu }
            let rawPorts = readListeningPorts()
            let agents = detectAgents(procs, ports: rawPorts)
            let containers = readContainers()
            let ports = annotate(rawPorts, processes: procs, agents: agents, containers: containers ?? [])
            let blockers = readSleepBlockers()
            DispatchQueue.main.async {
                self.processes = procs; self.apps = groups; self.ports = ports; self.agents = agents
                self.containers = containers; self.blockers = blockers
                self.updateAlerts(threshold: threshold)
                self.busy = false
            }
        }
    }

    func refreshTraffic() {
        guard !Monitor.demoMode else { return }
        work.async { [weak self] in
            let t = readAppTraffic()
            DispatchQueue.main.async { self?.traffic = t }
        }
    }

    // ------------------------------------------------------------ audio
    func refreshAudio(rebuild: Bool = false) {
        let devices = audioDevices()
        outputDevices = devices.filter(\.hasOutput)
        inputDevices = devices.filter(\.hasInput)
        let newOut = defaultDevice(input: false)
        let outputChanged = newOut != outputID && outputID != 0
        outputID = newOut
        inputID = defaultDevice(input: true)
        audioApps = MenuStats.audioApps()
        refreshAudioLevels()
        applyMixer(rebuild: rebuild && outputChanged)
    }

    // Il volume per app agisce solo se attivato nelle impostazioni
    func applyMixer(rebuild: Bool = false) {
        guard !Monitor.demoMode else { return }
        guard settings.c.perAppVolume else { mixer.stopAll(); return }
        if rebuild { mixer.rebuild(apps: audioApps, volumes: settings.c.appVolumes) }
        else { mixer.apply(apps: audioApps, volumes: settings.c.appVolumes) }
    }

    func refreshAudioLevels() {
        outputVolume = deviceVolume(outputID) ?? 0
        outputMuted = deviceMuted(outputID)
    }

    func setAppVolume(_ app: AudioApp, _ v: Double) {
        settings.c.appVolumes[app.key] = abs(v - 1) < 0.02 ? nil : v
        applyMixer()
        objectWillChange.send()
    }

    func appVolume(_ app: AudioApp) -> Double { settings.c.appVolumes[app.key] ?? 1 }

    // ------------------------------------------------------------ avvisi
    private func updateAlerts(threshold: Double) {
        var out: [Alert] = []
        if memory.pressure != .normal {
            out.append(Alert(id: "mem", severity: memory.pressure == .critical ? 2 : 1, title: "Memoria sotto pressione",
                             detail: "\(formatBytes(memory.used)) usati su \(formatBytes(memory.total))", actionTitle: "App", action: .openTab("apps")))
        }
        if disk.total > 0 && Double(disk.free) / Double(disk.total) < 0.1 {
            out.append(Alert(id: "disk", severity: 1, title: "Disco quasi pieno", detail: "\(formatBytes(UInt64(disk.free))) liberi",
                             actionTitle: nil, action: nil))
        }
        if thermal == .serious || thermal == .critical {
            out.append(Alert(id: "thermal", severity: 2, title: "Il Mac è molto caldo", detail: "macOS sta limitando le prestazioni",
                             actionTitle: "Sistema", action: .openTab("system")))
        }
        // app che consumano tanta CPU per piu' campioni di fila (~10 s)
        var streak: [String: Int] = [:]
        for g in apps where g.cpu >= threshold && g.name != "MenuStats" { streak[g.key] = (hogStreak[g.key] ?? 0) + 1 }
        hogStreak = streak
        for g in apps where (streak[g.key] ?? 0) >= 5 {
            out.append(Alert(id: "hog-\(g.key)", severity: 1, title: "\(g.name) usa molta CPU",
                             detail: "\(formatPercent(g.cpu / 100)) da un po'", actionTitle: "Chiudi", action: .quitApp(g)))
        }
        let orphans = ports.filter(\.orphan)
        if !orphans.isEmpty {
            out.append(Alert(id: "orphans", severity: 1,
                             title: orphans.count == 1 ? "Un server di sviluppo orfano" : "\(orphans.count) server di sviluppo orfani",
                             detail: orphans.map { ":\($0.port) \($0.label)" }.joined(separator: " · "),
                             actionTitle: orphans.count == 1 ? "Chiudi" : "Chiudi \(orphans.count)", action: .killPorts(orphans)))
        }
        alerts = out
    }

    func restart(_ g: AppGroup) {
        guard !restarting.contains(g.key) else { return }
        restarting.insert(g.key); restartFailed.remove(g.key)
        relaunch(g) { [weak self] ok in
            self?.restarting.remove(g.key)
            if !ok { self?.restartFailed.insert(g.key) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.refreshDetails() }
        }
    }

    func perform(_ a: Alert.Action, openTab: (String) -> Void) {
        switch a {
        case .quitApp(let g): terminate(g, force: false)
        case .killPorts(let ps): ps.forEach { killProcess($0.pid) }
        case .openTab(let t): openTab(t)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.refreshDetails() }
    }
}

// ================================================================ formattazione
func formatBytes(_ b: UInt64, decimals: Int = 1) -> String {
    let v = Double(b), kb = 1024.0, mb = kb * 1024, gb = mb * 1024, tb = gb * 1024
    if v >= tb { return String(format: "%.\(decimals)f TB", v / tb) }
    if v >= gb { return String(format: "%.\(decimals)f GB", v / gb) }
    if v >= mb { return String(format: "%.0f MB", v / mb) }
    if v >= kb { return String(format: "%.0f KB", v / kb) }
    return "\(b) B"
}

func formatRate(_ bps: Double, compact: Bool = false) -> String {
    let u = compact ? ["B", "K", "M", "G"] : ["B/s", "KB/s", "MB/s", "GB/s"]
    var v = bps, i = 0
    while v >= 1000 && i < u.count - 1 { v /= 1024; i += 1 }
    if i == 0 { return "\(Int(v))\(compact ? "" : " ")\(u[0])" }
    return String(format: v < 10 ? "%.1f%@%@" : "%.0f%@%@", v, compact ? "" : " ", u[i])
}

func formatPercent(_ f: Double) -> String { "\(Int((f * 100).rounded()))%" }

func formatTemp(_ c: Double, fahrenheit: Bool) -> String {
    fahrenheit ? "\(Int((c * 9 / 5 + 32).rounded()))°F" : "\(Int(c.rounded()))°"
}

func formatDuration(_ t: TimeInterval) -> String {
    let m = Int(t / 60), h = m / 60, d = h / 24
    if d > 0 { return "\(d)g \(h % 24)h" }
    if h > 0 { return "\(h)h \(m % 60)m" }
    return "\(max(m, 1))m"
}

extension Color {
    init(hex: String) {
        let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")), radix: 16) ?? 0x4FD1A5
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
