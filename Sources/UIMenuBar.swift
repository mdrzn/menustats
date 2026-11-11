// Contenuto dell'elemento nella barra dei menu, nei vari "look".
import SwiftUI

struct ModuleValue {
    let label: String
    let value: String
    let fraction: Double?        // per colore "per carico" e grafici
    let history: [Double]
    var maxValue: Double? = 1
}

extension Monitor {
    func value(_ m: MenuModule, fahrenheit: Bool) -> ModuleValue {
        switch m {
        case .cpu: return ModuleValue(label: "CPU", value: formatPercent(cpu), fraction: cpu, history: cpuHistory.values)
        case .memory: return ModuleValue(label: "MEM", value: formatPercent(memory.fraction), fraction: memory.fraction, history: memHistory.values)
        case .gpu: return ModuleValue(label: "GPU", value: gpu.map { formatPercent($0) } ?? "–", fraction: gpu, history: gpuHistory.values)
        case .network: return ModuleValue(label: "NET", value: formatRate(down, compact: true), fraction: nil, history: downHistory.values, maxValue: nil)
        case .temperature:
            let t = sensors.socTemperature
            return ModuleValue(label: "TEMP", value: t.map { formatTemp($0, fahrenheit: fahrenheit) } ?? "–", fraction: t.map { $0 / 100 },
                               history: tempHistory.values, maxValue: 110)
        case .power:
            return ModuleValue(label: "PWR", value: sensors.systemPower.map { String(format: "%.0fW", $0) } ?? "–", fraction: nil,
                               history: powerHistory.values, maxValue: nil)
        case .disk: return ModuleValue(label: "SSD", value: formatPercent(disk.fraction), fraction: disk.fraction, history: [disk.fraction, disk.fraction])
        case .battery:
            let b = battery?.percent
            return ModuleValue(label: "BAT", value: b.map { formatPercent($0) } ?? "–", fraction: b.map { 1 - $0 }, history: [])
        case .ports: return ModuleValue(label: "PORTE", value: "\(ports.filter { !["ControlCenter", "rapportd", "sharingd"].contains($0.command) }.count)", fraction: nil, history: [])
        case .agents: return ModuleValue(label: "AI", value: "\(agents.filter(\.isBusy).count)/\(agents.count)", fraction: nil, history: [])
        }
    }
}

struct MenuBarView: View {
    @ObservedObject var m = Monitor.shared
    @ObservedObject var s = Prefs.shared
    var config: Config? = nil            // anteprima nelle impostazioni con un'altra configurazione
    var forceDark = false

    var c: Config { config ?? s.c }

    var body: some View {
        HStack(spacing: c.look == .stacked ? 9 : 7) {
            if c.modules.isEmpty {
                Image(systemName: "chart.bar.xaxis").font(.system(size: 13, weight: .medium))
            } else if c.look == .stacked {
                ForEach(Array(stackedColumns.enumerated()), id: \.offset) { _, col in column(col) }
            } else {
                ForEach(c.modules) { item($0) }
            }
        }
        .font(.system(size: 11, weight: .medium, design: c.font.design))
        .monospacedDigit()
        .padding(.horizontal, 3)
        .frame(height: 22)
        .fixedSize()
    }

    // ------------------------------------------------------------ colori
    var accent: Color { Color(hex: c.accent) }
    func color(_ v: ModuleValue) -> Color {
        switch c.valueColor {
        case .menuBar: return forceDark ? .white : .primary
        case .accent: return accent
        case .load: return v.fraction.map { Theme.load($0) } ?? (forceDark ? .white : .primary)
        }
    }
    var labelColor: Color { forceDark ? .white.opacity(0.6) : .secondary }

    // ------------------------------------------------------------ impilato: due righe per colonna
    enum Column { case pair(MenuModule, MenuModule?), network }
    var stackedColumns: [Column] {
        var out: [Column] = [], pending: MenuModule?
        for mod in c.modules {
            if mod == .network {
                if let p = pending { out.append(.pair(p, nil)); pending = nil }
                out.append(.network)
            } else if let p = pending { out.append(.pair(p, mod)); pending = nil } else { pending = mod }
        }
        if let p = pending { out.append(.pair(p, nil)) }
        return out
    }

    @ViewBuilder func column(_ col: Column) -> some View {
        switch col {
        case .network:
            VStack(alignment: .trailing, spacing: -1) {
                HStack(spacing: 3) { Text(formatRate(m.up, compact: true)); Text("↑").foregroundStyle(labelColor) }
                HStack(spacing: 3) { Text(formatRate(m.down, compact: true)); Text("↓").foregroundStyle(labelColor) }
            }
            .font(.system(size: 9, weight: .semibold, design: c.font.design)).foregroundStyle(forceDark ? .white : .primary)
        case .pair(let a, let b):
            let va = m.value(a, fahrenheit: c.fahrenheit), vb = b.map { m.value($0, fahrenheit: c.fahrenheit) }
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: -1) {
                    Text(va.label); if let vb { Text(vb.label) }
                }.foregroundStyle(labelColor)
                VStack(alignment: .trailing, spacing: -1) {
                    Text(va.value).foregroundStyle(color(va)); if let vb { Text(vb.value).foregroundStyle(color(vb)) }
                }
            }
            .font(.system(size: vb == nil ? 11 : 9, weight: .semibold, design: c.font.design))
        }
    }

    // ------------------------------------------------------------ un elemento, negli altri look
    @ViewBuilder func item(_ mod: MenuModule) -> some View {
        let v = m.value(mod, fahrenheit: c.fahrenheit)
        let valueText = mod == .network ? "↓" + v.value : v.value
        switch c.look {
        case .compact, .stacked:
            HStack(spacing: 3) {
                Text(v.label).font(.system(size: 9, weight: .semibold, design: c.font.design)).foregroundStyle(labelColor)
                Text(valueText).foregroundStyle(color(v))
            }
        case .graph:
            HStack(spacing: 4) {
                Sparkline(values: Array(v.history.suffix(24)), maxValue: v.maxValue, color: c.valueColor == .menuBar ? (forceDark ? .white : .primary) : color(v), lineWidth: 1.1)
                    .frame(width: 26, height: 13)
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(labelColor.opacity(0.4), lineWidth: 0.5))
                Text(valueText).foregroundStyle(color(v))
            }
        case .pill:
            Text(valueText).foregroundStyle(c.valueColor == .menuBar ? (forceDark ? .white : .primary) : color(v))
                .padding(.horizontal, 6).padding(.vertical, 1.5)
                .background(Capsule().fill((c.valueColor == .menuBar ? accent : color(v)).opacity(0.28)))
        case .outline:
            HStack(spacing: 3) {
                Text(v.label).font(.system(size: 8.5, weight: .bold, design: c.font.design)).foregroundStyle(labelColor)
                Text(valueText).foregroundStyle(color(v))
            }
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .overlay(Capsule().strokeBorder(labelColor.opacity(0.7), lineWidth: 1))
        case .icons:
            HStack(spacing: 3) {
                Image(systemName: mod.symbol).font(.system(size: 10.5, weight: .medium)).foregroundStyle(labelColor)
                Text(valueText).foregroundStyle(color(v))
            }
        }
    }
}
