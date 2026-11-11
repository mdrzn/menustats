// Finestra delle impostazioni: barra dei menu (look, elementi, colori), generale, informazioni.
import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var s = Prefs.shared
    @Local private var page = "bar"
    var accent: Color { s.accent }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                navItem("bar", L("Barra dei menu"), "menubar.rectangle")
                navItem("panel", L("Pannello"), "paintpalette")
                navItem("general", L("Generale"), "gearshape")
                navItem("about", L("Informazioni"), "info.circle")
                Spacer()
                Text(L("made by mdrzn")).font(.ui(10)).foregroundStyle(Theme.tertiary).padding(.leading, 8)
            }
            .padding(10).frame(width: 170)
            .background(Theme.sidebar.opacity(0.7))
            Rectangle().fill(Theme.stroke).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch page {
                    case "panel": PanelSettings()
                    case "general": GeneralSettings()
                    case "about": AboutPage()
                    default: BarSettings()
                    }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 640, height: 600)
        .background(LinearGradient(colors: [Theme.backgroundTop, Theme.background], startPoint: .top, endPoint: .bottom))
        .foregroundStyle(Theme.text)
        .environment(\.colorScheme, Theme.dark ? .dark : .light)
        .id(Theme.identity)
        .tint(accent)
    }

    func navItem(_ id: String, _ title: String, _ symbol: String) -> some View {
        Button { page = id } label: {
            Label(title, systemImage: symbol).font(.ui(12, page == id ? .semibold : .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .foregroundStyle(page == id ? accent : Theme.secondary)
                .background(RoundedRectangle(cornerRadius: 7).fill(page == id ? accent.opacity(0.15) : .clear))
        }.buttonStyle(.plain)
    }
}

// Finta barra dei menu per le anteprime
struct MenuBarPreview: View {
    let config: Config
    var height: CGFloat = 30
    var body: some View {
        HStack {
            Spacer()
            MenuBarView(config: config, forceDark: true)
            Image(systemName: "wifi").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.9))
            Text("10:32").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(LinearGradient(colors: [Color(hex: "2A2F3A"), Color(hex: "1B1E26")], startPoint: .leading, endPoint: .trailing))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct BarSettings: View {
    @ObservedObject var s = Prefs.shared
    var accent: Color { s.accent }
    let lookCols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        Text(L("Barra dei menu")).font(.ui(18, .bold))
        MenuBarPreview(config: s.c, height: 34)

        SectionLabel(L("Aspetto"))
        LazyVGrid(columns: lookCols, spacing: 8) {
            ForEach(MenuLook.allCases) { look in
                Button { s.c.look = look } label: {
                    VStack(spacing: 6) {
                        MenuBarView(config: { var p = s.c; p.look = look; p.modules = Array(s.c.modules.prefix(2)); return p }(), forceDark: true)
                            .scaleEffect(0.9).frame(maxWidth: .infinity).frame(height: 24).clipped()
                        Text(look.title).font(.ui(11, s.c.look == look ? .semibold : .medium))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 10).fill(s.c.look == look ? accent.opacity(0.12) : Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(s.c.look == look ? accent.opacity(0.7) : Theme.stroke))
                    .clipped()
                }.buttonStyle(.plain)
            }
        }

        SectionLabel(L("Colore dei valori"))
        Segmented(options: ValueColor.allCases.map { ($0, $0.title) }, selection: $s.c.valueColor, accent: accent)
        SectionLabel(L("Carattere"))
        Segmented(options: FontStyle.allCases.map { ($0, $0.title) }, selection: $s.c.font, accent: accent)

        SectionLabel(L("Colore d'accento"))
        HStack(spacing: 10) {
            ForEach(accentPresets, id: \.hex) { p in
                Button { s.c.accent = p.hex } label: {
                    Circle().fill(Color(hex: p.hex)).frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(Theme.text, lineWidth: s.c.accent == p.hex ? 2 : 0))
                        .overlay(Circle().strokeBorder(.black.opacity(0.3), lineWidth: 0.5))
                }.buttonStyle(.plain).help(p.name)
            }
            ColorPicker("", selection: Binding(get: { Color(hex: s.c.accent) }, set: { c in
                if let n = NSColor(c).usingColorSpace(.sRGB) {
                    s.c.accent = String(format: L("%02X%02X%02X"), Int(n.redComponent * 255), Int(n.greenComponent * 255), Int(n.blueComponent * 255))
                }
            }), supportsOpacity: false).labelsHidden()
            Spacer()
        }

        SectionLabel(L("Elementi mostrati"))
        Card {
            VStack(spacing: 2) {
                ForEach(orderedModules, id: \.self) { mod in moduleRow(mod) }
            }
        }
        Text(L("Trascina l'ordine con le frecce. Temperatura e consumo usano sensori sperimentali.")).font(.ui(10.5)).foregroundStyle(Theme.tertiary)
    }

    // attivi nell'ordine scelto, poi gli altri
    var orderedModules: [MenuModule] { s.c.modules + MenuModule.allCases.filter { !s.c.modules.contains($0) } }

    func moduleRow(_ mod: MenuModule) -> some View {
        let on = s.c.modules.contains(mod)
        let idx = s.c.modules.firstIndex(of: mod)
        return HStack(spacing: 10) {
            Image(systemName: mod.symbol).font(.ui(12)).foregroundStyle(on ? accent : Theme.tertiary).frame(width: 18)
            Text(mod.title).font(.ui(12, .medium)).foregroundStyle(on ? Theme.text : Theme.secondary)
            Spacer()
            if let i = idx {
                IconButton(symbol: "chevron.up", help: L("Sposta a sinistra")) { if i > 0 { s.c.modules.swapAt(i, i - 1) } }.opacity(i > 0 ? 1 : 0.3)
                IconButton(symbol: "chevron.down", help: L("Sposta a destra")) { if i < s.c.modules.count - 1 { s.c.modules.swapAt(i, i + 1) } }
                    .opacity(i < s.c.modules.count - 1 ? 1 : 0.3)
            }
            Toggle("", isOn: Binding(get: { on }, set: { v in
                if v { s.c.modules.append(mod) } else { s.c.modules.removeAll { $0 == mod } }
                Monitor.shared.tick()
            })).toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
        .padding(.vertical, 3).padding(.horizontal, 4)
    }
}

struct PanelSettings: View {
    @ObservedObject var s = Prefs.shared
    var accent: Color { s.accent }
    var body: some View {
        Text(L("Pannello")).font(.ui(18, .bold))
        SectionLabel(L("Tema"))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
            ForEach(ThemeChoice.allCases) { t in
                Button { s.c.theme = t } label: {
                    VStack(spacing: 6) {
                        ThemeSwatch(choice: t, accent: accent).frame(height: 44)
                        Text(t.title).font(.ui(10.5, s.c.theme == t ? .semibold : .medium)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(s.c.theme == t ? accent.opacity(0.12) : Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(s.c.theme == t ? accent.opacity(0.7) : Theme.stroke))
                }.buttonStyle(.plain)
            }
        }
        Text(L("Automatico segue l'aspetto chiaro/scuro di macOS.")).font(.ui(10.5)).foregroundStyle(Theme.tertiary)
        SectionLabel(L("Dimensione del testo"))
        Segmented(options: [(0.92, L("Compatta")), (1.0, L("Normale")), (1.1, L("Grande"))], selection: $s.c.textScale, accent: accent)
        SectionLabel(L("Sfondo"))
        Segmented(options: [(1.0, L("Opaco")), (0.85, L("Leggero")), (0.7, L("Vetro"))], selection: $s.c.panelOpacity, accent: accent)
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Colori per area")).font(.ui(12))
                    Text(L("CPU, memoria, rete e temperatura con colori diversi nei grafici.")).font(.ui(10.5)).foregroundStyle(Theme.tertiary)
                }
                Spacer()
                Toggle("", isOn: $s.c.areaColors).toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
        }
        SectionLabel(L("Lingua"))
        Segmented(options: AppLanguage.allCases.map { ($0, $0.title) }, selection: $s.c.language, accent: accent)
    }
}

