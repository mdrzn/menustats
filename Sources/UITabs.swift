// Schede del popover: Rete, Volume, Porte, Agenti, Sveglio.
import SwiftUI
import AppKit
import CoreAudio

// ================================================================ Rete
struct NetworkTab: View {
    @ObservedObject var m = Monitor.shared
    @ObservedObject var s = Prefs.shared
    var accent: Color { s.accent }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TabHeader(title: "Rete", subtitle: primaryAddresses().first.map { "\($0.iface) · \($0.ip)" })
            Card {
                HStack(spacing: 24) {
                    rate("Download", m.down, "arrow.down", accent)
                    rate("Upload", m.up, "arrow.up", Color(hex: "A78BFA"))
                    Spacer()
                }
                ZStack {
                    Sparkline(values: m.downHistory.values, maxValue: max(m.downHistory.peak, m.upHistory.peak, 1024), color: accent)
                    Sparkline(values: m.upHistory.values, maxValue: max(m.downHistory.peak, m.upHistory.peak, 1024), color: Color(hex: "A78BFA"), fill: false, lineWidth: 1.1)
                }.frame(height: 54)
                HStack {
                    Text("picco ↓ \(formatRate(m.downHistory.peak)) · ↑ \(formatRate(m.upHistory.peak))").font(.ui(10)).foregroundStyle(Theme.tertiary)
                    Spacer()
                    Text("ultimi \(Int(Double(m.downHistory.values.count)))  campioni").font(.ui(10)).foregroundStyle(Theme.tertiary)
                }
            }
            Card(title: "Per app", trailing: "misurato ogni 3 s") {
                if m.traffic.isEmpty {
                    Text("Nessun traffico in questo momento.").font(.ui(11)).foregroundStyle(Theme.tertiary)
                } else {
                    let top = max(m.traffic.first.map { $0.down + $0.up } ?? 1, 1)
                    VStack(spacing: 4) {
                        ForEach(m.traffic.prefix(10)) { t in
                            VStack(spacing: 3) {
                                HStack {
                                    Text(t.name).font(.ui(11.5, .medium)).lineLimit(1)
                                    Spacer()
                                    Text("↓ \(formatRate(t.down))").font(.number(10.5, .regular)).frame(width: 78, alignment: .trailing)
                                    Text("↑ \(formatRate(t.up))").font(.number(10.5, .regular)).foregroundStyle(Theme.secondary).frame(width: 78, alignment: .trailing)
                                }
                                Meter(value: (t.down + t.up) / top, color: accent.opacity(0.7), height: 3)
                            }
                        }
                    }
                }
            }
            Card(title: "Interfacce") {
                ForEach(primaryAddresses(), id: \.iface) { a in KV(k: a.iface == "en0" ? "Ethernet / Wi-Fi (en0)" : a.iface, v: a.ip) }
                if primaryAddresses().isEmpty { Text("Nessuna rete attiva.").font(.ui(11)).foregroundStyle(Theme.tertiary) }
            }
        }
    }
    func rate(_ k: String, _ v: Double, _ sym: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(k, systemImage: sym).font(.ui(10.5, .medium)).foregroundStyle(c)
            Text(formatRate(v)).font(.number(20))
        }
    }
}

