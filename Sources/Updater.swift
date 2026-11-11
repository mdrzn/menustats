// Controllo aggiornamenti: legge l'ultima release di GitHub una volta al giorno (disattivabile).
import AppKit

final class Updater: ObservableObject {
    static let shared = Updater()
    @Published var latest: String?          // versione piu' recente se diversa da quella installata
    @Published var url: URL?
    private var timer: Timer?

    func start() {
        guard !Monitor.demoMode else { return }
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { [weak self] _ in self?.check() }
    }

    func check() {
        guard Prefs.shared.c.checkUpdates,
              let api = URL(string: "https://api.github.com/repos/mdrzn/menustats/releases/latest") else { return }
        var req = URLRequest(url: api)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }
            let remote = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let page = (json["html_url"] as? String).flatMap(URL.init(string:))
            DispatchQueue.main.async {
                if Self.isNewer(remote, than: appVersion) { self?.latest = remote; self?.url = page } else { self?.latest = nil }
            }
        }.resume()
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
