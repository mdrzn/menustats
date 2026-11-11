// MenuStats --screenshots <cartella>: genera le immagini del README con dati dimostrativi
// (nessun dato reale del Mac finisce nelle immagini pubblicate).
import AppKit
import SwiftUI

enum Screenshots {
    static func run(_ out: URL) {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        Prefs.persist = false
        Monitor.demoMode = true
        let m = Monitor.shared
        applyArgs()
        fillDemo(m)
        for tab in ["home", "apps", "system", "volume", "ports", "agents", "awake", "network"] {
            Nav.shared.tab = tab
            save(PopoverView(), size: CGSize(width: 480, height: 620), to: out.appendingPathComponent("tab-\(tab).png"), rounded: 14)
        }
        let current = Prefs.shared.c.theme
        for t in [ThemeChoice.graphite, .midnight, .paper, .contrast] {
            Prefs.shared.c.theme = t
            Nav.shared.tab = "home"
            save(PopoverView(), size: CGSize(width: 480, height: 620), to: out.appendingPathComponent("theme-\(t.rawValue).png"), rounded: 14)
        }
        Prefs.shared.c.theme = current
        save(LooksSheet(), size: CGSize(width: 560, height: CGFloat(MenuLook.allCases.count) * 46 + 16), to: out.appendingPathComponent("looks.png"), rounded: 12)
        save(SettingsView(), size: CGSize(width: 640, height: 600), to: out.appendingPathComponent("settings.png"), rounded: 12)
        save(AppLogo(size: 256).padding(0), size: CGSize(width: 256, height: 256), to: out.appendingPathComponent("logo.png"), rounded: 0, opaque: false)
        print("ok \(out.path)")
    }