// ================================================================ Volume
struct VolumeTab: View {
    @ObservedObject var m = Monitor.shared
    @ObservedObject var s = Prefs.shared
    var accent: Color { s.accent }
    var micUsers: [AudioApp] { m.audioApps.filter(\.recording) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TabHeader(title: "Volume")
            if !micUsers.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill").foregroundStyle(Theme.warning)
                    Text("Microfono in uso da ").font(.ui(11.5)) + Text(micUsers.map(\.name).joined(separator: ", ")).font(.ui(11.5, .semibold))
                    Spacer()
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.warning.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.warning.opacity(0.35)))
            }
            Card(title: "Uscita") {
                devicePicker(m.outputDevices, selected: m.outputID) { setDefaultDevice($0, input: false); m.refreshAudio(rebuild: true) }
                HStack(spacing: 10) {
                    IconButton(symbol: m.outputMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", help: "Muto") {
                        setDeviceMuted(m.outputID, !m.outputMuted); m.refreshAudioLevels()
                    }
                    ThinSlider(value: Binding(get: { Double(m.outputVolume) }, set: { setDeviceVolume(m.outputID, Float($0)); m.outputVolume = Float($0) }), color: accent)
                    Text(formatPercent(Double(m.outputVolume))).font(.number(11)).frame(width: 38, alignment: .trailing)
                }
            }
            Card(title: "Ingresso") {
                devicePicker(m.inputDevices, selected: m.inputID) { setDefaultDevice($0, input: true); m.refreshAudio() }
            }
            appsCard
        }
    }

    func devicePicker(_ list: [AudioDevice], selected: AudioObjectID, set: @escaping (AudioObjectID) -> Void) -> some View {
        Menu {
            ForEach(list) { d in
                Button { set(d.id) } label: { if d.id == selected { Label(d.name, systemImage: "checkmark") } else { Text(d.name) } }
            }
        } label: {
            HStack(spacing: 4) {
                Text(list.first { $0.id == selected }?.name ?? "—").font(.ui(12.5, .semibold))
                Image(systemName: "chevron.down").font(.ui(8, .bold)).foregroundStyle(Theme.secondary)
            }
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    @ViewBuilder var appsCard: some View {
        if !s.c.perAppVolume {
            Card(title: "Volume per app", trailing: "sperimentale") {
                Text("Regola il volume di ogni app da 0 a 150%, senza installare driver. Per farlo MenuStats intercetta il suono dell'app e lo riproduce lui: macOS chiederà il permesso di **registrazione audio di sistema**. Niente viene registrato o salvato.")
                    .font(.ui(11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                HStack { Spacer(); PillButton(title: "Attiva", color: accent, prominent: true) { s.c.perAppVolume = true; m.applyMixer() } }
            }
        } else {
            Card(title: "App", trailing: "\(m.audioApps.filter(\.playing).count) in riproduzione") {
                if m.audioApps.isEmpty { Text("Nessuna app sta usando l'audio.").font(.ui(11)).foregroundStyle(Theme.tertiary) }
                VStack(spacing: 9) {
                    ForEach(m.audioApps) { app in AppVolumeRow(app: app, accent: accent) }
                }
                if let e = m.mixer.lastError { Text(e).font(.ui(10)).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true) }
                HStack {
                    Text("Il volume scelto viene ricordato per ogni app.").font(.ui(10)).foregroundStyle(Theme.tertiary)
                    Spacer()
                    Button("Disattiva") { s.c.perAppVolume = false; m.applyMixer() }.buttonStyle(.plain).font(.ui(10.5)).foregroundStyle(Theme.secondary)
                }
            }
        }
    }
}

struct AppVolumeRow: View {
    @ObservedObject var m = Monitor.shared
    let app: AudioApp
    let accent: Color
    var body: some View {
        let v = m.appVolume(app)
        HStack(spacing: 10) {
            Group {
                if let i = app.icon { Image(nsImage: i).resizable() } else { Image(systemName: "app") }
            }.frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.ui(11.5, .semibold)).lineLimit(1)
                Text(app.playing ? "in riproduzione" : "inattiva").font(.ui(9.5)).foregroundStyle(app.playing ? accent : Theme.tertiary)
            }.frame(width: 104, alignment: .leading)
            ThinSlider(value: Binding(get: { v }, set: { m.setAppVolume(app, $0) }), range: 0...1.5, color: v > 1 ? Theme.warning : accent, marker: 1)
            Text(formatPercent(v)).font(.number(10.5)).frame(width: 38, alignment: .trailing)
            IconButton(symbol: v == 0 ? "speaker.slash.fill" : "speaker.wave.1", help: "Muto") { m.setAppVolume(app, v == 0 ? 1 : 0) }
        }
    }
}

