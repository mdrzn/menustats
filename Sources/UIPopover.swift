// Popover principale: barra laterale + schede. Questo file: guscio, Panoramica, App, Sistema.
import SwiftUI
import AppKit

struct TabInfo: Identifiable { let id: String; let title: String; let symbol: String }

let tabs: [TabInfo] = [
    TabInfo(id: "home", title: "Home", symbol: "square.grid.2x2"),
    TabInfo(id: "apps", title: "App", symbol: "list.bullet.rectangle"),
    TabInfo(id: "system", title: "Sistema", symbol: "cpu"),
    TabInfo(id: "network", title: "Rete", symbol: "network"),
    TabInfo(id: "volume", title: "Volume", symbol: "speaker.wave.2"),
    TabInfo(id: "ports", title: "Porte", symbol: "point.3.connected.trianglepath.dotted"),
    TabInfo(id: "agents", title: "Agenti", symbol: "sparkles"),
    TabInfo(id: "awake", title: "Sveglio", symbol: "cup.and.saucer"),
]

// Navigazione condivisa (la usano anche gli avvisi e la scorciatoia)
final class Nav: ObservableObject {
    static let shared = Nav()
    @Published var tab = Prefs.shared.c.lastTab { didSet { Prefs.shared.c.lastTab = tab } }
}

struct PopoverView: View {
    @ObservedObject var m = Monitor.shared
    @ObservedObject var s = Prefs.shared
    @ObservedObject var nav = Nav.shared
    var accent: Color { s.accent }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(tab: $nav.tab, accent: accent, badges: ["ports": m.ports.count, "agents": m.agents.count])
            Rectangle().fill(Theme.stroke).frame(width: 1)
            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    content.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                }
                Footer(accent: accent)
            }
        }
        .frame(width: 480, height: 620)
        .background(LinearGradient(colors: [Theme.backgroundTop, Theme.background], startPoint: .top, endPoint: .bottom))
        .foregroundStyle(Theme.text)
        .environment(\.colorScheme, .dark)
        .tint(accent)
        .onChange(of: nav.tab) { _, t in m.trafficVisible = t == "network" }
        .onAppear { m.trafficVisible = nav.tab == "network" }
    }

    @ViewBuilder var content: some View {
        switch nav.tab {
        case "apps": AppsTab()
        case "system": SystemTab()
        case "network": NetworkTab()
        case "volume": VolumeTab()
        case "ports": PortsTab()
        case "agents": AgentsTab()
        case "awake": AwakeTab()
        default: HomeTab()
        }
    }
}

struct Sidebar: View {
    @Binding var tab: String
    let accent: Color
    let badges: [String: Int]
    var body: some View {
        VStack(spacing: 4) {
            ForEach(tabs) { t in
                SidebarItem(info: t, selected: tab == t.id, accent: accent, badge: badges[t.id] ?? 0) { tab = t.id }
            }
            Spacer()
        }
        .padding(.vertical, 10).padding(.horizontal, 6)
        .frame(width: 66)
        .background(Theme.sidebar.opacity(0.7))
    }
}

struct SidebarItem: View {
    let info: TabInfo
    let selected: Bool
    let accent: Color
    let badge: Int
    let action: () -> Void
    @Local private var hover = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: info.symbol).font(.ui(14, .medium)).frame(height: 18)
                Text(info.title).font(.ui(9, selected ? .semibold : .medium))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            .foregroundStyle(selected ? accent : (hover ? Theme.text : Theme.secondary))
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selected ? accent.opacity(0.15) : (hover ? Color.white.opacity(0.05) : .clear)))
            .overlay(alignment: .topTrailing) {
                if badge > 0 {
                    Text("\(badge)").font(.ui(8.5, .bold)).foregroundStyle(.black.opacity(0.8))
                        .padding(.horizontal, 4).frame(minWidth: 14, minHeight: 14)
                        .background(Capsule().fill(accent)).offset(x: -4, y: 2)
                }
            }
        }
        .buttonStyle(.plain).focusEffectDisabled().onHover { hover = $0 }
    }
}