    // Rende la vista in una finestra fuori schermo (cosi' anche i controlli AppKit vengono disegnati)
    static func save<V: View>(_ view: V, size: CGSize, to url: URL, rounded: CGFloat, opaque: Bool = true) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).clipShape(RoundedRectangle(cornerRadius: rounded, style: .continuous)))
        host.frame = NSRect(origin: .zero, size: size)
        let w = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height), styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear
        w.appearance = NSAppearance(named: Theme.dark ? .darkAqua : .aqua)
        w.contentView = host
        w.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))     // lascia completare il layout e le task asincrone
        host.display()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        w.orderOut(nil)
    }

    // --theme graphite|midnight|paper|contrast  --lang it|en   (per provare temi e lingue)
    static func applyArgs() {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--theme"), i + 1 < a.count, let t = ThemeChoice(rawValue: a[i + 1]) { Prefs.shared.c.theme = t }
        if let i = a.firstIndex(of: "--lang"), i + 1 < a.count { Prefs.shared.c.language = a[i + 1] == "en" ? .english : .italian }
    }

    static func wave(_ n: Int, base: Double, amp: Double, seed: Double) -> [Double] {
        (0..<n).map { i in max(0, base + amp * (sin(Double(i) / 5 + seed) * 0.6 + sin(Double(i) / 2.3 + seed * 2) * 0.4)) }
    }

    static func fillDemo(_ m: Monitor) {
        let gb: UInt64 = 1 << 30
        m.hostName = "MacBook Pro"
        m.cpu = 0.24; m.cpuUser = 0.17; m.cpuSystem = 0.07
        m.perCore = [0.42, 0.31, 0.55, 0.22, 0.12, 0.08, 0.36, 0.18, 0.05, 0.09]
        m.cpuHistory.values = wave(90, base: 0.22, amp: 0.12, seed: 1)
        m.memory.total = 32 * gb; m.memory.app = 11 * gb; m.memory.wired = 3 * gb; m.memory.compressed = gb + gb / 2
        m.memory.used = m.memory.app + m.memory.wired + m.memory.compressed; m.memory.cached = 9 * gb; m.memory.swapUsed = 0
        m.memHistory.values = wave(90, base: 0.48, amp: 0.02, seed: 2)
        m.down = 1_850_000; m.up = 92_000
        m.downHistory.values = wave(90, base: 900_000, amp: 900_000, seed: 3)
        m.upHistory.values = wave(90, base: 80_000, amp: 60_000, seed: 4)
        m.gpu = 0.11; m.gpuHistory.values = wave(90, base: 0.1, amp: 0.06, seed: 5)
        m.disk = DiskInfo(total: 994 * Int64(gb), free: 412 * Int64(gb))
        m.sensors.temperatures = (1...8).map { SensorReading(name: "PMU tdie\($0)", value: 44 + Double($0 % 4) * 1.7) } + [SensorReading(name: "NAND CH0 temp", value: 37)]
        m.sensors.fans = [(1240, 1000, 4900)]
        m.sensors.systemPower = 14.2
        m.tempHistory.values = wave(90, base: 48, amp: 3, seed: 6)
        m.battery = nil

        func proc(_ pid: Int32, _ name: String, _ path: String, _ cpu: Double, _ mem: Double) -> ProcessSample {
            ProcessSample(pid: pid, ppid: 1, name: name, path: path, cpu: cpu, memory: UInt64(mem * Double(1 << 20)), threads: 24,
                          cpuTime: 3_400, startedAt: Date().addingTimeInterval(-26_000))
        }
        func group(_ name: String, _ path: String, _ procs: [ProcessSample]) -> AppGroup {
            AppGroup(key: path, name: name, bundlePath: path, processes: procs)
        }
        let safariCPU: [Double] = [6.1, 3.2, 2.4, 1.1, 0.8, 0.4, 0.3, 0.2, 0.1]
        let safariMem: [Double] = [420, 610, 380, 240, 190, 120, 90, 70, 50]
        var safari: [ProcessSample] = []
        for i in 0..<9 {
            let name = i == 0 ? "Safari" : "Safari Web Content"
            safari.append(proc(Int32(400 + i), name, "/Applications/Safari.app/Contents/MacOS/Safari", safariCPU[i], safariMem[i]))
        }
        m.apps = [
            group("Safari", "/Applications/Safari.app", safari),
            group(L("Terminale"), "/System/Applications/Utilities/Terminal.app", [proc(510, "Terminal", "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", 4.8, 310), proc(511, "node", "/opt/homebrew/bin/node", 3.1, 640)]),
            group(L("Musica"), "/System/Applications/Music.app", [proc(620, "Music", "/System/Applications/Music.app/Contents/MacOS/Music", 2.2, 280)]),
            group(L("Note"), "/System/Applications/Notes.app", [proc(630, "Notes", "/System/Applications/Notes.app/Contents/MacOS/Notes", 0.6, 190)]),
            group(L("Anteprima"), "/System/Applications/Preview.app", [proc(640, "Preview", "/System/Applications/Preview.app/Contents/MacOS/Preview", 0.2, 120)]),
            group("Finder", "/System/Library/CoreServices/Finder.app", [proc(650, "Finder", "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder", 0.1, 160)]),
        ]
        m.processes = m.apps.flatMap(\.processes)
        m.ports = [
            ListeningPort(port: 3000, pid: 711, command: "node", address: "127.0.0.1", label: "next dev", project: "shop-frontend", owner: "Claude Code"),
            ListeningPort(port: 4000, pid: 712, command: "node", address: "*", label: "api", project: "shop-backend", owner: "Codex"),
            ListeningPort(port: 5173, pid: 713, command: "node", address: "127.0.0.1", label: "vite", project: "docs", owner: L("Terminale"), orphan: true),
            ListeningPort(port: 5432, pid: 714, command: "com.docker", address: "*", label: "postgres", project: "postgres:17", owner: "Docker"),
        ]
        m.agents = [
            AgentSession(pid: 701, kind: "Claude Code", cwd: NSHomeDirectory() + "/code/shop-frontend", startedAt: Date().addingTimeInterval(-4_700),
                         cpu: 12.4, memory: 780 << 20, children: 5, ports: [3000], terminal: L("Terminale")),
            AgentSession(pid: 702, kind: "Codex", cwd: NSHomeDirectory() + "/code/shop-backend", startedAt: Date().addingTimeInterval(-1_300),
                         cpu: 0.3, memory: 210 << 20, children: 2, ports: [4000], terminal: "Ghostty"),
        ]
        var info = ClaudeSessionInfo(file: "")
        info.model = "claude-opus-5-5"
        info.inputTokens = 18_400; info.outputTokens = 212_000; info.cacheReadTokens = 9_800_000; info.cacheWriteTokens = 640_000
        info.lastText = L("Fatto: la pagina di checkout ora controlla il CAP e i test passano. Apro una pull request?")
        info.lastActivity = Date()
        m.agents[0].claude = info
        m.containers = [Container(id: "a1", name: "postgres", image: "postgres:17", status: "Up 3 hours", running: true, ports: "", hostPorts: [5432]),
                        Container(id: "a2", name: "redis", image: "redis:7-alpine", status: "Exited", running: false, ports: "", hostPorts: [])]
        m.traffic = [AppTraffic(name: "Safari", down: 1_420_000, up: 41_000), AppTraffic(name: L("Musica"), down: 320_000, up: 6_000),
                     AppTraffic(name: "node", down: 64_000, up: 38_000), AppTraffic(name: "mDNSResponder", down: 2_000, up: 1_000)]
        m.wifi = WiFiInfo(ssid: "Studio", rssi: -52, noise: -92, txRate: 866, band: "5 GHz")
        m.vpns = [("utun3", "100.64.0.12")]
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        HistoryStore.shared.daily = [df.string(from: Date()): [2.4e9, 3.1e8], df.string(from: Date().addingTimeInterval(-86_400)): [5.2e9, 9e8]]
        m.blockers = [SleepBlocker(pid: 620, process: "Music", name: L("Riproduzione audio"), type: "sistema")]
        m.alerts = [Alert(id: "orph", severity: 1, title: L("Un server di sviluppo orfano"), detail: ":5173 vite · docs", actionTitle: L("Chiudi"), action: .killPorts([])),
                    Alert(id: "hog", severity: 1, title: L("%@ usa molta CPU", "Safari"), detail: L("%@ da un po'", "140%"), actionTitle: L("Chiudi"), action: .openTab("apps"))]
        let speakers = AudioDevice(id: 1, uid: "demo-out", name: "Altoparlanti Mac", hasOutput: true, hasInput: false)
        let mic = AudioDevice(id: 2, uid: "demo-in", name: "Microfono MacBook", hasOutput: false, hasInput: true)
        m.outputDevices = [speakers]; m.inputDevices = [mic]; m.outputID = 1; m.inputID = 2; m.outputVolume = 0.62
        m.audioApps = [
            AudioApp(key: "com.apple.Music", name: L("Musica"), icon: NSWorkspace.shared.icon(forFile: "/System/Applications/Music.app"), objects: [], playing: true, recording: false),
            AudioApp(key: "com.apple.Safari", name: "Safari", icon: NSWorkspace.shared.icon(forFile: "/Applications/Safari.app"), objects: [], playing: true, recording: false),
            AudioApp(key: "com.apple.FaceTime", name: "FaceTime", icon: NSWorkspace.shared.icon(forFile: "/System/Applications/FaceTime.app"), objects: [], playing: false, recording: true),
        ]
        var c = Prefs.shared.c
        c.perAppVolume = true
        c.appVolumes = ["com.apple.Music": 0.45, "com.apple.Safari": 1.0, "com.apple.FaceTime": 1.3]
        c.modules = [.cpu, .memory, .network, .temperature]
        Prefs.shared.c = c          // solo in memoria (Prefs.persist = false)
        m.awake.start(minutes: 83)
    }
}

