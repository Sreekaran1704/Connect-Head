import Foundation

/// A single command sent to the headphones. Payload byte 0 is the payload type.
struct Request {
    let type: MessageType
    let payload: [UInt8]

    init(_ type: MessageType, _ payload: [UInt8]) {
        self.type = type
        self.payload = payload
    }

    init(_ payload: [UInt8]) {
        self.init(.command1, payload)
    }
}

// MARK: - Setting value types

enum NoiseMode: String, CaseIterable, Identifiable {
    case noiseCancelling = "Noise Cancelling"
    case ambient = "Ambient Sound"
    case off = "Off"
    var id: Self { self }

    var symbol: String {
        switch self {
        case .noiseCancelling: "ear.and.waveform"
        case .ambient: "ear"
        case .off: "speaker.wave.2"
        }
    }
}

enum EqPreset: UInt8, CaseIterable, Identifiable {
    case off = 0x00, bright = 0x10, excited = 0x11, mellow = 0x12, relaxed = 0x13
    case vocal = 0x14, trebleBoost = 0x15, bassBoost = 0x16, speech = 0x17
    case manual = 0xa0, custom1 = 0xa1, custom2 = 0xa2
    var id: Self { self }

    var name: String {
        switch self {
        case .off: "Off"
        case .bright: "Bright"
        case .excited: "Excited"
        case .mellow: "Mellow"
        case .relaxed: "Relaxed"
        case .vocal: "Vocal"
        case .trebleBoost: "Treble Boost"
        case .bassBoost: "Bass Boost"
        case .speech: "Speech"
        case .manual: "Manual"
        case .custom1: "Custom 1"
        case .custom2: "Custom 2"
        }
    }
}

enum AutoPowerOff: CaseIterable, Identifiable {
    case off, after5Min, after30Min, after1Hour, after3Hours, whenTakenOff
    var id: Self { self }

    var code: (UInt8, UInt8) {
        switch self {
        case .off: (0x11, 0x00)
        case .after5Min: (0x00, 0x00)
        case .after30Min: (0x01, 0x01)
        case .after1Hour: (0x02, 0x02)
        case .after3Hours: (0x03, 0x03)
        case .whenTakenOff: (0x10, 0x00)
        }
    }

    var name: String {
        switch self {
        case .off: "Never"
        case .after5Min: "After 5 minutes"
        case .after30Min: "After 30 minutes"
        case .after1Hour: "After 1 hour"
        case .after3Hours: "After 3 hours"
        case .whenTakenOff: "When taken off"
        }
    }

    init?(_ a: UInt8, _ b: UInt8) {
        guard let match = Self.allCases.first(where: { $0.code == (a, b) }) else { return nil }
        self = match
    }
}

/// What the NC/AMBIENT button cycles through.
enum NcButtonMode: UInt8, CaseIterable, Identifiable {
    case ncAmbientOff = 0x01, ncAmbient = 0x02, ncOff = 0x03, ambientOff = 0x04
    var id: Self { self }

    var name: String {
        switch self {
        case .ncAmbientOff: "NC → Ambient → Off"
        case .ncAmbient: "NC ↔ Ambient"
        case .ncOff: "NC ↔ Off"
        case .ambientOff: "Ambient ↔ Off"
        }
    }
}

enum VoiceAssistant: UInt8, CaseIterable, Identifiable {
    case off = 0xff, device = 0x30, google = 0x31, alexa = 0x32
    var id: Self { self }

    var name: String {
        switch self {
        case .off: "Off"
        case .device: "Mac / phone assistant"
        case .google: "Google Assistant"
        case .alexa: "Amazon Alexa"
        }
    }
}

enum AudioCodec: UInt8 {
    case unknown = 0x00, sbc = 0x01, aac = 0x02, ldac = 0x10, aptx = 0x20, aptxHD = 0x21

