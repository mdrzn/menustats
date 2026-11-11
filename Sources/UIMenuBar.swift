// Contenuto della barra dei menu: uno o piu' elementi, nei vari "look".
import SwiftUI

struct ModuleValue {
    let label: String
    let value: String
    let fraction: Double?        // 0...1: colore "per carico", anelli, barre, tachimetri
    let history: [Double]
    var maxValue: Double? = 1
}

extension Monitor {
    func value(_ m: MenuModule, fahrenheit: Bool) -> ModuleValue {
        switch m {
        case .cpu: return ModuleValue(label: "CPU", value: formatPercent(cpu), fraction: cpu, history: cpuHistory.values)
        case .memory: return ModuleValue(label: "MEM", value: formatPercent(memory.fraction), fraction: memory.fraction, history: memHistory.values)
        case .gpu: return ModuleValue(label: "GPU", value: gpu.map { formatPercent($0) } ?? "–", fraction: gpu, history: gpuHistory.values)
        case .network:
            let peak = max(downHistory.peak, 1)
            return ModuleValue(label: "NET", value: formatRate(down, compact: true), fraction: min(down / peak, 1), history: downHistory.values, maxValue: nil)
        case .temperature:
            let t = sensors.socTemperature
            return ModuleValue(label: "TEMP", value: t.map { formatTemp($0, fahrenheit: fahrenheit) } ?? "–", fraction: t.map { $0 / 100 },
                               history: tempHistory.values, maxValue: 110)
        case .power:
            let p = sensors.systemPower
            return ModuleValue(label: "PWR", value: p.map { String(format: "%.0fW", $0) } ?? "–", fraction: p.map { min($0 / max(powerHistory.peak, 1), 1) },
                               history: powerHistory.values, maxValue: nil)
        case .disk: return ModuleValue(label: "SSD", value: formatPercent(disk.fraction), fraction: disk.fraction, history: [disk.fraction, disk.fraction])
        case .diskFree:
            return ModuleValue(label: L("LIBERO"), value: String(format: "%.0fG", Double(max(disk.free, 0)) / 1_073_741_824), fraction: disk.fraction, history: [])
        case .battery:
            let b = battery?.percent
            return ModuleValue(label: "BAT", value: b.map { formatPercent($0) } ?? "–", fraction: b.map { 1 - $0 }, history: [])
        case .ports: return ModuleValue(label: L("PORTE"), value: "\(devPorts.count)", fraction: nil, history: [])
        case .agents: return ModuleValue(label: "AI", value: "\(agents.filter(\.isBusy).count)/\(agents.count)", fraction: nil, history: [])
        case .clock: return ModuleValue(label: "", value: clockText, fraction: nil, history: [])
        case .publicIP: return ModuleValue(label: "IP", value: publicIP ?? "…", fraction: nil, history: [])
        case .ping:
            return ModuleValue(label: "PING", value: pingMs.map { "\(Int($0.rounded()))ms" } ?? "–", fraction: pingMs.map { min($0 / 200, 1) },
                               history: pingHistory.values, maxValue: nil)
        case .uptime: return ModuleValue(label: "UP", value: formatDuration(uptime), fraction: nil, history: [])
        case .awake: return ModuleValue(label: "", value: awake.isActive ? (awake.remaining.map { formatDuration($0) } ?? "∞") : "", fraction: nil, history: [])
        case .mic: return ModuleValue(label: "", value: micInUse ? "●" : "", fraction: nil, history: [])
        }
    }

    // Porte "di sviluppo" (esclusi i servizi di macOS)
    var devPorts: [ListeningPort] { ports.filter { !macServices.contains($0.command) } }

    var clockText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: Lang.english ? "en_US" : "it_IT")
        f.setLocalizedDateFormatFromTemplate("EEE d HH:mm")
        return f.string(from: Date())
    }
}

let macServices: Set<String> = ["ControlCenter", "rapportd", "sharingd", "launchd", "remoted", "AirPlayXPCHelper", "WiFiAgent", "identityservicesd"]

extension MenuModule {
    // Testo piu' largo che il valore puo' assumere: riserva sempre quello spazio,
    // cosi' l'elemento nella barra (e il popover agganciato) non si sposta.
    var widthTemplate: String {
        switch self {
        case .cpu, .memory, .gpu, .disk, .battery: "100%"
        case .network: "↓999K"
        case .temperature: "100°"
        case .power: "100W"
        case .diskFree: "9999G"
        case .ports: "99"
        case .agents: "9/9"
        case .clock: "Mer 30 23:59"
        case .publicIP: "255.255.255.255"
        case .ping: "999ms"
        case .uptime: "99g 23h"
        case .awake: "23h 59m"
        case .mic: "●"
        }
    }
    // Indicatori: compaiono solo quando c'e' qualcosa da segnalare
    var isIndicator: Bool { self == .awake || self == .mic }
}

// Testo allineato a destra dentro uno spazio largo quanto `template`
struct FixedSlot: View {
    let text: String
    let template: String
    var body: some View {
        ZStack(alignment: .trailing) {
            Text(template).hidden()
            Text(text)
        }
    }
}