// MenuStats --icon <cartella.iconset>: icona dell'app a tutte le dimensioni (poi iconutil -> .icns)
extension Screenshots {
    static func icon(_ out: URL) {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = CGFloat(base * scale)
                // margine e ombra come le icone di macOS
                let view = ZStack {
                    AppLogo(size: px * 0.8).shadow(color: .black.opacity(0.35), radius: px * 0.02, y: px * 0.012)
                }.frame(width: px, height: px)
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                save(view, size: CGSize(width: px, height: px), to: out.appendingPathComponent(name), rounded: 0, opaque: false)
            }
        }
    }
}

// Tutti i look della barra uno sotto l'altro
struct LooksSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(MenuLook.allCases) { look in
                HStack {
                    Text(look.title).font(.ui(12, .semibold)).foregroundStyle(Theme.secondary).frame(width: 90, alignment: .leading)
                    MenuBarPreview(config: { var c = Prefs.shared.c; c.look = look; c.valueColor = look == .pill ? .menuBar : (look == .graph ? .accent : .menuBar); return c }())
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
    }
}

// ================================================================ GIF dimostrative
// MenuStats --gifs <cartella>: fotogrammi PNG per scena (poi make-gifs.sh li unisce con ffmpeg).
// I dati demo vengono fatti evolvere a ogni fotogramma, cosi' grafici e valori si muovono.
final class FrameRecorder {
    let host: NSHostingView<AnyView>
    let window: NSWindow
    let size: CGSize

