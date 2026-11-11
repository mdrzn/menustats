// Avvio: elemento nella barra dei menu, popover, finestra impostazioni, scorciatoia globale.
import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox

// Vista SwiftUI dentro il pulsante della barra: lascia passare i clic al pulsante
final class PassthroughHostingView<V: View>: NSHostingView<V> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    static weak var shared: AppDelegate?
    // Elementi nella barra: "all" (uno solo con tutti i moduli) oppure uno per modulo
    var items: [(key: String, item: NSStatusItem, host: PassthroughHostingView<MenuBarView>)] = []
    var anchor: NSStatusItem?          // elemento a cui e' agganciato il popover aperto
    let popover = NSPopover()
    var settingsWindow: NSWindow?
    var hotKeyRef: EventHotKeyRef?
    var tabHotKeys: [EventHotKeyRef] = []
    var bag = Set<AnyCancellable>()
    let monitor = Monitor.shared

    func applicationDidFinishLaunching(_ n: Notification) {
        AppDelegate.shared = self
        rebuildItems()
        // ad ogni aggiornamento la larghezza degli elementi segue il contenuto
        monitor.objectWillChange.merge(with: Prefs.shared.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.resizeItems() } }
            .store(in: &bag)

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.appearance = NSAppearance(named: Theme.dark ? .darkAqua : .aqua)
        // Dimensione fissa da subito: senza, al primo clic SwiftUI calcola la misura dopo
        // l'apertura e il popover compare in un punto provvisorio prima di spostarsi.
        let size = PopoverView.size
        let controller = NSHostingController(rootView: PopoverView())
        controller.sizingOptions = []
        controller.view.frame = NSRect(origin: .zero, size: size)
        controller.view.layoutSubtreeIfNeeded()
        popover.contentSize = size
        popover.contentViewController = controller

        installHotKeyHandler()
        registerHotKey()
        Notifier.shared.setup()
        Updater.shared.start()
        // MENUSTATS_OPEN=1: apre il pannello all'avvio (per misurare i consumi a pannello aperto)
        if ProcessInfo.processInfo.environment["MENUSTATS_OPEN"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.togglePopoverOpen() }
        }
        Prefs.shared.objectWillChange.receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.applyTheme(); self?.rebuildItems() } }
            .store(in: &bag)
    }

    func applyTheme() {
        let appearance = NSAppearance(named: Theme.dark ? .darkAqua : .aqua)
        popover.appearance = appearance
        settingsWindow?.appearance = appearance
        if popover.contentSize != PopoverView.size { popover.contentSize = PopoverView.size }
    }

    // Crea o ricrea gli elementi nella barra quando cambia la modalita' o l'elenco dei moduli
    func rebuildItems() {
        let c = Prefs.shared.c
        let separate = c.separateItems && !c.minimalMode && !c.modules.isEmpty
        let keys = separate ? c.modules.map(\.rawValue) : ["all"]
        guard keys != items.map(\.key) else { return }
        if popover.isShown { popover.performClose(nil) }
        items.forEach { NSStatusBar.system.removeStatusItem($0.item) }
        items.removeAll()
        // macOS mette ogni nuovo elemento a sinistra dei precedenti: si creano dall'ultimo
        for key in keys.reversed() {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            let host = PassthroughHostingView(rootView: MenuBarView(only: MenuModule(rawValue: key)))
            host.translatesAutoresizingMaskIntoConstraints = true
            if let button = item.button {
                button.addSubview(host)
                button.target = self
                button.action = #selector(itemClicked(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
            items.insert((key, item, host), at: 0)
        }
        resizeItems()
    }

    func resizeItems() {
        for (_, item, host) in items {
            let size = host.fittingSize
            let w = ceil(size.width)
            if abs(item.length - w) > 0.5 { item.length = w }
            let h = item.button?.bounds.height ?? 22
            host.frame = NSRect(x: 0, y: (h - size.height) / 2, width: w, height: size.height)
        }
    }

    @objc func itemClicked(_ sender: NSStatusBarButton) {
        guard let entry = items.first(where: { $0.item.button === sender }) else { return }
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu(on: entry.item); return }
        if let mod = MenuModule(rawValue: entry.key) { Nav.shared.tab = mod.tab }
        if popover.isShown && anchor === entry.item { popover.performClose(nil); return }
        show(from: entry.item)
    }

    // Apre il pannello se e' chiuso (es. clic su una notifica)
    func togglePopoverOpen() {
        if !popover.isShown, let first = items.first?.item { show(from: first) }
    }

    // Scorciatoia: apre/chiude il popover sul primo elemento
    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        if let first = items.first?.item { show(from: first) }
    }

    func show(from item: NSStatusItem) {
        if popover.isShown { popover.performClose(nil) }
        guard let button = item.button else { return }
        anchor = item
        monitor.detailed = true
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate()
    }

    func showMenu(on item: NSStatusItem) {
        let menu = NSMenu()
        menu.addItem(withTitle: L("Impostazioni…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        let awake = menu.addItem(withTitle: monitor.awake.isActive ? L("Disattiva \"tieni sveglio\"") : L("Tieni sveglio il Mac"), action: #selector(toggleAwake), keyEquivalent: "")
        awake.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Esci da MenuStats"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc func toggleAwake() { monitor.awake.isActive ? monitor.awake.stop() : monitor.awake.start(minutes: nil) }

    func popoverDidClose(_ n: Notification) { monitor.detailed = false }

    @objc func openSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "MenuStats"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.appearance = NSAppearance(named: Theme.dark ? .darkAqua : .aqua)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            settingsWindow = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ n: Notification) {
        if (n.object as? NSWindow) == settingsWindow { NSApp.setActivationPolicy(.accessory) }
    }

    func applicationWillTerminate(_ n: Notification) {
        monitor.mixer.stopAll()        // restituisce l'audio alle app
        monitor.awake.stop()
        monitor.awake.setAuto(nil)
        HistoryStore.shared.save()
    }

    // ------------------------------------------------------------ ⌥⌘M (Carbon: nessun permesso richiesto)
    func installHotKeyHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let id = Int(hk.id)
            DispatchQueue.main.async {
                if id == 1 { AppDelegate.shared?.togglePopover() }
                else if id >= 11, id - 11 < tabs.count { AppDelegate.shared?.openTab(tabs[id - 11].id) }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }

    func registerHotKey() {
        if let r = hotKeyRef { UnregisterEventHotKey(r); hotKeyRef = nil }
        tabHotKeys.forEach { UnregisterEventHotKey($0) }
        tabHotKeys.removeAll()
        if Prefs.shared.c.hotkeyEnabled {
            RegisterEventHotKey(UInt32(kVK_ANSI_M), UInt32(cmdKey | optionKey), EventHotKeyID(signature: OSType(0x4D535431), id: 1),
                                GetApplicationEventTarget(), 0, &hotKeyRef)
        }
        guard Prefs.shared.c.tabHotkeys else { return }
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8]
        for (i, key) in digits.enumerated() where i < tabs.count {
            var ref: EventHotKeyRef?
            RegisterEventHotKey(UInt32(key), UInt32(cmdKey | optionKey), EventHotKeyID(signature: OSType(0x4D535431), id: UInt32(11 + i)),
                                GetApplicationEventTarget(), 0, &ref)
            if let ref { tabHotKeys.append(ref) }
        }
    }

    // ⌥⌘1…8: apre il pannello sulla scheda (o la cambia se e' gia' aperto)
    func openTab(_ tab: String) {
        Nav.shared.tab = tab
        togglePopoverOpen()
    }
}