// ================================================================ Porte
struct PortRow: View {
    let p: ListeningPort
    var compact = false
    @ObservedObject var s = Prefs.shared
    @Local private var hover = false
    var body: some View {
        HStack(spacing: 8) {
            Text(":\(p.port)").font(.mono(11.5, .semibold)).foregroundStyle(s.accent).frame(width: 54, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(p.label).font(.ui(11.5, .medium)).lineLimit(1)
                    if let pr = p.project { Text("· \(pr)").font(.ui(10.5)).foregroundStyle(Theme.secondary).lineLimit(1) }
                }
                if !compact {
                    HStack(spacing: 4) {
                        Badge(text: p.isLocalOnly ? "solo locale" : "rete", color: p.isLocalOnly ? Theme.secondary : Theme.warning)
                        if p.orphan { Badge(text: "orfano", color: Theme.danger) }
                        Text("pid \(p.pid)").font(.mono(9)).foregroundStyle(Theme.tertiary)
                    }
                }
            }
            Spacer()
            if hover && !compact {
                if !p.isLocalOnly || true {
                    IconButton(symbol: "safari", help: "Apri nel browser") { NSWorkspace.shared.open(URL(string: "http://localhost:\(p.port)")!) }
                }
                IconButton(symbol: "xmark.circle", help: "Termina il processo") { killProcess(p.pid); Monitor.shared.refreshDetails() }
            } else {
                Text(p.owner ?? p.command).font(.ui(10.5)).foregroundStyle(Theme.tertiary).lineLimit(1)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, compact ? 3 : 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(hover ? Theme.cardHover : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

struct PortsTab: View {
    @ObservedObject var m = Monitor.shared
    @ObservedObject var s = Prefs.shared
    @Local private var showSystem = false
    // le porte dei servizi di macOS (AirPlay, Condivisione…) non interessano quasi mai
    var devPorts: [ListeningPort] { m.ports.filter { !systemServices.contains($0.command) } }
    var sysPorts: [ListeningPort] { m.ports.filter { systemServices.contains($0.command) } }
    let systemServices: Set<String> = ["ControlCenter", "rapportd", "sharingd", "launchd", "remoted", "AirPlayXPCHelper", "WiFiAgent", "identityservicesd"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TabHeader(title: "Porte", subtitle: "\(m.ports.count) in ascolto") {
                IconButton(symbol: "arrow.clockwise", help: "Aggiorna") { m.refreshDetails() }
            }
            Card(title: "Sviluppo", trailing: devPorts.isEmpty ? nil : "passa sopra per le azioni") {
                if devPorts.isEmpty {
                    Text("Nessun server in ascolto. Avvia un progetto e comparirà qui, con la cartella e chi l'ha lanciato.")
                        .font(.ui(11)).foregroundStyle(Theme.tertiary).fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 1) { ForEach(devPorts) { PortRow(p: $0) } }
            }
            if let cs = m.containers {
                Card(title: "Docker", trailing: "\(cs.filter(\.running).count) attivi") {
                    if cs.isEmpty { Text("Nessun container.").font(.ui(11)).foregroundStyle(Theme.tertiary) }
                    ForEach(cs) { c in ContainerRow(c: c) }
                }
            }
            if !sysPorts.isEmpty {
                Card {
                    Button { withAnimation(.easeOut(duration: 0.15)) { showSystem.toggle() } } label: {
                        HStack {
                            SectionLabel("Servizi di macOS (\(sysPorts.count))")
                            Spacer()
                            Image(systemName: "chevron.down").font(.ui(8, .bold)).foregroundStyle(Theme.tertiary).rotationEffect(.degrees(showSystem ? 180 : 0))
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if showSystem { VStack(spacing: 1) { ForEach(sysPorts) { PortRow(p: $0) } } }
                }
            }
        }
    }
}

struct ContainerRow: View {
    let c: Container
    var body: some View {
        HoverRow {
            HStack(spacing: 8) {
                Dot(color: c.running ? Prefs.shared.accent : Theme.tertiary, size: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.name).font(.ui(11.5, .medium))
                    Text(c.image).font(.mono(9.5)).foregroundStyle(Theme.tertiary).lineLimit(1)
                }
                Spacer()
                Text(c.hostPorts.map { ":\($0)" }.joined(separator: " ")).font(.mono(10.5)).foregroundStyle(Prefs.shared.accent)
                PillButton(title: c.running ? "Ferma" : "Avvia") { dockerAction(c.running ? "stop" : "start", c.id) }
            }
        }
    }
}

// ================================================================ Agenti
struct AgentsTab: View {
    @ObservedObject var m = Monitor.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TabHeader(title: "Agenti AI", subtitle: m.agents.isEmpty ? nil : "\(m.agents.filter(\.isBusy).count) al lavoro · \(m.agents.count) sessioni")
            if m.agents.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "sparkles").font(.ui(20)).foregroundStyle(Prefs.shared.accent)
                        Text("Nessuna sessione attiva").font(.ui(12.5, .semibold))
                        Text("Qui compaiono le sessioni di Claude Code, Codex, Gemini CLI, Aider, OpenCode, Cursor Agent, Amp e Goose: cartella del progetto, terminale, risorse usate e porte aperte.")
                            .font(.ui(11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            ForEach(m.agents) { AgentCard(a: $0) }
        }
    }
}

struct AgentCard: View {
    let a: AgentSession
    @ObservedObject var s = Prefs.shared
    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(s.accent.opacity(0.15))
                    Image(systemName: "sparkles").font(.ui(13, .semibold)).foregroundStyle(s.accent)
                }.frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(a.project).font(.ui(13, .semibold)).lineLimit(1)
                        Badge(text: a.kind, color: s.accent)
                    }
                    if let cwd = a.cwd {
                        Text(cwd.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.mono(9.5)).foregroundStyle(Theme.tertiary).lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer()
                HStack(spacing: 5) {
                    Dot(color: a.isBusy ? s.accent : Theme.tertiary, size: 6)
                    Text(a.isBusy ? "al lavoro" : "in attesa").font(.ui(10.5, .medium)).foregroundStyle(a.isBusy ? s.accent : Theme.secondary)
                }
            }
            HStack(spacing: 16) {
                stat("Da", formatDuration(Date().timeIntervalSince(a.startedAt)))
                stat("CPU", String(format: "%.1f%%", a.cpu))
                stat("Memoria", formatBytes(a.memory))
                stat("Processi", "\(a.children + 1)")
                if let t = a.terminal { stat("Terminale", t) }
                Spacer()
            }
            HStack(spacing: 6) {
                ForEach(a.ports, id: \.self) { p in
                    Button { NSWorkspace.shared.open(URL(string: "http://localhost:\(p)")!) } label: { Badge(text: ":\(p)", color: s.accent) }.buttonStyle(.plain)
                }
                Spacer()
                if let cwd = a.cwd {
                    IconButton(symbol: "folder", help: "Apri la cartella") { NSWorkspace.shared.open(URL(fileURLWithPath: cwd)) }
                }
                IconButton(symbol: "xmark.circle", help: "Termina la sessione") { killProcess(a.pid); Monitor.shared.refreshDetails() }
            }
        }
    }
    func stat(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.ui(9.5)).foregroundStyle(Theme.tertiary)
            Text(v).font(.number(11, .medium)).lineLimit(1)
        }
    }
}

