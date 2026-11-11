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
    var statusItem: NSStatusItem!
    var hosting: PassthroughHostingView<MenuBarView>!
    let popover = NSPopover()
    var settingsWindow: NSWindow?
    var hotKeyRef: EventHotKeyRef?
    var bag = Set<AnyCancellable>()
    let monitor = Monitor.shared

    func applicationDidFinishLaunching(_ n: Notification) {
        AppDelegate.shared = self
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            hosting = PassthroughHostingView(rootView: MenuBarView())
            hosting.translatesAutoresizingMaskIntoConstraints = true
            button.addSubview(hosting)
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        resizeStatusItem()
        // ad ogni aggiornamento la larghezza dell'elemento segue il contenuto
        monitor.objectWillChange.merge(with: Prefs.shared.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.resizeStatusItem() } }
            .store(in: &bag)

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.appearance = NSAppearance(named: .darkAqua)
        // Dimensione fissa da subito: senza, al primo clic SwiftUI calcola la misura dopo
        // l'apertura e il popover compare in un punto provvisorio prima di spostarsi.
        let size = NSSize(width: 480, height: 620)
        let controller = NSHostingController(rootView: PopoverView())
        controller.sizingOptions = []
        controller.view.frame = NSRect(origin: .zero, size: size)
        controller.view.layoutSubtreeIfNeeded()
        popover.contentSize = size
        popover.contentViewController = controller

        installHotKeyHandler()
        registerHotKey()
    }

    func resizeStatusItem() {
        guard let hosting else { return }
        let size = hosting.fittingSize
        let w = ceil(size.width)
        if abs((statusItem.length) - w) > 0.5 { statusItem.length = w }
        let h = statusItem.button?.bounds.height ?? 22
        hosting.frame = NSRect(x: 0, y: (h - size.height) / 2, width: w, height: size.height)
    }

    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        // clic destro: menu rapido
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu(); return }
        monitor.detailed = true
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate()
    }

    func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Impostazioni…", action: #selector(openSettings), keyEquivalent: ",").target = self
        let awake = menu.addItem(withTitle: monitor.awake.isActive ? "Disattiva \"tieni sveglio\"" : "Tieni sveglio il Mac", action: #selector(toggleAwake), keyEquivalent: "")
        awake.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Esci da MenuStats", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
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
            w.appearance = NSAppearance(named: .darkAqua)
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
    }

    // ------------------------------------------------------------ ⌥⌘M (Carbon: nessun permesso richiesto)
    func installHotKeyHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { AppDelegate.shared?.togglePopover() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    func registerHotKey() {
        if let r = hotKeyRef { UnregisterEventHotKey(r); hotKeyRef = nil }
        guard Prefs.shared.c.hotkeyEnabled else { return }
        RegisterEventHotKey(UInt32(kVK_ANSI_M), UInt32(cmdKey | optionKey), EventHotKeyID(signature: OSType(0x4D535431), id: 1),
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

let app = NSApplication.shared
if let i = CommandLine.arguments.firstIndex(of: "--screenshots"), i + 1 < CommandLine.arguments.count {
    Screenshots.run(URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