let app = NSApplication.shared
if let i = CommandLine.arguments.firstIndex(of: "--screenshots"), i + 1 < CommandLine.arguments.count {
    Screenshots.run(URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--icon"), i + 1 < CommandLine.arguments.count {
    Screenshots.icon(URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--gifs"), i + 1 < CommandLine.arguments.count {
    Screenshots.gifs(URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    exit(0)
}
// MenuStats --debug: stampa i dati raccolti (per sviluppo)
if CommandLine.arguments.contains("--debug") {
    let m = Monitor.shared
    m.detailed = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
        print("cpu \(formatPercent(m.cpu)) mem \(formatBytes(m.memory.used)) soc \(m.sensors.socTemperature ?? -1)")
        for a in m.agents {
            print("agent \(a.kind) \(a.project) busy=\(a.isBusy) terminal=\(a.terminal ?? "-")")
            if let c = a.claude {
                print("   model=\(c.model ?? "-") tokens=\(formatTokens(c.totalTokens)) out=\(formatTokens(c.outputTokens)) file=\((c.file as NSString).lastPathComponent)")
                print("   last=\(c.lastText.map { String($0.prefix(80)) } ?? "-")")
            }
        }
        let w = readWiFi()
        print("wifi", w.map { "\($0.ssid ?? "(ssid nascosto)") \($0.rssi)dBm \($0.txRate)Mbit \($0.band ?? "")" } ?? "nessuno", "vpn", activeVPNs().map { "\($0.iface) \($0.ip)" })
        print("ports", m.devPorts.map { ":\($0.port) \($0.label)" }, "alerts", m.alerts.map(\.title))
        exit(0)
    }
    RunLoop.main.run()
}
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