struct MenuBarView: View {
    @ObservedObject var m = Monitor.shared
    @ObservedObject var s = Prefs.shared
    var config: Config? = nil            // anteprima nelle impostazioni con un'altra configurazione
    var only: MenuModule? = nil          // elemento singolo (modalita' "elementi separati")
    var forceDark = false

    var c: Config { config ?? s.c }
    var modules: [MenuModule] {
        (only.map { [$0] } ?? c.modules).filter { !$0.isIndicator || !m.value($0, fahrenheit: c.fahrenheit).value.isEmpty }
    }

    var body: some View {
        HStack(spacing: c.look == .stacked ? 9 : 7) {
            if c.minimalMode && only == nil {
                minimal
            } else if modules.isEmpty && only != nil {
                Color.clear.frame(width: 0)            // indicatore spento: elemento invisibile
            } else if modules.isEmpty {
                Image(systemName: "chart.bar.xaxis").font(.system(size: 13, weight: .medium))
            } else if c.look == .stacked {
                ForEach(Array(stackedColumns.enumerated()), id: \.offset) { _, col in column(col) }
            } else {
                ForEach(modules) { item($0) }
            }
        }
        .font(.system(size: 11, weight: .medium, design: c.font.design))
        .monospacedDigit()
        .padding(.horizontal, 3)
        .frame(height: 22)
        .fixedSize()
    }

    // ------------------------------------------------------------ modalita' minima: un'icona che cambia colore
    var minimal: some View {
        let sev = m.alerts.map(\.severity).max() ?? 0
        return Image(systemName: sev > 0 ? "chart.bar.xaxis.ascending" : "chart.bar.xaxis")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(sev > 1 ? Theme.danger : sev == 1 ? Theme.warning : primary)
    }

    // ------------------------------------------------------------ colori ed etichette
    var accent: Color { Color(hex: c.accent) }
    var primary: Color { forceDark ? .white : .primary }
    func color(_ v: ModuleValue) -> Color {
        switch c.valueColor {
        case .menuBar: return primary
        case .accent: return accent
        case .load: return v.fraction.map { Theme.load($0) } ?? primary
        }
    }
    var labelColor: Color { forceDark ? .white.opacity(0.6) : .secondary }
    func label(_ mod: MenuModule, _ v: ModuleValue) -> String? {
        if c.hideLabels { return nil }
        if let custom = c.labels[mod.rawValue], !custom.isEmpty { return custom }
        return v.label.isEmpty ? nil : v.label
    }

    // ------------------------------------------------------------ impilato: due righe per colonna
    enum Column { case pair(MenuModule, MenuModule?), network, single(MenuModule) }
    var stackedColumns: [Column] {
        var out: [Column] = [], pending: MenuModule?
        for mod in modules {
            if mod == .network || mod == .clock || mod == .publicIP || mod.isIndicator {
                if let p = pending { out.append(.pair(p, nil)); pending = nil }
                out.append(mod == .network ? .network : .single(mod))
            } else if let p = pending { out.append(.pair(p, mod)); pending = nil } else { pending = mod }
        }
        if let p = pending { out.append(.pair(p, nil)) }
        return out
    }

    @ViewBuilder func column(_ col: Column) -> some View {
        switch col {
        case .network:
            VStack(alignment: .trailing, spacing: -1) {
                HStack(spacing: 3) { FixedSlot(text: formatRate(m.up, compact: true), template: "999K"); Text("↑").foregroundStyle(labelColor) }
                HStack(spacing: 3) { FixedSlot(text: formatRate(m.down, compact: true), template: "999K"); Text("↓").foregroundStyle(labelColor) }
            }
            .font(.system(size: 9, weight: .semibold, design: c.font.design)).foregroundStyle(primary)
        case .single(let mod):
            item(mod, forceLook: .compact)
        case .pair(let a, let b):
            let va = m.value(a, fahrenheit: c.fahrenheit), vb = b.map { m.value($0, fahrenheit: c.fahrenheit) }
            HStack(spacing: 4) {
                if !c.hideLabels {
                    VStack(alignment: .leading, spacing: -1) {
                        Text(label(a, va) ?? ""); if let vb, let b { Text(label(b, vb) ?? "") }
                    }.foregroundStyle(labelColor)
                }
                VStack(alignment: .trailing, spacing: -1) {
                    FixedSlot(text: va.value, template: a.widthTemplate).foregroundStyle(color(va))
                    if let vb, let b { FixedSlot(text: vb.value, template: b.widthTemplate).foregroundStyle(color(vb)) }
                }
            }
            .font(.system(size: vb == nil ? 11 : 9, weight: .semibold, design: c.font.design))
        }
    }