    var name: String {
        switch self {
        case .unknown: "Unknown"
        case .sbc: "SBC"
        case .aac: "AAC"
        case .ldac: "LDAC"
        case .aptx: "aptX"
        case .aptxHD: "aptX HD"
        }
    }
}

/// A phone/computer the headphones are paired with (from the multipoint device list).
struct SourceDevice: Identifiable, Equatable {
    let address: String
    let name: String
    /// 0 = not connected, otherwise the connection slot (1, 2) the headphones assigned it.
    let slot: UInt8
    let classOfDevice: UInt32

    var connected: Bool { slot != 0 }

    var id: String { address }
    var isPhone: Bool { (classOfDevice >> 8) & 0x1f == 0x02 }
    var symbol: String { isPhone ? "iphone" : "laptopcomputer" }
}

/// Everything we know about the headphones. `nil` means the device hasn't reported it (yet),
/// and the UI hides that control.
struct HeadphoneState {
    var firmware: String?
    var codec: AudioCodec?
    var battery: Int?
    var charging = false

    var noiseMode: NoiseMode?
    var focusOnVoice = false
    var ambientLevel = 10

    var ncButtonMode: NcButtonMode?

    var eqPreset: EqPreset?
    var clearBass = 0
    var eqBands = [0, 0, 0, 0, 0]
    /// The ULT WEAR puts an extra 0x01 after the preset in EQ messages, and expects it back.
    var eqHasExtraByte = false

    var autoPowerOff: AutoPowerOff?
    var pauseWhenTakenOff: Bool?
    var voiceGuidance: Bool?
    var voiceGuidanceVolume: Int?
    var voiceAssistant: VoiceAssistant?
    var dseeUpsampling: Bool?
    var preferSoundQuality: Bool?
    var multipoint: Bool?
    var captureVoiceDuringCall: Bool?

    var devices: [SourceDevice]?
    /// Address of the device currently allowed to play audio.
    var playbackDevice: String?
}

// MARK: - Requests (Sony protocol v2, as used by the WH-ULT900N)

enum Commands {
    static let initialize = Request([0x00, 0x00])

    /// Queried right after the init handshake.
    static let initialQueries: [Request] = [
        Request([0x04, 0x02]),         // firmware version
        Request([0x12, 0x02]),         // audio codec
        Request([0x22, 0x00]),         // battery
        Request([0x66, 0x17]),         // ambient sound control
        Request([0xfa, 0x03]),         // NC/AMB button mode
        Request([0x56, 0x00]),         // equalizer
        Request([0x26, 0x05]),         // auto power off
        Request([0x26, 0x01]),         // pause when taken off
        Request([0xe6, 0x01]),         // DSEE upsampling
        Request([0xe6, 0x02]),         // connection quality (LDAC)
        Request([0xf6, 0x04]),         // voice assistant
        Request([0xd6, 0xd1]),         // multipoint
        Request([0xd6, 0xd3]),         // capture voice during call
        Request(.command2, [0x46, 0x01]), // voice guidance on/off
        Request(.command2, [0x46, 0x20]), // voice guidance volume
        deviceList,
    ]

    static let battery = Request([0x22, 0x00])
    static let codec = Request([0x12, 0x02])

    static func ambientSound(mode: NoiseMode, focusOnVoice: Bool, level: Int) -> Request {
        Request([
            0x68, 0x17, 0x01,
            mode == .off ? 0x00 : 0x01,
            mode == .ambient ? 0x01 : 0x00,
            focusOnVoice ? 0x01 : 0x00,
            UInt8(clamping: level),
        ])
    }

    static func ncButtonMode(_ mode: NcButtonMode) -> Request {
        Request([0xfc, 0x03, 0x01, 0x00, 0x01, 0x00, mode.rawValue])
    }

    static func eqPreset(_ preset: EqPreset, extraByte: Bool) -> Request {
        Request([0x58, 0x00, preset.rawValue] + (extraByte ? [0x01] : []) + [0x00])
    }

