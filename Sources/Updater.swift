// Aggiornamenti: legge l'ultima release di GitHub una volta al giorno (disattivabile) e, se
// richiesto, scarica lo zip, sostituisce l'app nella stessa posizione e la riavvia.
import AppKit

final class Updater: ObservableObject {
    static let shared = Updater()
    @Published var latest: String?          // versione piu' recente se diversa da quella installata
    @Published var url: URL?                // pagina della release
    @Published var installing = false
    @Published var error: String?
    private var asset: URL?                 // MenuStats.zip della release
    private var timer: Timer?

    func start() {
        guard !Monitor.demoMode else { return }
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { [weak self] _ in self?.check() }
    }

    func check() {
        // MENUSTATS_UPDATE_FEED: release finta per provare l'aggiornamento senza GitHub
        let feed = ProcessInfo.processInfo.environment["MENUSTATS_UPDATE_FEED"] ?? "https://api.github.com/repos/mdrzn/menustats/releases/latest"
        guard Prefs.shared.c.checkUpdates, let api = URL(string: feed) else { return }
        var req = URLRequest(url: api)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }
            let remote = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let page = (json["html_url"] as? String).flatMap(URL.init(string:))
            let zip = (json["assets"] as? [[String: Any]])?
                .first { ($0["name"] as? String) == "MenuStats.zip" }?["browser_download_url"] as? String
            DispatchQueue.main.async {
                guard let self else { return }
                if Self.isNewer(remote, than: appVersion) {
                    self.latest = remote; self.url = page; self.asset = zip.flatMap(URL.init(string:))
                    if Prefs.shared.c.autoInstallUpdates { self.installWhenIdle() }
                } else {
                    self.latest = nil
                }
            }
        }.resume()
    }

    // Installazione automatica: aspetta che il pannello sia chiuso, per non interrompere l'utente
    private func installWhenIdle() {
        if Monitor.shared.detailed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.installWhenIdle() }
        } else {
            install()
        }
    }

    // Scarica, verifica, sostituisce l'app e la riavvia
    func install() {
        guard !installing, let asset, let latest else { if let url { NSWorkspace.shared.open(url) }; return }
        installing = true; error = nil
        URLSession.shared.downloadTask(with: asset) { [weak self] tmp, _, err in
            guard let self else { return }
            do {
                guard let tmp else { throw UpdateError(err?.localizedDescription ?? "download failed") }
                try self.replaceApp(withZip: tmp, expectedVersion: latest)
                DispatchQueue.main.async { self.relaunch() }
            } catch {
                DispatchQueue.main.async {
                    self.installing = false
                    self.error = (error as? UpdateError)?.message ?? error.localizedDescription
                }
            }
        }.resume()
    }

    private struct UpdateError: Error { let message: String; init(_ m: String) { message = m } }

    private func replaceApp(withZip zip: URL, expectedVersion: String) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("menustats-update-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        // estrazione con ditto (come lo zip e' stato creato)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, work.path]
        try ditto.run(); ditto.waitUntilExit()
        let newApp = work.appendingPathComponent("MenuStats.app")
        guard ditto.terminationStatus == 0, let bundle = Bundle(url: newApp) else { throw UpdateError("the download is not a valid app") }

        // e' davvero MenuStats, ed e' la versione annunciata?
        guard bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              let v = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              v == expectedVersion, Self.isNewer(v, than: appVersion) else { throw UpdateError("unexpected app or version in the download") }

        // l'app attuale va nel Cestino (recuperabile), la nuova prende il suo posto
        let current = Bundle.main.bundleURL
        guard fm.isWritableFile(atPath: current.deletingLastPathComponent().path) else {
            throw UpdateError("no permission to replace \(current.path)")
        }
        var trashed: NSURL?
        try fm.trashItem(at: current, resultingItemURL: &trashed)
        do {
            try fm.moveItem(at: newApp, to: current)
        } catch {
            if let back = trashed as URL? { try? fm.moveItem(at: back, to: current) }   // rimette la vecchia
            throw UpdateError("could not install the new version: \(error.localizedDescription)")
        }
        // niente blocco di Gatekeeper sull'app scaricata da noi stessi
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", current.path]
        try? xattr.run(); xattr.waitUntilExit()
    }

    // Avvia la nuova copia appena questa si e' chiusa
    private func relaunch() {
        let path = Bundle.main.bundleURL.path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"\(path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }

    // Confronto numerico per componenti: "0.10" > "0.9"
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}