struct Footer: View {
    @ObservedObject var m = Monitor.shared
    let accent: Color
    var body: some View {
        HStack(spacing: 8) {
            Text("MenuStats").font(.ui(10.5, .semibold)).foregroundStyle(Theme.secondary)
            Text("\(String(format: "%.1f", m.selfUsage.cpu * 100))% · \(formatBytes(m.selfUsage.memory))")
                .font(.number(10, .medium)).foregroundStyle(Theme.tertiary)
            Spacer()
            Text("\(chipName) · acceso da \(formatDuration(m.uptime))").font(.ui(10)).foregroundStyle(Theme.tertiary)
            IconButton(symbol: "gearshape", help: "Impostazioni") { AppDelegate.shared?.openSettings() }
            IconButton(symbol: "power", help: "Esci da MenuStats") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Color.black.opacity(0.22))
        .overlay(alignment: .top) { Rectangle().fill(Theme.stroke).frame(height: 1) }
    }
}

struct TabHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.ui(16, .bold))
            if let subtitle { Text(subtitle).font(.ui(11)).foregroundStyle(Theme.tertiary) }
            Spacer()
            trailing
        }.padding(.bottom, 2)
    }
}

extension TabHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) { self.title = title; self.subtitle = subtitle; self.trailing = EmptyView() }
}

// ================================================================ Panoramica
struct HomeTab: View {
    @ObservedObject var m = Monitor.shared
    @ObservedObject var s = Prefs.shared
    var accent: Color { s.accent }
    let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TabHeader(title: "Panoramica", subtitle: m.hostName)
            LazyVGrid(columns: cols, spacing: 8) {
                MetricTile(label: "CPU", detail: "\(m.perCore.count) core", value: "\(Int(m.cpu * 100))", unit: "%",
                           history: m.cpuHistory.values, color: accent)
                MetricTile(label: "GPU", detail: chipName, value: m.gpu.map { "\(Int($0 * 100))" } ?? "–", unit: "%",
                           history: m.gpuHistory.values, color: accent)
                MetricTile(label: "MEMORIA", detail: "su \(formatBytes(m.memory.total, decimals: 0))",
                           value: String(format: "%.1f", Double(m.memory.used) / 1_073_741_824), unit: "GB",
                           history: m.memHistory.values, color: m.memory.pressure == .normal ? accent : Theme.warning)
                MetricTile(label: "RETE", detail: "↑ \(formatRate(m.up, compact: true))", value: "↓" + formatRate(m.down, compact: true),
                           history: m.downHistory.values, maxValue: nil, color: accent)
                MetricTile(label: "DISCO", detail: "\(formatBytes(UInt64(max(m.disk.free, 0)), decimals: 0)) liberi",
                           value: "\(Int(m.disk.fraction * 100))", unit: "%", history: Array(repeating: m.disk.fraction, count: 2), color: accent)
                thirdTile
            }
            if !m.alerts.isEmpty { AlertsCard(accent: accent) }
            TopAppsCard()
            HStack(alignment: .top, spacing: 8) {
                AwakeMiniCard()
                if !m.agents.isEmpty { AgentsMiniCard() }
            }
            if !m.ports.isEmpty { PortsMiniCard() }
        }
    }

    @ViewBuilder var thirdTile: some View {
        if let b = m.battery {
            MetricTile(label: "BATTERIA", detail: b.charging ? "in carica" : (b.minutesLeft.map { formatDuration(Double($0 * 60)) } ?? ""),
                       value: "\(Int(b.percent * 100))", unit: "%", history: [b.percent, b.percent], color: accent)
        } else if let t = m.sensors.socTemperature {
            MetricTile(label: "CHIP", detail: m.sensors.systemPower.map { String(format: "%.0f W", $0) } ?? "",
                       value: formatTemp(t, fahrenheit: s.c.fahrenheit), history: m.tempHistory.values, maxValue: 110,
                       color: t > 90 ? Theme.danger : t > 75 ? Theme.warning : accent)
        } else {
            MetricTile(label: "SWAP", detail: "", value: formatBytes(m.memory.swapUsed), history: [], color: accent)
        }
    }
}

struct AlertsCard: View {
    @ObservedObject var m = Monitor.shared
    let accent: Color
    var body: some View {
        Card(title: "Da controllare", trailing: "\(m.alerts.count)", tint: Theme.warning) {
            VStack(spacing: 6) {
                ForEach(m.alerts) { a in
                    HStack(spacing: 8) {
                        Dot(color: a.severity > 1 ? Theme.danger : Theme.warning)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.title).font(.ui(11.5, .semibold))
                            Text(a.detail).font(.ui(10)).foregroundStyle(Theme.secondary).lineLimit(1)
                        }
                        Spacer()
                        if let t = a.actionTitle, let act = a.action {
                            PillButton(title: t, color: Theme.warning, prominent: true) { m.perform(act) { Nav.shared.tab = $0 } }
                        }
                    }
                }
            }
        }
    }
}

