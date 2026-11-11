// Audio: dispositivi, volume generale, chi usa il microfono e volume per singola app.
// Il volume per app usa i "process tap" di Core Audio (macOS 14.2+): l'audio dell'app viene
// intercettato e silenziato all'origine, poi riprodotto sull'uscita con il guadagno scelto.
// Nessun driver da installare; serve il permesso "Registrazione audio di sistema".
import AppKit
import CoreAudio
import AudioToolbox

// ================================================================ helper Core Audio
func caAddress(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
               _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: element)
}

func caGet<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
              element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain, default d: T) -> T {
    var a = caAddress(sel, scope, element)
    var v = d
    var size = UInt32(MemoryLayout<T>.size)
    return AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v) == noErr ? v : d
}

func caString(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> String? {
    var a = caAddress(sel, scope)
    var v: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v) == noErr, let s = v?.takeRetainedValue() else { return nil }
    return s as String
}

func caArray(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
    var a = caAddress(sel, scope)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(obj, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

func caHas(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) -> Bool {
    var a = caAddress(sel, scope, element)
    return AudioObjectHasProperty(obj, &a)
}

func caSettable(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) -> Bool {
    var a = caAddress(sel, scope, element)
    var s: DarwinBoolean = false
    return AudioObjectIsPropertySettable(obj, &a, &s) == noErr && s.boolValue
}

let systemObject = AudioObjectID(kAudioObjectSystemObject)

// ================================================================ dispositivi
struct AudioDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let hasOutput: Bool
    let hasInput: Bool
}

func audioDevices() -> [AudioDevice] {
    caArray(systemObject, kAudioHardwarePropertyDevices).compactMap { id in
        guard let uid = caString(id, kAudioDevicePropertyDeviceUID), let name = caString(id, kAudioObjectPropertyName) else { return nil }
        // i dispositivi aggregati privati (anche i nostri) non vanno mostrati
        if uid.hasPrefix("MenuStats") { return nil }
        let outs = caArray(id, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput).count
        let ins = caArray(id, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput).count
        return AudioDevice(id: id, uid: uid, name: name, hasOutput: outs > 0, hasInput: ins > 0)
    }
}

func defaultDevice(input: Bool) -> AudioObjectID {
    caGet(systemObject, input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice, default: AudioObjectID(0))
}

func setDefaultDevice(_ id: AudioObjectID, input: Bool) {
    var a = caAddress(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
    var v = id
    AudioObjectSetPropertyData(systemObject, &a, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &v)
}

// Volume del dispositivo: elemento principale se esiste, altrimenti media dei canali 1 e 2
func deviceVolume(_ id: AudioObjectID, input: Bool = false) -> Float? {
    let scope = input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
    if caHas(id, kAudioDevicePropertyVolumeScalar, scope: scope, element: kAudioObjectPropertyElementMain) {
        return caGet(id, kAudioDevicePropertyVolumeScalar, scope: scope, default: Float(0))
    }
    let ch = [UInt32(1), 2].filter { caHas(id, kAudioDevicePropertyVolumeScalar, scope: scope, element: $0) }
    guard !ch.isEmpty else { return nil }
    return ch.map { caGet(id, kAudioDevicePropertyVolumeScalar, scope: scope, element: $0, default: Float(0)) }.reduce(0, +) / Float(ch.count)
}

func setDeviceVolume(_ id: AudioObjectID, _ v: Float, input: Bool = false) {
    let scope = input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
    var value = max(0, min(1, v))
    let elements: [UInt32] = caSettable(id, kAudioDevicePropertyVolumeScalar, scope: scope, element: kAudioObjectPropertyElementMain)
        ? [kAudioObjectPropertyElementMain] : [1, 2]
    for e in elements where caSettable(id, kAudioDevicePropertyVolumeScalar, scope: scope, element: e) {
        var a = caAddress(kAudioDevicePropertyVolumeScalar, scope, e)
        AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<Float>.size), &value)
    }
}

func deviceMuted(_ id: AudioObjectID) -> Bool {
    caGet(id, kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput, default: UInt32(0)) != 0
}