    static func eqBands(clearBass: Int, bands: [Int], extraByte: Bool) -> Request {
        Request([0x58, 0x00, 0xa0] + (extraByte ? [0x01] : []) + [0x06]
                + ([clearBass] + bands).map { UInt8(clamping: $0 + 10) })
    }

    static func autoPowerOff(_ value: AutoPowerOff) -> Request {
        Request([0x28, 0x05, value.code.0, value.code.1])
    }

    // Many v2 toggles use 0x00 for "on" and 0x01 for "off".
    static func pauseWhenTakenOff(_ on: Bool) -> Request { Request([0xf8, 0x01, on ? 0x00 : 0x01]) }
    static func dseeUpsampling(_ on: Bool) -> Request { Request([0xe8, 0x01, on ? 0x01 : 0x00]) }
    static func preferSoundQuality(_ on: Bool) -> Request { Request([0xe8, 0x02, on ? 0x00 : 0x01]) }
    static func captureVoiceDuringCall(_ on: Bool) -> Request { Request([0xd8, 0xd3, 0x00, on ? 0x00 : 0x01]) }
    static func voiceGuidance(_ on: Bool) -> Request { Request(.command2, [0x48, 0x01, on ? 0x00 : 0x01]) }
    static func voiceGuidanceVolume(_ v: Int) -> Request { Request(.command2, [0x48, 0x20, UInt8(bitPattern: Int8(clamping: v)), 0x00]) }
    static func voiceAssistant(_ va: VoiceAssistant) -> Request { Request([0xf8, 0x04, va.rawValue]) }

    /// Multipoint is toggled via the 0xd1 touch-sensor slot and then committed.
    static func multipoint(_ on: Bool) -> [Request] {
        [Request([0xd8, 0xd1, 0x00, on ? 0x00 : 0x01]), Request([0x98, 0x00, 0x06, 0x01])]
    }

    static let powerOff = Request([0x24, 0x03, 0x01])

    // Multipoint device management lives in the second command family ("peripheral" commands,
    // as named by mos9527/SonyHeadphonesClient's libmdr). Inquired type 0x02 = with class of device.
    static let deviceList = Request(.command2, [0x36, 0x02])

    static func connectDevice(_ address: String) -> Request {
        Request(.command2, [0x3c, 0x02, 0x01] + Array(address.utf8))
    }

    static func disconnectDevice(_ address: String) -> Request {
        Request(.command2, [0x3c, 0x02, 0x00] + Array(address.utf8))
    }

    /// Hands the audio "playback right" to another connected device.
    static func playFrom(_ address: String) -> Request {
        Request(.command2, [0x3c, 0x01] + Array(address.utf8))
    }
}

// MARK: - Responses