struct TopAppsCard: View {
    @ObservedObject var m = Monitor.shared
    var body: some View {
        Card(title: "App più attive", trailing: "CPU · MEMORIA") {
            VStack(spacing: 2) {
                ForEach(m.apps.prefix(5)) { g in
                    HoverRow {
                        HStack(spacing: 8) {
                            AppIconView(path: g.bundlePath, size: 16)
                            Text(g.name).font(.ui(11.5, .medium)).lineLimit(1)
                            if g.processes.count > 1 { Text("\(g.processes.count)").font(.ui(10)).foregroundStyle(Theme.tertiary) }
                            Spacer()
                            Text(String(format: "%.1f%%", g.cpu)).font(.number(11)).frame(width: 52, alignment: .trailing)
                            Text(formatBytes(g.memory)).font(.number(11, .regular)).foregroundStyle(Theme.secondary).frame(width: 58, alignment: .trailing)
                        }
                    }
                }
                if m.apps.isEmpty { Text("Raccolta dati…").font(.ui(11)).foregroundStyle(Theme.tertiary) }
            }
        }
    }
}

struct AwakeMiniCard: View {
    @ObservedObject var awake = Monitor.shared.awake
    @ObservedObject var s = Prefs.shared
    var body: some View {
        Card(title: "Tieni sveglio") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(awake.isActive ? "Attivo" : "Spento").font(.ui(12.5, .semibold))
                        .foregroundStyle(awake.isActive ? s.accent : Theme.text)
                    Text(awake.isActive ? (awake.remaining.map { "ancora \(formatDuration($0))" } ?? "senza limite") : "il Mac va in stop normalmente")
                        .font(.ui(10)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { awake.isActive }, set: { $0 ? awake.start(minutes: nil) : awake.stop() }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
        }
    }
}

struct AgentsMiniCard: View {
    @ObservedObject var m = Monitor.shared
    var body: some View {
        Card(title: "Agenti", trailing: "\(m.agents.count)") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(m.agents.prefix(3)) { a in
                    HStack(spacing: 6) {
                        Dot(color: a.isBusy ? Prefs.shared.accent : Theme.tertiary, size: 5)
                        Text(a.project).font(.ui(11, .medium)).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(a.kind).font(.ui(9.5)).foregroundStyle(Theme.tertiary).lineLimit(1)
                    }
                }
            }
        }
        .onTapGesture { Nav.shared.tab = "agents" }
    }
}

struct PortsMiniCard: View {
    @ObservedObject var m = Monitor.shared
    var body: some View {
        Card(title: "Porte in ascolto", trailing: "\(m.ports.count)") {
            VStack(spacing: 2) {
                ForEach(m.ports.prefix(4)) { p in PortRow(p: p, compact: true) }
            }
        }
    }
}

// ================================================================ App
struct AppsTab: View {
    @ObservedObject var m = Monitor.shared
    @Local private var query = ""
    @Local private var byMemory = false
    @Local private var expanded: Set<String> = []
    @Local private var inspected: pid_t?