func setDeviceMuted(_ id: AudioObjectID, _ m: Bool) {
    var a = caAddress(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput)
    var v: UInt32 = m ? 1 : 0
    AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
}

// ================================================================ processi audio
struct AudioProcess {
    let object: AudioObjectID
    let pid: pid_t
    let bundleID: String?
    let playing: Bool
    let recording: Bool
}

func audioProcesses() -> [AudioProcess] {
    caArray(systemObject, kAudioHardwarePropertyProcessObjectList).map { obj in
        AudioProcess(object: obj,
                     pid: caGet(obj, kAudioProcessPropertyPID, default: pid_t(-1)),
                     bundleID: caString(obj, kAudioProcessPropertyBundleID),
                     playing: caGet(obj, kAudioProcessPropertyIsRunningOutput, default: UInt32(0)) != 0,
                     recording: caGet(obj, kAudioProcessPropertyIsRunningInput, default: UInt32(0)) != 0)
    }
}

// Un'app che produce (o ha prodotto) audio, con tutti i suoi processi (es. helper di Chrome)
struct AudioApp: Identifiable {
    var id: String { key }
    let key: String              // bundle id dell'app (chiave per ricordare il volume)
    let name: String
    let icon: NSImage?
    var objects: [AudioObjectID]
    var playing: Bool
    var recording: Bool
}

func audioApps() -> [AudioApp] {
    var apps: [String: AudioApp] = [:]
    for p in audioProcesses() where p.pid > 0 && p.pid != getpid() {
        // risale all'app proprietaria tramite il percorso (.app piu' esterna)
        let path = ProcessReader.path(p.pid)
        guard let r = path.range(of: ".app/") else { continue }      // demoni di sistema: esclusi
        let bundlePath = String(path[..<r.upperBound].dropLast())
        let bundle = Bundle(path: bundlePath)
        let key = bundle?.bundleIdentifier ?? bundlePath
        if apps[key] == nil {
            let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? ((bundlePath as NSString).lastPathComponent as NSString).deletingPathExtension
            apps[key] = AudioApp(key: key, name: name, icon: NSWorkspace.shared.icon(forFile: bundlePath),
                                 objects: [], playing: false, recording: false)
        }
        apps[key]!.objects.append(p.object)
        apps[key]!.playing = apps[key]!.playing || p.playing
        apps[key]!.recording = apps[key]!.recording || p.recording
    }
    return apps.values.sorted { ($0.playing ? 0 : 1, $0.name) < ($1.playing ? 0 : 1, $1.name) }
}

// ================================================================ volume per app
// Guadagno letto dal thread audio: classe separata, scrittura atomica di un Float su arm64/x86
final class GainBox { var gain: Float = 1 }