extension HeadphoneState {
    /// Applies a reply or notification from the headphones. Returns false if it wasn't understood.
    @discardableResult
    mutating func apply(_ type: MessageType, _ p: [UInt8]) -> Bool {
        guard let kind = p.first else { return false }

        if type == .command2 {
            if kind == 0x37 || kind == 0x39 {
                return applyDeviceList(p)
            }
            guard (kind == 0x47 || kind == 0x49), p.count >= 3 else { return false }
            switch p[1] {
            case 0x01: voiceGuidance = p[2] == 0x00
            case 0x20: voiceGuidanceVolume = Int(Int8(bitPattern: p[2]))
            default: return false
            }
            return true
        }

        switch kind {
        case 0x05 where p.count >= 3 && p[1] == 0x02:
            let len = Int(p[2])
            guard p.count >= 3 + len else { return false }
            firmware = String(bytes: p[3..<(3 + len)], encoding: .ascii)

        case 0x13, 0x15:
            guard p.count == 3, p[1] == 0x02 else { return false }
            codec = AudioCodec(rawValue: p[2]) ?? .unknown

        case 0x23, 0x25:
            guard p.count >= 4, p[1] == 0x00 else { return false }
            battery = Int(p[2])
            charging = p[3] == 0x01

        case 0x27, 0x29:
            if p.count == 4, p[1] == 0x05 {
                autoPowerOff = AutoPowerOff(p[2], p[3])
            } else if p.count == 3, p[1] == 0x01 {
                pauseWhenTakenOff = p[2] == 0x00
            } else {
                return false
            }

        case 0x57, 0x59:
            // 57 00 <preset> [01 on the ULT WEAR] 06 <clear bass> <5 bands>: the values are always last.
            guard p.count >= 10, p[p.count - 7] == 0x06 else { return false }
            eqPreset = EqPreset(rawValue: p[2])
            eqHasExtraByte = p.count == 11
            let values = p.suffix(6).map { Int($0) - 10 }
            clearBass = values[0]
            eqBands = Array(values.dropFirst())

        case 0x67, 0x69:
            return applyAmbient(p)

        case 0xd7, 0xd9:
            guard p.count == 4 else { return false }
            let on = p[3] == 0x00
            switch p[1] {
            case 0xd1: multipoint = on
            case 0xd3: captureVoiceDuringCall = on
            default: return false
            }

        case 0xe7, 0xe9:
            guard p.count == 3 else { return false }
            switch p[1] {
            case 0x01: dseeUpsampling = p[2] == 0x01
            case 0x02: preferSoundQuality = p[2] == 0x00
            default: return false
            }

        case 0xf7, 0xf9:
            guard p.count >= 3 else { return false }
            switch p[1] {
            case 0x01: pauseWhenTakenOff = p[2] == 0x00
            case 0x04: voiceAssistant = VoiceAssistant(rawValue: p[2])
            default: return false
            }

        case 0xfb, 0xfd:
            guard p.count == 7, p[1] == 0x03 else { return false }
            ncButtonMode = NcButtonMode(rawValue: p[6])

        default:
            return false
        }
        return true
    }

    /// 37/39 02 <count> { <17-byte address> <slot> <class of device, 3 BE> <len> <name> }… <playing slot>
    /// The trailing byte is the connection slot of the device that has the audio, not a list index.
    private mutating func applyDeviceList(_ p: [UInt8]) -> Bool {
        guard p.count >= 3, p[1] == 0x02 else { return false }
        var list: [SourceDevice] = []
        var i = 3
        for _ in 0..<Int(p[2]) {
            guard i + 22 <= p.count else { return false }
            let address = String(decoding: p[i..<(i + 17)], as: UTF8.self)
            let slot = p[i + 17]
            let cod = UInt32(p[i + 18]) << 16 | UInt32(p[i + 19]) << 8 | UInt32(p[i + 20])
            let nameLength = Int(p[i + 21])
            i += 22
            guard i + nameLength <= p.count else { return false }
            let name = String(decoding: p[i..<(i + nameLength)], as: UTF8.self)
            i += nameLength
            list.append(SourceDevice(address: address, name: name, slot: slot, classOfDevice: cod))
        }
        devices = list
        let playingSlot = i < p.count ? p[i] : 0
        playbackDevice = playingSlot == 0 ? nil : list.first { $0.slot == playingSlot }?.address
        return true
    }

    private mutating func applyAmbient(_ p: [UInt8]) -> Bool {
        guard (6...8).contains(p.count), [0x15, 0x17, 0x22].contains(p[1]) else { return false }
        let hasWindMode = p[1] == 0x17 && p.count > 7
        if p[3] == 0x00 {
            noiseMode = .off
        } else if p[1] == 0x22 {
            noiseMode = .ambient
        } else if hasWindMode && p[5] != 0x02 {
            noiseMode = .noiseCancelling // wind noise reduction; treat as NC
        } else {
            noiseMode = p[4] == 0x01 ? .ambient : .noiseCancelling
        }
        focusOnVoice = p[p.count - 2] == 0x01
        ambientLevel = Int(p[p.count - 1])
        return true
    }
}
