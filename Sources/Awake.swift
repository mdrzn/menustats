// "Tieni sveglio": asserzioni di alimentazione (come il comando caffeinate) e chi altro sta
// impedendo lo stop del Mac.
import Foundation
import IOKit.pwr_mgt

final class AwakeController: ObservableObject {
    enum Mode: String, CaseIterable, Codable { case system, display }
    @Published private(set) var activeUntil: Date?      // .distantFuture = senza limite
    @Published private(set) var isActive = false
    @Published var mode: Mode = .system
    private var assertion: IOPMAssertionID = 0
    private var autoAssertion: IOPMAssertionID = 0
    @Published private(set) var autoReason: String?     // "tieni sveglio" automatico attivo, e perche'
    private var timer: Timer?

    // Regola automatica (agenti, server, alimentatore): asserzione separata da quella manuale
    func setAuto(_ reason: String?) {
        if autoAssertion != 0 { IOPMAssertionRelease(autoAssertion); autoAssertion = 0 }
        autoReason = reason
        guard reason != nil else { return }
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                    "MenuStats: keep awake (automatic)" as CFString, &autoAssertion)
    }

    func start(minutes: Int?) {
        stop()
        let type = (mode == .display ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep) as CFString
        let ok = IOPMAssertionCreateWithName(type, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                             "MenuStats: keep awake" as CFString, &assertion)
        guard ok == kIOReturnSuccess else { return }
        isActive = true
        if let m = minutes {
            activeUntil = Date().addingTimeInterval(TimeInterval(m * 60))
            timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(m * 60), repeats: false) { [weak self] _ in self?.stop() }
        } else {
            activeUntil = .distantFuture
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }
        isActive = false; activeUntil = nil
    }

    var remaining: TimeInterval? {
        guard let u = activeUntil, u != .distantFuture else { return nil }
        return max(0, u.timeIntervalSinceNow)
    }
}

// Asserzioni degli altri processi (cosa tiene sveglio il Mac in questo momento)
struct SleepBlocker: Identifiable {
    var id: String { "\(pid)-\(name)" }
    let pid: pid_t
    let process: String
    let name: String
    let type: String
}

func readSleepBlockers() -> [SleepBlocker] {
    var dict: Unmanaged<CFDictionary>?
    guard IOPMCopyAssertionsByProcess(&dict) == kIOReturnSuccess,
          let byPid = dict?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
    let relevant: Set<String> = ["PreventUserIdleSystemSleep", "PreventUserIdleDisplaySleep", "PreventSystemSleep", "NoIdleSleepAssertion", "NoDisplaySleepAssertion"]
    var out: [SleepBlocker] = []
    for (pid, list) in byPid {
        for a in list {
            let type = a["AssertType"] as? String ?? ""
            guard relevant.contains(type) else { continue }
            let p = pid_t(pid.int32Value)
            guard p != getpid() else { continue }
            let proc = a["Process Name"] as? String ?? ((ProcessReader.path(p) as NSString).lastPathComponent)
            out.append(SleepBlocker(pid: p, process: proc, name: a["AssertName"] as? String ?? "", type: type.contains("Display") ? L("schermo") : L("sistema")))
        }
    }
    return out.sorted { $0.process < $1.process }
}