// Anteprima in miniatura di un tema
struct ThemeSwatch: View {
    let choice: ThemeChoice
    let accent: Color
    var body: some View {
        if choice == .auto {
            HStack(spacing: 0) { half(.graphite); half(.paper) }.clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            half(choice).clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
    func half(_ c: ThemeChoice) -> some View {
        let p = Palette.of(c)
        return ZStack(alignment: .topLeading) {
            p.background
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 2).fill(p.ink.opacity(p.textAlpha)).frame(width: 22, height: 4)
                RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 30, height: 4)
                RoundedRectangle(cornerRadius: 2).fill(p.ink.opacity(p.tertiaryAlpha)).frame(width: 16, height: 4)
            }.padding(7)
        }
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(p.ink.opacity(0.15)))
    }
}

struct GeneralSettings: View {
    @ObservedObject var s = Prefs.shared
    var accent: Color { s.accent }
    var body: some View {
        Text(L("Generale")).font(.ui(18, .bold))
        Card(title: L("Aggiornamento")) {
            HStack {
                Text(L("Frequenza nella barra dei menu")).font(.ui(12))
                Spacer()
                Segmented(options: [(1.0, L("1 s")), (2.0, L("2 s")), (5.0, L("5 s"))], selection: Binding(get: { s.c.interval }, set: {
                    s.c.interval = $0; Monitor.shared.reschedule()
                }), accent: accent).frame(width: 160)
            }
            Text(L("Con il pannello aperto i dati si aggiornano ogni secondo.")).font(.ui(10.5)).foregroundStyle(Theme.tertiary)
        }
        Card(title: L("Preferenze")) {
            row(L("Gradi Fahrenheit")) { Toggle("", isOn: $s.c.fahrenheit).toggleStyle(.switch).labelsHidden().controlSize(.small) }
            row(L("Avvia al login")) { Toggle("", isOn: $s.launchAtLogin).toggleStyle(.switch).labelsHidden().controlSize(.small) }
            row(L("Apri il pannello con ⌥⌘M")) { Toggle("", isOn: Binding(get: { s.c.hotkeyEnabled }, set: { s.c.hotkeyEnabled = $0; AppDelegate.shared?.registerHotKey() }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small) }
        }
        Card(title: L("Avvisi")) {
            HStack {
                Text(L("App che usano molta CPU")).font(.ui(12))
                Spacer()
                Slider(value: $s.c.cpuAlert, in: 50...400, step: 10).frame(width: 160)
                Text("\(Int(s.c.cpuAlert))%").font(.number(11)).frame(width: 44, alignment: .trailing)
            }
            Text(L("Soglia per almeno 10 secondi. 100% = un core pieno.")).font(.ui(10.5)).foregroundStyle(Theme.tertiary)
        }
        Card(title: L("Sperimentale")) {
            row(L("Volume per app")) { Toggle("", isOn: Binding(get: { s.c.perAppVolume }, set: { s.c.perAppVolume = $0; Monitor.shared.applyMixer() }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small) }
            Text(L("Richiede il permesso di registrazione audio di sistema: l'audio dell'app viene intercettato solo per cambiarne il volume."))
                .font(.ui(10.5)).foregroundStyle(Theme.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }
    func row<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack { Text(t).font(.ui(12)); Spacer(); c() }
    }
}

let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

struct AboutPage: View {
    @ObservedObject var s = Prefs.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                AppLogo(size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("MenuStats")).font(.ui(22, .bold))
                    Text(L("Versione %@", appVersion)).font(.ui(12)).foregroundStyle(Theme.secondary)
                }
            }
            Text(L("Un monitor di sistema open source per la barra dei menu, pensato per chi sviluppa: risorse, app, porte, agenti AI, audio e \"tieni sveglio\" in un solo pannello."))
                .font(.ui(12.5)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            Card {
                HStack {
                    Text(L("Made by ")).font(.ui(13)) + Text("mdrzn").font(.ui(13, .bold))
                    Spacer()
                    Link(L("GitHub"), destination: URL(string: "https://github.com/mdrzn/menustats")!).font(.ui(12, .semibold))
                }
                Text(L("Licenza MIT. Nessun dato lascia il tuo Mac.")).font(.ui(11)).foregroundStyle(Theme.tertiary)
            }
        }
    }
}

// Logo disegnato in SwiftUI: tre barre su un riquadro con l'accento
struct AppLogo: View {
    var size: CGFloat
    var accent = Color(hex: "4FD1A5")
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "1F242E"), Color(hex: "0E1014")], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous).strokeBorder(Theme.ink.opacity(0.12), lineWidth: size * 0.015)
            HStack(alignment: .bottom, spacing: size * 0.08) {
                bar(0.34); bar(0.62); bar(0.46)
            }
            .offset(y: size * 0.04)
            Path { p in
                p.move(to: CGPoint(x: size * 0.2, y: size * 0.56))
                p.addCurve(to: CGPoint(x: size * 0.8, y: size * 0.3), control1: CGPoint(x: size * 0.42, y: size * 0.62), control2: CGPoint(x: size * 0.55, y: size * 0.22))
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round))
        }
        .frame(width: size, height: size)
    }
    func bar(_ h: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.04).fill(accent.opacity(0.35 + h)).frame(width: size * 0.13, height: size * h)
    }
}
