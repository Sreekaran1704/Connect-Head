import AudioToolbox
import CoreAudio
import Foundation

/// Local history of what was played and how loud, for the Listening page. Fed by NowPlaying
/// on every poll: time accumulates into a session per track while it plays, and the Mac's output
/// volume is sampled into per-minute buckets while something plays through the headphones.
/// Stored as JSON in Application Support; nothing leaves the Mac. Kept for 120 days.
@MainActor
final class ListeningLog: ObservableObject {
    static let shared = ListeningLog()

    struct Session: Codable, Identifiable, Equatable {
        var id = UUID()
        var title: String
        var artist: String
        /// "Spotify", "Music", "YouTube" or "YouTube Music".
        var service: String
        var start: Date
        var seconds: Double

        var end: Date { start.addingTimeInterval(seconds) }
    }

    /// Volume for one minute of listening: `level` is the time-weighted average (0…1).
    struct VolumeMinute: Codable, Equatable {
        var minute: Date
        var level: Double
        var seconds: Double
    }

    @Published private(set) var sessions: [Session] = []
    @Published private(set) var volume: [VolumeMinute] = []

    private static let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Connect Head/listening.json")
    private static let retention: TimeInterval = 120 * 86_400

    private var lastTick: Date?
    private var saveScheduled = false

    private init() {
        load()
    }

    // MARK: Recording

    /// Called on every NowPlaying poll with what's playing now (or nil).
    func record(_ track: NowPlaying.Track?, headphonesName: String?, now: Date = .now) {
        defer { lastTick = now }
        guard let track, track.playing, let last = lastTick else { return }
        let dt = min(now.timeIntervalSince(last), 10)   // cap gaps (sleep, stalls)
        guard dt > 0 else { return }

        let service = track.service
        if var current = sessions.last, current.title == track.title, current.artist == track.artist,
           current.service == service, now.timeIntervalSince(current.end) < 90 {
            current.seconds += dt
            sessions[sessions.count - 1] = current
        } else {
            sessions.append(Session(title: track.title, artist: track.artist, service: service,
                                    start: now.addingTimeInterval(-dt), seconds: dt))
        }

        // Volume only means something when the Mac's sound goes to the headphones.
        if let output = SystemVolume.currentOutput(), let name = headphonesName,
           output.name.localizedCaseInsensitiveContains(name) || name.localizedCaseInsensitiveContains(output.name) {
            addVolume(output.level, seconds: dt, at: now)
        }
        scheduleSave()
    }

    private func addVolume(_ level: Double, seconds: Double, at date: Date) {
        let minute = Calendar.current.dateInterval(of: .minute, for: date)?.start ?? date
        if var last = volume.last, last.minute == minute {
            last.level = (last.level * last.seconds + level * seconds) / (last.seconds + seconds)
            last.seconds += seconds
            volume[volume.count - 1] = last
        } else {
            volume.append(VolumeMinute(minute: minute, level: level, seconds: seconds))
        }
    }

    // MARK: Persistence

    private struct Stored: Codable {
        var sessions: [Session]
        var volume: [VolumeMinute]
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.url),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        let cutoff = Date.now.addingTimeInterval(-Self.retention)
        sessions = stored.sessions.filter { $0.start > cutoff }
        volume = stored.volume.filter { $0.minute > cutoff }
    }

    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.saveScheduled = false
            self?.save()
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(Stored(sessions: sessions, volume: volume)) else { return }
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.url, options: .atomic)
    }

    func clear() {
        sessions = []
        volume = []
        save()
    }

    #if PREVIEW
    func setPreview(sessions: [Session], volume: [VolumeMinute]) {
        self.sessions = sessions
        self.volume = volume
    }
    #endif
}

/// The Mac's default output device and its volume, via Core Audio.
enum SystemVolume {
    struct Output {
        let name: String
        let level: Double
    }

    static func currentOutput() -> Output? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else {
            return nil
        }

        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioObjectPropertyName
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
              let deviceName = name?.takeRetainedValue() as String? else { return nil }

        var volume = Float32(0)
        size = UInt32(MemoryLayout<Float32>.size)
        address = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                             mScope: kAudioDevicePropertyScopeOutput,
                                             mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else { return nil }
        return Output(name: deviceName, level: Double(volume))
    }
}