    var groups: [AppGroup] {
        let list = query.isEmpty ? m.apps : m.apps.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.processes.contains { $0.name.localizedCaseInsensitiveContains(query) }
        }
        return byMemory ? list.sorted { $0.memory > $1.memory } : list.sorted { $0.cpu > $1.cpu }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TabHeader(title: "App", subtitle: "\(m.apps.filter { $0.bundlePath != nil }.count) app · \(m.processes.count) processi")
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.ui(11)).foregroundStyle(Theme.tertiary)
                    TextField("Cerca app o processo", text: $query).textFieldStyle(.plain).font(.ui(11.5))
                }
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
                Segmented(options: [(false, "CPU"), (true, "Memoria")], selection: $byMemory, accent: Prefs.shared.accent).frame(width: 130)
            }
            Card {
                VStack(spacing: 1) {
                    HStack {
                        SectionLabel("App / processo"); Spacer()
                        SectionLabel("CPU").frame(width: 52, alignment: .trailing)
                        SectionLabel("Mem").frame(width: 60, alignment: .trailing)
                    }.padding(.horizontal, 6).padding(.bottom, 3)
                    ForEach(groups.prefix(60)) { g in groupRow(g) }
                }
            }
        }
    }

    @ViewBuilder func groupRow(_ g: AppGroup) -> some View {
        let open = expanded.contains(g.key)
        HoverRow {
            HStack(spacing: 7) {
                Image(systemName: "chevron.right").font(.ui(8, .bold)).foregroundStyle(Theme.tertiary)
                    .rotationEffect(.degrees(open ? 90 : 0)).opacity(g.processes.count > 1 ? 1 : 0)
                AppIconView(path: g.bundlePath, size: 16)
                Text(g.name).font(.ui(11.5, .medium)).lineLimit(1)
                if g.processes.count > 1 { Text("\(g.processes.count)").font(.ui(10)).foregroundStyle(Theme.tertiary) }
                Spacer()
                Text(String(format: "%.1f%%", g.cpu)).font(.number(11)).frame(width: 52, alignment: .trailing)
                Text(formatBytes(g.memory)).font(.number(11, .regular)).foregroundStyle(Theme.secondary).frame(width: 60, alignment: .trailing)
            }
        }
        .onTapGesture {
            if g.processes.count > 1 { if open { expanded.remove(g.key) } else { expanded.insert(g.key) } }
            else { inspected = inspected == g.mainPID ? nil : g.mainPID }
        }
        .contextMenu {
            if g.bundlePath != nil { Button("Riavvia") { m.restart(g) } }
            Button("Esci") { terminate(g, force: false) }
            Button("Forza uscita") { terminate(g, force: true) }
            if let b = g.bundlePath { Button("Mostra nel Finder") { NSWorkspace.shared.selectFile(b, inFileViewerRootedAtPath: "") } }
        }
        if g.processes.count == 1, inspected == g.mainPID { ProcessInspector(pid: g.mainPID, group: g).padding(.leading, 22) }
        if open {
            ForEach(g.processes.sorted { $0.cpu > $1.cpu }.prefix(25)) { p in
                HoverRow {
                    HStack {
                        Text(p.name).font(.ui(11)).foregroundStyle(Theme.secondary).lineLimit(1).padding(.leading, 30)
                        Text("\(p.pid)").font(.mono(9.5)).foregroundStyle(Theme.tertiary)
                        Spacer()
                        Text(String(format: "%.1f%%", p.cpu)).font(.number(10.5, .regular)).frame(width: 52, alignment: .trailing)
                        Text(formatBytes(p.memory)).font(.number(10.5, .regular)).foregroundStyle(Theme.tertiary).frame(width: 60, alignment: .trailing)
                    }
                }
                .onTapGesture { inspected = inspected == p.pid ? nil : p.pid }
                .contextMenu {
                    Button("Termina") { killProcess(p.pid) }
                    Button("Forza chiusura") { killProcess(p.pid, force: true) }
                }
                if inspected == p.pid { ProcessInspector(pid: p.pid, group: g).padding(.leading, 30) }
            }
        }
    }
}

// Dettagli di un processo: firma, team, runtime protetto, sandbox, architettura
struct ProcessInspector: View {
    let pid: pid_t
    var group: AppGroup? = nil
    @ObservedObject var m = Monitor.shared
    @Local private var sig: SignatureInfo?
    @Local private var info: ProcessSample?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let sig {
                HStack(spacing: 6) {
                    Image(systemName: sig.teamID != nil || sig.appleSigned ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(sig.teamID != nil || sig.appleSigned ? Prefs.shared.accent : Theme.warning)
                    Text(sig.signer).font(.ui(11, .semibold)).lineLimit(1)
                }
                if let id = sig.identifier { Text(id).font(.mono(9.5)).foregroundStyle(Theme.tertiary).lineLimit(1) }
                HStack(spacing: 4) {
                    Badge(text: sig.hardenedRuntime ? "Runtime protetto" : "Runtime non protetto", color: sig.hardenedRuntime ? Prefs.shared.accent : Theme.secondary)
                    Badge(text: sig.sandboxed ? "Sandbox" : "Senza sandbox", color: sig.sandboxed ? Prefs.shared.accent : Theme.secondary)
                    if let a = sig.architecture { Badge(text: a, color: a.contains("Rosetta") ? Theme.warning : Theme.secondary) }
                }
                HStack(spacing: 14) {
                    if let t = sig.teamID { mini("Team ID", t) }
                    if let i = info { mini("Tempo CPU", formatDuration(i.cpuTime)); mini("Thread", "\(i.threads)"); mini("Avviato", formatDuration(Date().timeIntervalSince(i.startedAt)) + " fa") }
                }
            } else {
                ProgressView().controlSize(.small)
            }
            if let g = group { actions(g) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.25)))
        .padding(.vertical, 3)
        .task(id: pid) {
            let p = pid
            let s = await Task.detached { signatureInfo(pid: p) }.value
            sig = s
            info = Monitor.shared.processes.first { $0.pid == p }
        }
    }
    // Azioni sull'intera app (tutti i suoi processi)
    @ViewBuilder func actions(_ g: AppGroup) -> some View {
        HStack(spacing: 6) {
            if g.bundlePath != nil {
                PillButton(title: m.restarting.contains(g.key) ? "Riavvio…" : "Riavvia", color: Prefs.shared.accent, prominent: true) { m.restart(g) }
            }
            PillButton(title: "Esci") { terminate(g, force: false); m.refreshDetails() }
            PillButton(title: "Forza uscita", color: Theme.danger) { terminate(g, force: true); m.refreshDetails() }
            Spacer()
            if m.restartFailed.contains(g.key) {
                Text("non si è chiusa: controlla se chiede di salvare").font(.ui(9.5)).foregroundStyle(Theme.warning).lineLimit(1)
            }
        }
        .padding(.top, 2)
    }

    func mini(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.ui(9)).foregroundStyle(Theme.tertiary)
            Text(v).font(.number(10.5, .medium))
        }
    }
}

