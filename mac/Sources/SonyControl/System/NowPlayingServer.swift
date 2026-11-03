import AppKit
import Network
import os

/// Shares this Mac's Now Playing with Connect Head on the phone, over the local network:
/// advertised with Bonjour as `_connecthead._tcp`, plain HTTP with two endpoints:
///   GET  /now-playing              → JSON (title, artist, album, service, playing, position, duration, artwork)
///   POST /control?action=playpause|next|previous|handback  (handback: the phone released the controls)
///   GET  /headphones               → the headphones' state, as this Mac reads it
///   POST /send?type=0c&p=68170101…  → relays a raw request to the headphones
/// The headphones allow one control link, so while this Mac holds it, the phone app controls
/// them through these two endpoints instead of taking the link.
/// Requests must carry `X-Headphones: <the headphones' Bluetooth address>`. Only devices paired
/// with the same headphones know it, so others on the network can't read or control playback.
@MainActor
final class NowPlayingServer {
    static let shared = NowPlayingServer()

    /// Returns the connected headphones' address (AA:BB:…), or nil when none is connected.
    var headphonesAddress: () -> String? = { nil }
    /// Called when the phone app hands the headphone controls back (it was closed or left).
    var onHandBack: () -> Void = {}
    weak var controller: HeadphoneController?

    private var listener: NWListener?
    private let log = Logger(subsystem: "local.sonycontrol", category: "share")

    func start() {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(name: Host.current().localizedName ?? "Mac", type: "_connecthead._tcp")
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.serve(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.log.info("now-playing share: \(String(describing: state), privacy: .public)") }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            log.error("couldn't start now-playing share: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: HTTP

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            Task { @MainActor in
                guard let self, let data, let request = String(data: data, encoding: .utf8) else { connection.cancel(); return }
                let (status, body) = self.respond(to: request)
                let head = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }

    private func respond(to request: String) -> (String, Data) {
        let lines = request.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2 else { return ("400 Bad Request", Data("{}".utf8)) }
        let method = String(parts[0]), target = String(parts[1])

        let header = lines.dropFirst().first { $0.lowercased().hasPrefix("x-headphones:") }
        let sent = header.map { String($0.dropFirst("x-headphones:".count)).trimmingCharacters(in: .whitespaces).uppercased() }
        guard let expected = headphonesAddress(), let sent, sent == expected else {
            return ("403 Forbidden", Data("{}".utf8))
        }

        if method == "GET", target.hasPrefix("/headphones") {
            return ("200 OK", headphonesJSON())
        }
        if method == "POST", target.hasPrefix("/send") {
            let items = URLComponents(string: target)?.queryItems ?? []
            let hex = items.first { $0.name == "p" }?.value ?? ""
            let bytes = stride(from: 0, to: hex.count - 1, by: 2).compactMap { i -> UInt8? in
                let start = hex.index(hex.startIndex, offsetBy: i)
                return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)
            }
            guard let typeCode = items.first(where: { $0.name == "type" })?.value.flatMap({ UInt8($0, radix: 16) }),
                  let type = MessageType(rawValue: typeCode), !bytes.isEmpty,
                  let controller, controller.status == .connected else {
                return ("409 Conflict", Data("{}".utf8))
            }
            controller.send(Request(type, bytes))
            return ("200 OK", Data("{}".utf8))
        }

        let player = NowPlaying.shared
        if method == "GET", target.hasPrefix("/now-playing") {
            return ("200 OK", json(for: player.track, artwork: player.artwork))
        }
        if method == "POST", target.hasPrefix("/control") {
            let action = URLComponents(string: target)?.queryItems?.first { $0.name == "action" }?.value
            switch action {
            case "playpause": player.playPause()
            case "next": player.next()
            case "previous": player.previous()
            case "handback": onHandBack()
            default: return ("400 Bad Request", Data("{}".utf8))
            }
            return ("200 OK", Data("{}".utf8))
        }
        return ("404 Not Found", Data("{}".utf8))
    }

    private func headphonesJSON() -> Data {
        guard let hp = controller, hp.status == .connected, hp.loaded else { return Data(#"{"connected":false}"#.utf8) }
        let s = hp.state
        var state: [String: Any] = [
            "charging": s.charging, "focusOnVoice": s.focusOnVoice, "ambientLevel": s.ambientLevel,
            "clearBass": s.clearBass, "eqBands": s.eqBands, "eqHasExtraByte": s.eqHasExtraByte,
        ]
        state["firmware"] = s.firmware
        state["codec"] = s.codec?.rawValue
        state["battery"] = s.battery
        state["noiseMode"] = s.noiseMode.map { ["Noise Cancelling": "NOISE_CANCELLING", "Ambient Sound": "AMBIENT", "Off": "OFF"][$0.rawValue] ?? "OFF" }
        state["ncButtonMode"] = s.ncButtonMode?.rawValue
        state["eqPreset"] = s.eqPreset?.rawValue
        state["pauseWhenTakenOff"] = s.pauseWhenTakenOff
        state["voiceGuidance"] = s.voiceGuidance
        state["voiceGuidanceVolume"] = s.voiceGuidanceVolume
        state["voiceAssistant"] = s.voiceAssistant?.rawValue
        state["dseeUpsampling"] = s.dseeUpsampling
        state["preferSoundQuality"] = s.preferSoundQuality
        state["multipoint"] = s.multipoint
        state["captureVoiceDuringCall"] = s.captureVoiceDuringCall
        state["playbackDevice"] = s.playbackDevice
        state["devices"] = s.devices?.map { ["address": $0.address, "name": $0.name, "slot": Int($0.slot), "cod": Int($0.classOfDevice)] }
        let body: [String: Any] = ["connected": true, "deviceName": hp.deviceName ?? "Headphones",
                                   "host": Host.current().localizedName ?? "Mac", "state": state]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
    }

    private func json(for track: NowPlaying.Track?, artwork: NSImage?) -> Data {
        guard let track else { return Data(#"{"track":null}"#.utf8) }
        var info: [String: Any] = [
            "title": track.title, "artist": track.artist, "album": track.album,
            "service": track.service, "playing": track.playing,
            "position": track.position, "duration": track.duration, "controllable": track.controllable,
            "device": Host.current().localizedName ?? "Mac",
        ]
        if let jpeg = artwork.flatMap(Self.thumbnail) { info["artwork"] = jpeg.base64EncodedString() }
        return (try? JSONSerialization.data(withJSONObject: ["track": info])) ?? Data("{}".utf8)
    }

    /// Small JPEG of the artwork for the phone (keeps each poll light).
    private static func thumbnail(_ image: NSImage) -> Data? {
        let side: CGFloat = 200
        let thumb = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            image.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
            return true
        }
        guard let tiff = thumb.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.75])
    }
}