    // ------------------------------------------------------------ un elemento
    @ViewBuilder func item(_ mod: MenuModule, forceLook: MenuLook? = nil) -> some View {
        let v = m.value(mod, fahrenheit: c.fahrenheit)
        let look = forceLook ?? c.look
        if mod == .mic {
            Image(systemName: "mic.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.warning)
        } else if mod == .awake {
            HStack(spacing: 3) {
                Image(systemName: "cup.and.saucer.fill").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(accent)
                if look != .icons && look != .ring && look != .gauge { Text(v.value).foregroundStyle(primary) }
            }
        } else {
            let valueText = mod == .network ? "↓" + v.value : v.value
            let slot = FixedSlot(text: valueText, template: mod.widthTemplate)
            switch look {
            case .compact, .stacked:
                HStack(spacing: 3) {
                    if let l = label(mod, v) { Text(l).font(.system(size: 9, weight: .semibold, design: c.font.design)).foregroundStyle(labelColor) }
                    slot.foregroundStyle(color(v))
                }
            case .graph:
                HStack(spacing: 4) {
                    if v.history.count > 1 {
                        Sparkline(values: Array(v.history.suffix(24)), maxValue: v.maxValue, color: c.valueColor == .menuBar ? primary : color(v), lineWidth: 1.1)
                            .frame(width: 26, height: 13)
                            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(labelColor.opacity(0.4), lineWidth: 0.5))
                    } else if let l = label(mod, v) {
                        Text(l).font(.system(size: 9, weight: .semibold)).foregroundStyle(labelColor)
                    }
                    slot.foregroundStyle(color(v))
                }
            case .columns:
                HStack(spacing: 4) {
                    if v.history.count > 1 {
                        MiniColumns(values: Array(v.history.suffix(12)), maxValue: v.maxValue, color: c.valueColor == .menuBar ? primary : color(v))
                            .frame(width: 22, height: 13)
                    }
                    slot.foregroundStyle(color(v))
                }
            case .ring:
                HStack(spacing: 4) {
                    if let f = v.fraction {
                        Ring(value: f, color: c.valueColor == .menuBar ? primary : color(v), lineWidth: 2.2).frame(width: 12, height: 12)
                    } else if let l = label(mod, v) {
                        Text(l).font(.system(size: 9, weight: .semibold)).foregroundStyle(labelColor)
                    }
                    slot.foregroundStyle(color(v))
                }
            case .bar:
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 3) {
                        if let l = label(mod, v) { Text(l).font(.system(size: 8, weight: .bold)).foregroundStyle(labelColor) }
                        slot.font(.system(size: 9.5, weight: .semibold, design: c.font.design)).foregroundStyle(color(v))
                    }
                    if let f = v.fraction {
                        Meter(value: f, color: c.valueColor == .menuBar ? primary.opacity(0.85) : color(v), height: 2.5)
                    }
                }.fixedSize(horizontal: true, vertical: false)
            case .gauge:
                HStack(spacing: 4) {
                    if let f = v.fraction {
                        MiniGauge(value: f, color: c.valueColor == .menuBar ? primary : color(v)).frame(width: 18, height: 11)
                    }
                    slot.foregroundStyle(color(v))
                }
            case .pill:
                slot.foregroundStyle(c.valueColor == .menuBar ? primary : color(v))
                    .padding(.horizontal, 6).padding(.vertical, 1.5)
                    .background(Capsule().fill((c.valueColor == .menuBar ? accent : color(v)).opacity(0.28)))
            case .outline:
                HStack(spacing: 3) {
                    if let l = label(mod, v) { Text(l).font(.system(size: 8.5, weight: .bold, design: c.font.design)).foregroundStyle(labelColor) }
                    slot.foregroundStyle(color(v))
                }
                .padding(.horizontal, 5).padding(.vertical, 1.5)
                .overlay(Capsule().strokeBorder(labelColor.opacity(0.7), lineWidth: 1))
            case .icons:
                HStack(spacing: 3) {
                    Image(systemName: mod.symbol).font(.system(size: 10.5, weight: .medium)).foregroundStyle(labelColor)
                    slot.foregroundStyle(color(v))
                }
            }
        }
    }
}

// Istogramma a colonne (ultimi campioni)
struct MiniColumns: View {
    let values: [Double]
    var maxValue: Double?
    var color: Color
    var body: some View {
        GeometryReader { g in
            let top = max(maxValue ?? (values.max() ?? 1), 0.0001)
            let w = (g.size.width - CGFloat(values.count - 1)) / CGFloat(max(values.count, 1))
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                    RoundedRectangle(cornerRadius: 0.8).fill(color.opacity(0.85))
                        .frame(width: max(w, 1), height: max(1, g.size.height * CGFloat(min(v / top, 1))))
                }
            }
        }
    }
}

// Tachimetro a semicerchio
struct MiniGauge: View {
    let value: Double
    var color: Color
    var body: some View {
        GeometryReader { g in
            let r = min(g.size.width / 2, g.size.height) - 1.5
            let c = CGPoint(x: g.size.width / 2, y: g.size.height - 0.5)
            ZStack {
                Path { p in p.addArc(center: c, radius: r, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false) }
                    .stroke(color.opacity(0.25), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                Path { p in p.addArc(center: c, radius: r, startAngle: .degrees(180), endAngle: .degrees(180 + 180 * min(max(value, 0), 1)), clockwise: false) }
                    .stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            }
        }
    }
}