    init<V: View>(_ view: V, size: CGSize, rounded: CGFloat) {
        self.size = size
        host = NSHostingView(rootView: AnyView(view.frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: rounded, style: .continuous))))
        host.frame = NSRect(origin: .zero, size: size)
        window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear
        window.appearance = NSAppearance(named: Theme.dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    }

    func capture(_ url: URL) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))   // lascia a SwiftUI il tempo di ridisegnare
        host.layoutSubtreeIfNeeded()
        host.display()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    func close() { window.orderOut(nil) }
}

extension Screenshots {
    static func gifs(_ out: URL) {
        let fm = FileManager.default
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        Prefs.persist = false
        Monitor.demoMode = true
        let m = Monitor.shared
        applyArgs()
        fillDemo(m)
        var t = 0
        func scene(_ name: String) -> URL {
            let d = out.appendingPathComponent(name)
            try? fm.removeItem(at: d); try? fm.createDirectory(at: d, withIntermediateDirectories: true)
            return d
        }
        let popover = CGSize(width: 480, height: 620)

        // 1. giro delle schede
        var dir = scene("tour")
        Nav.shared.tab = "home"
        var rec = FrameRecorder(PopoverView(), size: popover, rounded: 14)
        var n = 0
        for tab in ["home", "apps", "system", "ports", "agents", "volume", "awake"] {
            Nav.shared.tab = tab
            for _ in 0..<13 { evolve(m, t); t += 1; rec.capture(dir.appendingPathComponent(String(format: "%04d.png", n))); n += 1 }
        }
        rec.close()

        // 2. panoramica dal vivo
        dir = scene("overview")
        Nav.shared.tab = "home"
        rec = FrameRecorder(PopoverView(), size: popover, rounded: 14)
        for i in 0..<40 { evolve(m, t); t += 1; rec.capture(dir.appendingPathComponent(String(format: "%04d.png", i))) }
        rec.close()

        // 3. barra dei menu: i look uno dopo l'altro
        dir = scene("menubar")
        let bar = MenuBarShowcase()
        rec = FrameRecorder(bar, size: CGSize(width: 620, height: 150), rounded: 14)
        n = 0
        for look in MenuLook.allCases {
            MenuBarShowcase.look = look
            Prefs.shared.objectWillChange.send()
            for _ in 0..<10 { evolve(m, t); t += 1; rec.capture(dir.appendingPathComponent(String(format: "%04d.png", n))); n += 1 }
        }
        rec.close()

        // 4. volume per app: i cursori si spostano
        dir = scene("volume")
        Nav.shared.tab = "volume"
        rec = FrameRecorder(PopoverView(), size: popover, rounded: 14)
        for i in 0..<40 {
            let f = Double(i) / 39
            let ease = f < 0.5 ? 2 * f * f : 1 - pow(-2 * f + 2, 2) / 2
            Prefs.shared.c.appVolumes["com.apple.Music"] = 1.0 - 0.6 * ease
            Prefs.shared.c.appVolumes["com.apple.FaceTime"] = 1.0 + 0.35 * ease
            m.objectWillChange.send()
            evolve(m, t); t += 1
            rec.capture(dir.appendingPathComponent(String(format: "%04d.png", i)))
        }
        rec.close()
        print("ok \(out.path)")
    }

