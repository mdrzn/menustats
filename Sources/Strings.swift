// Lingua dell'interfaccia: italiano (testi nel codice) o inglese (dizionario sotto).
// L("Testo") ritorna il testo nella lingua scelta; L("%d app", n) formatta.
import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system, italian, english
    var id: String { rawValue }
    var title: String {
        switch self { case .system: L("Come il sistema"); case .italian: "Italiano"; case .english: "English" }
    }
}

enum Lang {
    // Ricalcolato quando cambia l'impostazione (Prefs) e all'avvio
    static var english = resolve(.system)

    static func resolve(_ l: AppLanguage) -> Bool {
        switch l {
        case .english: return true
        case .italian: return false
        case .system: return !(Locale.preferredLanguages.first ?? "en").hasPrefix("it")
        }
    }
}

func L(_ s: String) -> String { Lang.english ? (english[s] ?? s) : s }
func L(_ s: String, _ args: CVarArg...) -> String { String(format: L(s), arguments: args) }

// Chiavi non tradotte: per un controllo in fase di sviluppo (MenuStats --missing-strings)
func missingTranslations(_ keys: [String]) -> [String] { keys.filter { english[$0] == nil } }

private let english: [String: String] = [
    // ---------------------------------------------------------------- generale
    "Come il sistema": "Same as system",
    "Panoramica": "Overview", "Home": "Home", "App": "Apps", "Sistema": "System", "Rete": "Network",
    "Volume": "Volume", "Porte": "Ports", "Agenti": "Agents", "Agenti AI": "AI agents", "Sveglio": "Awake",
    "Impostazioni": "Settings", "Impostazioni…": "Settings…", "Esci da MenuStats": "Quit MenuStats",
    "%@ · acceso da %@": "%@ · up %@", "Raccolta dati…": "Collecting data…", "Aggiorna": "Refresh",
    "made by mdrzn": "made by mdrzn", "Made by ": "Made by ",
    // ---------------------------------------------------------------- panoramica
    "MEMORIA": "MEMORY", "RETE": "NETWORK", "DISCO": "DISK", "BATTERIA": "BATTERY", "CHIP": "CHIP", "SWAP": "SWAP",
    "%d core": "%d cores", "su %@": "of %@", "%@ liberi": "%@ free", "in carica": "charging",
    "Da controllare": "Needs attention", "App più attive": "Top apps", "CPU · MEMORIA": "CPU · MEMORY",
    "Tieni sveglio": "Keep awake", "Attivo": "On", "Spento": "Off", "ancora %@": "%@ left", "senza limite": "no time limit",
    "il Mac va in stop normalmente": "the Mac sleeps normally", "Porte in ascolto": "Listening ports",
    // ---------------------------------------------------------------- avvisi
    "Memoria sotto pressione": "Memory under pressure", "%@ usati su %@": "%@ used of %@",
    "Disco quasi pieno": "Disk almost full", "Il Mac è molto caldo": "The Mac is very hot",
    "macOS sta limitando le prestazioni": "macOS is throttling performance", "%@ usa molta CPU": "%@ is using a lot of CPU",
    "%@ da un po'": "%@ for a while", "Chiudi": "Quit", "Chiudi %d": "Quit %d",
    "Un server di sviluppo orfano": "An orphaned dev server", "%d server di sviluppo orfani": "%d orphaned dev servers",
    // ---------------------------------------------------------------- app
    "%d app · %d processi": "%d apps · %d processes", "Cerca app o processo": "Search apps or processes",
    "Memoria": "Memory", "App / processo": "App / process", "Mem": "Mem",
    "Riavvia": "Restart", "Riavvio…": "Restarting…", "Esci": "Quit", "Forza uscita": "Force quit", "Mostra nel Finder": "Show in Finder",
    "Termina": "Terminate", "Forza chiusura": "Force kill", "Runtime protetto": "Hardened runtime", "Runtime non protetto": "No hardened runtime",
    "Sandbox": "Sandbox", "Senza sandbox": "No sandbox", "Team ID": "Team ID", "Tempo CPU": "CPU time", "Thread": "Threads",
    "Avviato": "Started", "%@ fa": "%@ ago", "non si è chiusa: controlla se chiede di salvare": "didn't quit: check whether it's asking to save",
    // ---------------------------------------------------------------- sistema
    "Processore": "Processor", "utente %@ · sistema %@": "user %@ · system %@",
    "temperatura normale": "normal temperature", "un po' caldo": "a bit warm", "caldo: prestazioni ridotte": "hot: performance reduced",
    "molto caldo": "very hot", "pressione normale": "normal pressure", "pressione alta": "high pressure", "pressione critica": "critical pressure",
    "Wired": "Wired", "Compr.": "Compr.", "Cache": "Cache", "Sensori": "Sensors", "sperimentale": "experimental",
    "Sensori non disponibili su questo Mac.": "Sensors aren't available on this Mac.", "Chip": "Chip", "SSD": "SSD",
    "Consumo": "Power", "Ventola": "Fan", "Ventola %d": "Fan %d", "Nascondi i sensori": "Hide sensors",
    "Tutti i sensori (%d)": "All sensors (%d)", "Disco": "Disk", "%@ liberi su %@": "%@ free of %@", "GPU": "GPU",
    "Batteria": "Battery", "alimentatore": "power adapter", "a batteria": "on battery", " alla carica": " to full", " rimanenti": " left",
    // ---------------------------------------------------------------- rete
    "Download": "Download", "Upload": "Upload", "picco ↓ %@ · ↑ %@": "peak ↓ %@ · ↑ %@", "ultimi %d campioni": "last %d samples",
    "Per app": "Per app", "misurato ogni 3 s": "measured every 3 s", "Nessun traffico in questo momento.": "No traffic right now.",
    "Interfacce": "Interfaces", "Ethernet / Wi-Fi (en0)": "Ethernet / Wi-Fi (en0)", "Nessuna rete attiva.": "No active network.",
    // ---------------------------------------------------------------- volume
    "Microfono in uso da ": "Microphone in use by ", "Uscita": "Output", "Ingresso": "Input", "Muto": "Mute",
    "Volume per app": "Per-app volume", "Attiva": "Turn on", "Disattiva": "Turn off",
    "Regola il volume di ogni app da 0 a 150%, senza installare driver. Per farlo MenuStats intercetta il suono dell'app e lo riproduce lui: macOS chiederà il permesso di **registrazione audio di sistema**. Niente viene registrato o salvato.":
        "Set each app's volume from 0 to 150%, with no driver to install. To do this MenuStats captures the app's sound and plays it back itself, so macOS will ask for the **System Audio Recording** permission. Nothing is recorded or saved.",
    "%d in riproduzione": "%d playing", "Nessuna app sta usando l'audio.": "No app is using audio.",
    "Il volume scelto viene ricordato per ogni app.": "The volume you pick is remembered for each app.",
    "in riproduzione": "playing", "inattiva": "idle",
    // ---------------------------------------------------------------- porte
    "%d in ascolto": "%d listening", "Sviluppo": "Development", "passa sopra per le azioni": "hover for actions",
    "Nessun server in ascolto. Avvia un progetto e comparirà qui, con la cartella e chi l'ha lanciato.":
        "No servers listening. Start a project and it will show up here, with its folder and who started it.",
    "Docker": "Docker", "%d attivi": "%d running", "Nessun container.": "No containers.", "Servizi di macOS (%d)": "macOS services (%d)",
    "solo locale": "local only", "rete": "network", "orfano": "orphaned", "Apri nel browser": "Open in browser",
    "Termina il processo": "Terminate the process", "Ferma": "Stop", "Avvia": "Start", "Copia URL": "Copy URL",
    // ---------------------------------------------------------------- agenti
    "%d al lavoro · %d sessioni": "%d working · %d sessions", "Nessuna sessione attiva": "No active sessions",
    "Qui compaiono le sessioni di Claude Code, Codex, Gemini CLI, Aider, OpenCode, Cursor Agent, Amp e Goose: cartella del progetto, terminale, risorse usate e porte aperte.":
        "Sessions of Claude Code, Codex, Gemini CLI, Aider, OpenCode, Cursor Agent, Amp and Goose show up here: project folder, terminal, resources used and open ports.",
    "al lavoro": "working", "in attesa": "waiting", "Da": "Running", "Processi": "Processes", "Terminale": "Terminal",
    "Apri la cartella": "Open folder", "Termina la sessione": "End session",
    // ---------------------------------------------------------------- sveglio
    "Il Mac resta sveglio": "The Mac stays awake", "Stop normale": "Normal sleep", "finché non lo spegni": "until you turn it off",
    "Il Mac va in stop secondo le impostazioni di sistema": "The Mac sleeps according to System Settings",
    "15 min": "15 min", "1 ora": "1 hour", "2 ore": "2 hours", "4 ore": "4 hours", "Sempre": "Always",
    "Solo il Mac": "Mac only", "Mac e schermo": "Mac and display", "Chi impedisce lo stop": "What's preventing sleep",
    "Nessuna app sta tenendo sveglio il Mac.": "No app is keeping the Mac awake.", "schermo": "display", "sistema": "system",
    "Tieni sveglio il Mac": "Keep the Mac awake", "Disattiva \"tieni sveglio\"": "Turn off \"keep awake\"",
    // ---------------------------------------------------------------- impostazioni
    "Barra dei menu": "Menu bar", "Generale": "General", "Informazioni": "About", "Aspetto": "Look",
    "Impilato": "Stacked", "Compatto": "Compact", "Grafico": "Graph", "Pillola": "Pill", "Contorno": "Outline", "Icone": "Icons",
    "Colore dei valori": "Value colour", "Come la barra": "Like the menu bar", "Accento": "Accent", "Per carico": "By load", "per carico": "by load",
    "Carattere": "Font", "Arrotondato": "Rounded", "Monospaziato": "Monospaced", "Colore d'accento": "Accent colour",
    "Elementi mostrati": "Items shown", "Sposta a sinistra": "Move left", "Sposta a destra": "Move right",
    "Trascina l'ordine con le frecce. Temperatura e consumo usano sensori sperimentali.": "Reorder with the arrows. Temperature and power use experimental sensors.",
    "Aggiornamento": "Refresh", "Frequenza nella barra dei menu": "Menu bar refresh rate",
    "Con il pannello aperto i dati si aggiornano ogni secondo.": "With the panel open, data refreshes every second.",
    "Preferenze": "Preferences", "Gradi Fahrenheit": "Fahrenheit", "Avvia al login": "Open at login",
    "Apri il pannello con ⌥⌘M": "Open the panel with ⌥⌘M", "Avvisi": "Alerts", "App che usano molta CPU": "Apps using a lot of CPU",
    "Soglia per almeno 10 secondi. 100% = un core pieno.": "Threshold held for at least 10 seconds. 100% = one full core.",
    "Sperimentale": "Experimental",
    "Richiede il permesso di registrazione audio di sistema: l'audio dell'app viene intercettato solo per cambiarne il volume.":
        "Needs the System Audio Recording permission: the app's audio is captured only to change its volume.",
    "Versione %@": "Version %@",
    "Un monitor di sistema open source per la barra dei menu, pensato per chi sviluppa: risorse, app, porte, agenti AI, audio e \"tieni sveglio\" in un solo pannello.":
        "An open-source menu bar system monitor for people who build things: resources, apps, ports, AI agents, audio and keep-awake in one panel.",
    "Licenza MIT. Nessun dato lascia il tuo Mac.": "MIT License. No data leaves your Mac.",
    // ---------------------------------------------------------------- moduli
    "Temperatura": "Temperature", "PORTE": "PORTS",
    "Automatico": "Automatic",
    "Grafite": "Graphite",
    "Mezzanotte": "Midnight",
    "Carta": "Paper",
    "Contrasto alto": "High contrast",
    "Pannello": "Panel",
    "Tema": "Theme",
    "Automatico segue l'aspetto chiaro/scuro di macOS.": "Automatic follows macOS light/dark appearance.",
    "Dimensione del testo": "Text size",
    "Compatta": "Compact",
    "Normale": "Normal",
    "Grande": "Large",
    "Sfondo": "Background",
    "Opaco": "Opaque",
    "Leggero": "Light",
    "Vetro": "Glass",
    "Colori per area": "Colours by area",
    "CPU, memoria, rete e temperatura con colori diversi nei grafici.": "CPU, memory, network and temperature in different colours in the charts.",
    "Lingua": "Language",
    "Musica": "Music",
    "Note": "Notes",
    "Anteprima": "Preview",
    "Riproduzione audio": "Playing audio",
    "Elementi separati": "Separate items",
    "Un elemento per ogni voce: cliccandolo il pannello si apre sulla scheda giusta. Con ⌘ puoi trascinarli.": "One item per entry: clicking it opens the panel on the right tab. Hold ⌘ to drag them.",
    "Modalità minima": "Minimal mode",
    "Solo un'icona, che diventa gialla o rossa quando c'è qualcosa da controllare.": "Just an icon that turns yellow or red when something needs attention.",
    "Verde fino a": "Green up to",
    "Rosso oltre": "Red above",
    "Nascondi le etichette": "Hide labels",
    "Ordina con le frecce; scrivi un'etichetta per sostituire quella predefinita. IP pubblico e ping contattano Internet (api.ipify.org e l'host del ping); temperatura e consumo usano sensori sperimentali.": "Reorder with the arrows; type a label to replace the default one. Public IP and ping contact the Internet (api.ipify.org and the ping host); temperature and power use experimental sensors.",
    "Host del ping": "Ping host",
    "Contatta Internet": "Contacts the Internet",
    "Etichetta personalizzata": "Custom label",
    "Colonne": "Columns",
    "Anello": "Ring",
    "Barra": "Bar",
    "Tachimetro": "Gauge",
    "Disco (uso)": "Disk (used)",
    "Disco (spazio libero)": "Disk (free space)",
    "Ora e data": "Time and date",
    "IP pubblico": "Public IP",
    "Ping": "Ping",
    "Tempo di accensione": "Uptime",
    "Tieni sveglio (indicatore)": "Keep awake (indicator)",
    "Microfono in uso (indicatore)": "Microphone in use (indicator)",
    "LIBERO": "FREE",
    "Menta": "Mint",
    "Laguna": "Lagoon",
    "Lavanda": "Lavender",
    "Corallo": "Coral",
    "Ambra": "Amber",
    "Lime": "Lime",
    "Ghiaccio": "Ice",
    "Mac molto caldo": "Mac very hot",
    "Agente AI che ha finito o aspetta": "AI agent finished or waiting",
    "Server di sviluppo che si ferma": "Dev server stops",
    "Riavvio automatico di un'app": "Automatic app restart",
    "%@ ha finito": "%@ finished",
    "In attesa in %@": "Waiting in %@",
    "Il server :%d si è fermato": "Server :%d stopped",
    "%@ riavviata": "%@ restarted",
    "Usava %@, oltre la soglia di %@": "It was using %@, over the %@ limit",
    "un agente AI è al lavoro": "an AI agent is working",
    "c'è un server di sviluppo acceso": "a dev server is running",
    "collegato all'alimentatore": "it's on the power adapter",
    "attivo": "on",
    "Sveglio perché %@": "Awake because %@",
    "Mentre un agente AI è al lavoro": "While an AI agent is working",
    "Mentre c'è un server di sviluppo acceso": "While a dev server is running",
    "Quando è collegato all'alimentatore": "When on the power adapter",
    "Modello": "Model",
    "Token": "Tokens",
    "Output": "Output",
    "In attesa da %@": "Waiting for %@",
    "Mai": "Never",
    "Oltre %@": "Over %@",
    "Riavvio auto oltre %@": "Auto-restart over %@",
    "Riavvio automatico": "Auto-restart",
    "Riavvia l'app da sola quando usa più memoria di così (al massimo una volta ogni 30 minuti)": "Restart the app automatically when it uses more memory than this (at most once every 30 minutes)",
    "Notifiche": "Notifications",
    "Alla prima notifica macOS chiede il permesso. Clic su una notifica: si apre la scheda giusta.": "macOS asks for permission at the first notification. Click a notification to open the right tab.",
]