final class AppVolumeTap {
    let objects: [AudioObjectID]
    let box = GainBox()
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "menustats.audio", qos: .userInteractive)

    init(objects: [AudioObjectID], outputUID: String, gain: Float) throws {
        self.objects = objects
        box.gain = gain
        let desc = CATapDescription(stereoMixdownOfProcesses: objects)
        desc.uuid = UUID()
        desc.muteBehavior = .mutedWhenTapped
        desc.isPrivate = true
        desc.name = "MenuStats per-app volume"
        var err = AudioHardwareCreateProcessTap(desc, &tapID)
        guard err == noErr else { throw NSError(domain: "tap", code: Int(err)) }

        let agg: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MenuStats",
            kAudioAggregateDeviceUIDKey: "MenuStats-" + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        err = AudioHardwareCreateAggregateDevice(agg as CFDictionary, &aggregateID)
        guard err == noErr else { teardown(); throw NSError(domain: "aggregate", code: Int(err)) }

        let box = self.box
        err = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, inInput, _, outOutput, _ in
            Self.render(UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInput)),
                        UnsafeMutableAudioBufferListPointer(outOutput), gain: box.gain)
        }
        guard err == noErr else { teardown(); throw NSError(domain: "ioproc", code: Int(err)) }
        err = AudioDeviceStart(aggregateID, procID)
        guard err == noErr else { teardown(); throw NSError(domain: "start", code: Int(err)) }
    }

    // Copia l'audio intercettato (Float32) sull'uscita applicando il guadagno, adattando
    // interleaved/non-interleaved e il numero di canali.
    static func render(_ input: UnsafeMutableAudioBufferListPointer, _ output: UnsafeMutableAudioBufferListPointer, gain: Float) {
        // canali in ingresso come (buffer, canale, stride)
        var inCh: [(UnsafeMutablePointer<Float>, Int, Int)] = []   // (base, offset, stride)
        var frames = Int.max
        for b in input {
            guard let d = b.mData else { continue }
            let n = Int(max(b.mNumberChannels, 1))
            let f = Int(b.mDataByteSize) / (4 * n)
            frames = min(frames, f)
            for c in 0..<n { inCh.append((d.assumingMemoryBound(to: Float.self), c, n)) }
        }
        for b in output {
            guard let d = b.mData else { continue }
            let n = Int(max(b.mNumberChannels, 1))
            let f = Int(b.mDataByteSize) / (4 * n)
            let out = d.assumingMemoryBound(to: Float.self)
            if inCh.isEmpty || frames == .max { memset(d, 0, Int(b.mDataByteSize)); continue }
            let count = min(f, frames)
            for c in 0..<n {
                let src = inCh[min(c, inCh.count - 1)]
                for i in 0..<count { out[i * n + c] = src.0[i * src.2 + src.1] * gain }
            }
            if f > count { memset(out + count * n, 0, (f - count) * n * 4) }
        }
    }

    func teardown() {
        if let p = procID {
            AudioDeviceStop(aggregateID, p)
            AudioDeviceDestroyIOProcID(aggregateID, p)
            procID = nil
        }
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID); aggregateID = AudioObjectID(kAudioObjectUnknown) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID); tapID = AudioObjectID(kAudioObjectUnknown) }
    }

    deinit { teardown() }
}

// Gestisce i tap attivi: uno per app con volume diverso dal 100%
final class AppVolumeMixer {
    private var taps: [String: AppVolumeTap] = [:]
    private(set) var lastError: String?

    // volumes: bundle id -> guadagno (0...1.5); le app al 100% non vengono toccate
    func apply(apps: [AudioApp], volumes: [String: Double]) {
        let outID = defaultDevice(input: false)
        guard let outUID = caString(outID, kAudioDevicePropertyDeviceUID) else { return }
        var wanted = Set<String>()
        for app in apps {
            let g = Float(volumes[app.key] ?? 1)
            guard abs(g - 1) > 0.005 else { continue }
            wanted.insert(app.key)
            if let t = taps[app.key], Set(t.objects) == Set(app.objects) {
                t.box.gain = g
            } else {
                taps[app.key]?.teardown()
                do {
                    taps[app.key] = try AppVolumeTap(objects: app.objects, outputUID: outUID, gain: g)
                    lastError = nil
                } catch {
                    taps[app.key] = nil
                    lastError = "Volume per app non disponibile (\((error as NSError).domain) \((error as NSError).code)). Controlla il permesso \"Registrazione audio di sistema\"."
                }
            }
        }
        for (k, t) in taps where !wanted.contains(k) { t.teardown(); taps[k] = nil }
    }

    // L'uscita e' cambiata: i tap vanno ricreati sul nuovo dispositivo
    func rebuild(apps: [AudioApp], volumes: [String: Double]) {
        taps.values.forEach { $0.teardown() }
        taps.removeAll()
        apply(apps: apps, volumes: volumes)
    }

    func stopAll() { taps.values.forEach { $0.teardown() }; taps.removeAll() }
}

// Notifica quando cambiano dispositivo di uscita o elenco dei processi audio
func observeAudio(_ handler: @escaping () -> Void) {
    for sel in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice,
                kAudioHardwarePropertyProcessObjectList, kAudioHardwarePropertyDevices] {
        var a = caAddress(sel)
        AudioObjectAddPropertyListenerBlock(systemObject, &a, DispatchQueue.main) { _, _ in handler() }
    }
}
