// Sistema di design di MenuStats: colori, tipografia e componenti riutilizzabili.
// Tutto in SwiftUI puro (niente NSVisualEffectView), cosi' si puo' anche renderizzare fuori
// schermo per gli screenshot del README.
import SwiftUI
import AppKit

// ================================================================ token
enum Theme {
    static let background = Color(hex: "101216")
    static let backgroundTop = Color(hex: "171A21")
    static let sidebar = Color(hex: "0C0E11")
    static let card = Color.white.opacity(0.045)
    static let cardHover = Color.white.opacity(0.075)
    static let stroke = Color.white.opacity(0.075)
    static let text = Color.white.opacity(0.93)
    static let secondary = Color.white.opacity(0.56)
    static let tertiary = Color.white.opacity(0.34)
    static let warning = Color(hex: "F5B942")
    static let danger = Color(hex: "FB7185")
    static let radius: CGFloat = 12

    // verde -> ambra -> rosso in base al carico (0...1)
    static func load(_ f: Double) -> Color {
        f < 0.6 ? Color(hex: "4ADE80") : f < 0.85 ? warning : danger
    }
}

extension Font {
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    static func number(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .monospaced) }
}

// ================================================================ contenitori
struct Card<Content: View>: View {
    var title: String? = nil
    var trailing: String? = nil
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if title != nil || trailing != nil {
                HStack {
                    if let title { SectionLabel(title, color: tint) }
                    Spacer()
                    if let trailing { Text(trailing).font(.ui(10.5)).foregroundStyle(Theme.tertiary) }
                }
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(tint.map { $0.opacity(0.07) } ?? Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(tint.map { $0.opacity(0.35) } ?? Theme.stroke, lineWidth: 1))
    }
}

struct SectionLabel: View {
    let text: String
    var color: Color?
    init(_ text: String, color: Color? = nil) { self.text = text; self.color = color }
    var body: some View {
        Text(text.uppercased()).font(.ui(9.5, .semibold)).tracking(0.9).foregroundStyle(color ?? Theme.tertiary)
    }
}

// ================================================================ grafici
struct Sparkline: View {
    let values: [Double]
    var maxValue: Double? = nil        // nil = scala automatica sul massimo
    var color: Color
    var fill = true
    var lineWidth: CGFloat = 1.4

    var body: some View {
        GeometryReader { g in
            let pts = points(in: g.size)
            if pts.count > 1 {
                ZStack {
                    if fill {
                        Path { p in
                            p.move(to: CGPoint(x: pts[0].x, y: g.size.height))
                            pts.forEach { p.addLine(to: $0) }
                            p.addLine(to: CGPoint(x: pts.last!.x, y: g.size.height))
                            p.closeSubpath()
                        }
                        .fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    }
                    Path { p in p.addLines(pts) }
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    func points(in s: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let top = max(maxValue ?? (values.max() ?? 1), 0.0001)
        let step = s.width / CGFloat(values.count - 1)
        return values.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * step, y: s.height - CGFloat(min(v / top, 1)) * (s.height - 1.5) - 0.75)
        }
    }
}

// Barra orizzontale sottile
struct Meter: View {
    let value: Double            // 0...1
    var color: Color
    var height: CGFloat = 5
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule().fill(color).frame(width: max(height, g.size.width * CGFloat(min(max(value, 0), 1))))
            }
        }.frame(height: height)
    }
}

// Barra a segmenti (es. memoria: app / wired / compressa)
struct StackedMeter: View {
    let parts: [(Double, Color)]   // frazioni del totale
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { g in
            HStack(spacing: 1.5) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                    Rectangle().fill(p.1).frame(width: max(0, g.size.width * CGFloat(p.0) - 1.5))
                }
                Spacer(minLength: 0)
            }
            .background(Color.white.opacity(0.07))
            .clipShape(Capsule())
        }.frame(height: height)
    }
}

// Anello di avanzamento
struct Ring: View {
    let value: Double
    var color: Color
    var lineWidth: CGFloat = 4
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            Circle().trim(from: 0, to: CGFloat(min(max(value, 0), 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// ================================================================ elementi
struct MetricTile: View {
    let label: String
    let detail: String
    let value: String
    var unit: String? = nil
    let history: [Double]
    var maxValue: Double? = 1
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.ui(10, .semibold)).foregroundStyle(Theme.secondary)
                Spacer(minLength: 4)
                Text(detail).font(.ui(9.5)).foregroundStyle(Theme.tertiary).lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.number(19)).foregroundStyle(Theme.text)
                if let unit { Text(unit).font(.ui(10, .medium)).foregroundStyle(Theme.secondary) }
            }
            Sparkline(values: history, maxValue: maxValue, color: color).frame(height: 18)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke))
    }
}