// ================================================================ Sveglio
struct AwakeTab: View {
    @ObservedObject var m = Monitor.shared
    @ObservedObject var awake = Monitor.shared.awake
    @ObservedObject var s = Prefs.shared
    let durations: [(Int?, String)] = [(15, "15 min"), (60, "1 ora"), (120, "2 ore"), (240, "4 ore"), (nil, "Sempre")]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TabHeader(title: "Tieni sveglio")
            Card(tint: awake.isActive ? s.accent : nil) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill((awake.isActive ? s.accent : Color.white).opacity(0.12))
                        Image(systemName: awake.isActive ? "cup.and.saucer.fill" : "moon.zzz").font(.ui(18, .medium))
                            .foregroundStyle(awake.isActive ? s.accent : Theme.secondary)
                    }.frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(awake.isActive ? "Il Mac resta sveglio" : "Stop normale").font(.ui(14, .semibold))
                        Text(awake.isActive ? (awake.remaining.map { "ancora \(formatDuration($0))" } ?? "finché non lo spegni")
                             : "Il Mac va in stop secondo le impostazioni di sistema").font(.ui(11)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { awake.isActive }, set: { $0 ? awake.start(minutes: nil) : awake.stop() }))
                        .toggleStyle(.switch).labelsHidden()
                }
                HStack(spacing: 6) {
                    ForEach(Array(durations.enumerated()), id: \.offset) { _, d in
                        PillButton(title: d.1) { awake.start(minutes: d.0) }
                    }
                }
                Segmented(options: [(AwakeController.Mode.system, "Solo il Mac"), (.display, "Mac e schermo")],
                          selection: Binding(get: { awake.mode }, set: { awake.mode = $0; if awake.isActive { awake.start(minutes: awake.remaining.map { Int($0 / 60) }) } }),
                          accent: s.accent)
            }
            Card(title: "Chi impedisce lo stop", trailing: m.blockers.isEmpty ? nil : "\(m.blockers.count)") {
                if m.blockers.isEmpty { Text("Nessuna app sta tenendo sveglio il Mac.").font(.ui(11)).foregroundStyle(Theme.tertiary) }
                ForEach(m.blockers) { b in
                    HStack(spacing: 8) {
                        Text(b.process).font(.ui(11.5, .medium)).lineLimit(1)
                        Text(b.name).font(.ui(10)).foregroundStyle(Theme.tertiary).lineLimit(1)
                        Spacer()
                        Badge(text: b.type)
                    }
                }
            }
        }
    }
}