// ================================================================ Sistema
struct SystemTab: View {
    @ObservedObject var m = Monitor.shared
    @ObservedObject var s = Prefs.shared
    @Local private var allSensors = false
    var accent: Color { s.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TabHeader(title: "Sistema", subtitle: "\(chipName) · macOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion)")
            cpuCard
            memoryCard
            sensorsCard
            HStack(alignment: .top, spacing: 8) {
                Card(title: "Disco") {
                    Text(formatBytes(UInt64(max(m.disk.total - m.disk.free, 0)), decimals: 0)).font(.number(15))
                    Meter(value: m.disk.fraction, color: m.disk.fraction > 0.9 ? Theme.warning : accent)
                    Text("\(formatBytes(UInt64(max(m.disk.free, 0)), decimals: 0)) liberi su \(formatBytes(UInt64(m.disk.total), decimals: 0))")
                        .font(.ui(10)).foregroundStyle(Theme.secondary)
                }
                Card(title: "GPU") {
                    Text(m.gpu.map { formatPercent($0) } ?? "–").font(.number(15))
                    Sparkline(values: m.gpuHistory.values, maxValue: 1, color: accent).frame(height: 22)
                }
            }
            if let b = m.battery {
                Card(title: "Batteria", trailing: b.charging ? "in carica" : (b.onAC ? "alimentatore" : "a batteria")) {
                    HStack { Text(formatPercent(b.percent)).font(.number(15)); Spacer()
                        if let mnt = b.minutesLeft { Text(formatDuration(Double(mnt * 60)) + (b.charging ? " alla carica" : " rimanenti")).font(.ui(10.5)).foregroundStyle(Theme.secondary) } }
                    Meter(value: b.percent, color: b.percent < 0.2 ? Theme.danger : accent)
                }
            }
        }
    }

    var cpuCard: some View {
        Card(title: "Processore", trailing: "\(m.perCore.count) core") {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(formatPercent(m.cpu)).font(.number(22))
                Text("utente \(formatPercent(m.cpuUser)) · sistema \(formatPercent(m.cpuSystem))").font(.ui(10.5)).foregroundStyle(Theme.secondary)
                Spacer()
                Text(thermalText).font(.ui(10.5, .medium)).foregroundStyle(m.thermal == .nominal ? Theme.tertiary : Theme.warning)
            }
            Sparkline(values: m.cpuHistory.values, maxValue: 1, color: accent).frame(height: 30)
            CoreBars(cores: m.perCore, performance: 0, accent: accent).frame(height: 34)
        }
    }

    var thermalText: String {
        switch m.thermal { case .nominal: "temperatura normale"; case .fair: "un po' caldo"; case .serious: "caldo: prestazioni ridotte"; default: "molto caldo" }
    }

    var memoryCard: some View {
        let t = Double(max(m.memory.total, 1))
        let parts: [(Double, Color)] = [(Double(m.memory.app) / t, accent), (Double(m.memory.wired) / t, Color(hex: "A78BFA")),
                                        (Double(m.memory.compressed) / t, Theme.warning)]
        return Card(title: "Memoria", trailing: pressureText) {
            HStack(alignment: .firstTextBaseline) {
                Text(formatBytes(m.memory.used)).font(.number(22))
                Text("su \(formatBytes(m.memory.total, decimals: 0))").font(.ui(10.5)).foregroundStyle(Theme.secondary)
                Spacer()
                if m.memory.swapUsed > 0 { Text("swap \(formatBytes(m.memory.swapUsed))").font(.ui(10.5)).foregroundStyle(Theme.secondary) }
            }
            StackedMeter(parts: parts)
            HStack(spacing: 12) {
                legend("App", m.memory.app, accent)
                legend("Wired", m.memory.wired, Color(hex: "A78BFA"))
                legend("Compr.", m.memory.compressed, Theme.warning)
                legend("Cache", m.memory.cached, Theme.tertiary)
            }
        }
    }

    var pressureText: String {
        switch m.memory.pressure { case .normal: "pressione normale"; case .warning: "pressione alta"; case .critical: "pressione critica" }
    }

    func legend(_ k: String, _ v: UInt64, _ c: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(c).frame(width: 6, height: 6)
            Text(k).font(.ui(10)).foregroundStyle(Theme.secondary)
            Text(formatBytes(v)).font(.number(10, .medium))
        }
    }

    var sensorsCard: some View {
        Card(title: "Sensori", trailing: "sperimentale") {
            if m.sensors.temperatures.isEmpty && m.sensors.fans.isEmpty {
                Text("Sensori non disponibili su questo Mac.").font(.ui(11)).foregroundStyle(Theme.tertiary)
            } else {
                HStack(spacing: 18) {
                    if let t = m.sensors.socTemperature { big("Chip", formatTemp(t, fahrenheit: s.c.fahrenheit), t > 90 ? Theme.danger : t > 75 ? Theme.warning : Theme.text) }
                    if let t = m.sensors.ssdTemperature { big("SSD", formatTemp(t, fahrenheit: s.c.fahrenheit), Theme.text) }
                    if let p = m.sensors.systemPower { big("Consumo", String(format: "%.1f W", p), Theme.text) }
                    ForEach(Array(m.sensors.fans.enumerated()), id: \.offset) { i, f in
                        big(m.sensors.fans.count > 1 ? "Ventola \(i + 1)" : "Ventola", "\(Int(f.actual)) rpm", Theme.text)
                    }
                    Spacer()
                }
                if !m.tempHistory.values.isEmpty {
                    Sparkline(values: m.tempHistory.values, maxValue: 110, color: accent).frame(height: 22)
                }
                Button { withAnimation(.easeOut(duration: 0.15)) { allSensors.toggle() } } label: {
                    HStack(spacing: 4) {
                        Text(allSensors ? "Nascondi i sensori" : "Tutti i sensori (\(m.sensors.temperatures.count))").font(.ui(10.5, .medium))
                        Image(systemName: "chevron.down").font(.ui(8, .bold)).rotationEffect(.degrees(allSensors ? 180 : 0))
                    }.foregroundStyle(Theme.secondary)
                }.buttonStyle(.plain)
                if allSensors {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 3) {
                        ForEach(m.sensors.temperatures) { r in
                            HStack {
                                Text(r.name).font(.mono(9.5)).foregroundStyle(Theme.secondary).lineLimit(1)
                                Spacer()
                                Text(formatTemp(r.value, fahrenheit: s.c.fahrenheit)).font(.number(10, .medium))
                            }
                        }
                    }
                }
            }
        }
    }

    func big(_ k: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.ui(10)).foregroundStyle(Theme.secondary)
            Text(v).font(.number(15)).foregroundStyle(c)
        }
    }
}

// Barre verticali per core
struct CoreBars: View {
    let cores: [Double]
    let performance: Int
    let accent: Color
    var body: some View {
        GeometryReader { g in
            let n = max(cores.count, 1)
            let w = (g.size.width - CGFloat(n - 1) * 3) / CGFloat(n)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(cores.enumerated()), id: \.offset) { _, v in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.06))
                        RoundedRectangle(cornerRadius: 2).fill(accent.opacity(0.35 + 0.65 * v)).frame(height: max(2, g.size.height * CGFloat(v)))
                    }.frame(width: w)
                }
            }
        }
    }
}