struct Badge: View {
    let text: String
    var color: Color = Theme.secondary
    var filled = false
    var body: some View {
        Text(text).font(.ui(9.5, .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(filled ? Color.black.opacity(0.8) : color)
            .background(Capsule().fill(filled ? color : color.opacity(0.13)))
    }
}

struct Dot: View {
    var color: Color
    var size: CGFloat = 6
    var body: some View { Circle().fill(color).frame(width: size, height: size).shadow(color: color.opacity(0.6), radius: 3) }
}

// Pulsante piccolo "pillola"
struct PillButton: View {
    let title: String
    var color: Color = Theme.text
    var prominent = false
    let action: () -> Void
    @Local private var hover = false
    var body: some View {
        Button(action: action) {
            Text(title).font(.ui(10.5, .semibold))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .foregroundStyle(prominent ? Color.black.opacity(0.85) : color)
                .background(Capsule().fill(prominent ? color : Color.white.opacity(hover ? 0.14 : 0.08)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct IconButton: View {
    let symbol: String
    var help: String = ""
    let action: () -> Void
    @Local private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.ui(11, .medium))
                .frame(width: 22, height: 22)
                .foregroundStyle(hover ? Theme.text : Theme.secondary)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(hover ? 0.1 : 0)))
        }
        .buttonStyle(.plain).help(help).onHover { hover = $0 }
    }
}

// Riga con hover leggero
struct HoverRow<Content: View>: View {
    @ViewBuilder var content: Content
    @Local private var hover = false
    var body: some View {
        content
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7).fill(hover ? Theme.cardHover : .clear))
            .contentShape(Rectangle())
            .onHover { hover = $0 }
    }
}

// Icona di un'app (con cache)
enum AppIcons {
    private static var cache: [String: NSImage] = [:]
    static func icon(_ path: String?) -> NSImage? {
        guard let path else { return nil }
        if let i = cache[path] { return i }
        let i = NSWorkspace.shared.icon(forFile: path)
        cache[path] = i
        return i
    }
}

struct AppIconView: View {
    let path: String?
    var size: CGFloat = 18
    var fallback = "terminal"
    var body: some View {
        if let img = AppIcons.icon(path) {
            Image(nsImage: img).resizable().frame(width: size, height: size)
        } else {
            Image(systemName: fallback).font(.ui(size * 0.55, .medium)).foregroundStyle(Theme.secondary)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.25).fill(Color.white.opacity(0.07)))
        }
    }
}

// Selettore a segmenti nel nostro stile
struct Segmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var accent: Color
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                let on = o.0 == selection
                Button { selection = o.0 } label: {
                    Text(o.1).font(.ui(10.5, on ? .semibold : .medium)).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                        .foregroundStyle(on ? Theme.text : Theme.secondary)
                        .background(RoundedRectangle(cornerRadius: 6).fill(on ? accent.opacity(0.22) : .clear))
                }.buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
    }
}

// Slider sottile con colore d'accento (per volumi)
struct ThinSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var color: Color
    var marker: Double? = nil      // tacca (es. 100%)
    @Local private var dragging = false
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let f = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.09)).frame(height: 4)
                Capsule().fill(color).frame(width: max(4, w * f), height: 4)
                if let m = marker {
                    let mf = CGFloat((m - range.lowerBound) / (range.upperBound - range.lowerBound))
                    Rectangle().fill(Color.white.opacity(0.35)).frame(width: 1.5, height: 9).offset(x: w * mf - 0.75)
                }
                Circle().fill(Color.white).frame(width: dragging ? 13 : 11, height: dragging ? 13 : 11)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(x: max(0, min(w - 11, w * f - 5.5)))
            }
            .frame(height: 16)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { d in
                    dragging = true
                    var v = range.lowerBound + Double(min(max(d.location.x / w, 0), 1)) * (range.upperBound - range.lowerBound)
                    if let m = marker, abs(v - m) < (range.upperBound - range.lowerBound) * 0.025 { v = m }   // aggancio al 100%
                    value = v
                }
                .onEnded { _ in dragging = false })
        }.frame(height: 16)
    }
}

// Riga etichetta/valore
struct KV: View {
    let k: String
    let v: String
    var vColor: Color = Theme.text
    var body: some View {
        HStack {
            Text(k).font(.ui(11)).foregroundStyle(Theme.secondary)
            Spacer()
            Text(v).font(.number(11, .medium)).foregroundStyle(vColor)
        }
    }
}

// ================================================================ stato locale delle viste
// Equivalente di @State: con i soli Command Line Tools il plugin delle macro SwiftUI
// (necessario a @State nei nuovi SDK) non c'e', quindi usiamo @StateObject su una scatola.
final class LocalBox<T>: ObservableObject {
    @Published var value: T
    init(_ v: T) { value = v }
}

@propertyWrapper struct Local<T>: DynamicProperty {
    @StateObject private var box: LocalBox<T>
    init(wrappedValue: T) { _box = StateObject(wrappedValue: LocalBox(wrappedValue)) }
    var wrappedValue: T {
        get { box.value }
        nonmutating set { box.value = newValue }
    }
    var projectedValue: Binding<T> { Binding(get: { box.value }, set: { box.value = $0 }) }
}