    // Fa evolvere i dati demo di un passo (curve morbide e deterministiche)
    static func evolve(_ m: Monitor, _ i: Int) {
        let t = Double(i)
        m.cpu = max(0.04, 0.24 + 0.12 * sin(t / 7) + 0.05 * sin(t / 2.1))
        m.cpuUser = m.cpu * 0.7; m.cpuSystem = m.cpu * 0.3
        m.perCore = (0..<10).map { k in max(0.02, min(1, m.cpu * (1.6 - Double(k) * 0.12) + 0.12 * sin(t / 3 + Double(k)))) }
        m.cpuHistory.add(m.cpu)
        m.memory.app = UInt64((11 + 0.4 * sin(t / 20)) * Double(1 << 30))
        m.memory.used = m.memory.app + m.memory.wired + m.memory.compressed
        m.memHistory.add(m.memory.fraction)
        m.down = max(20_000, 1_200_000 + 1_000_000 * sin(t / 4) + 500_000 * sin(t / 1.7))
        m.up = max(4_000, 70_000 + 50_000 * sin(t / 3 + 1))
        m.downHistory.add(m.down); m.upHistory.add(m.up)
        m.gpu = max(0.02, 0.11 + 0.07 * sin(t / 5)); m.gpuHistory.add(m.gpu ?? 0)
        let temp = 48 + 3 * sin(t / 9)
        m.sensors.temperatures = m.sensors.temperatures.map { SensorReading(name: $0.name, value: $0.name.contains("NAND") ? 37 : temp - 2 + Double($0.name.count % 3)) }
        m.tempHistory.add(temp)
        m.sensors.systemPower = 13 + 3 * sin(t / 6)
        if !m.apps.isEmpty {
            m.apps[0].processes[0].cpu = 6 + 4 * sin(t / 5)
            m.apps[1].processes[1].cpu = 3 + 2.5 * sin(t / 4 + 2)
        }
        if !m.agents.isEmpty { m.agents[0].cpu = 8 + 6 * sin(t / 3) }
    }
}

// Barra dei menu grande su uno sfondo, con il nome del look
struct MenuBarShowcase: View {
    static var look: MenuLook = .stacked
    @ObservedObject var s = Prefs.shared
    @ObservedObject var m = Monitor.shared
    var body: some View {
        let config: Config = { var c = s.c; c.look = Self.look; c.valueColor = Self.look == .graph ? .accent : .menuBar; return c }()
        VStack(spacing: 14) {
            MenuBarPreview(config: config, height: 30)
                .scaleEffect(1.5)
                .frame(width: 400, height: 46)
            HStack(spacing: 6) {
                ForEach(MenuLook.allCases) { l in
                    Text(l.title).font(.ui(11, l == Self.look ? .semibold : .medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .foregroundStyle(l == Self.look ? Theme.text : Theme.tertiary)
                        .background(Capsule().fill(l == Self.look ? s.accent.opacity(0.25) : .clear))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Color(hex: "1E2430"), Color(hex: "0F1115")], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
