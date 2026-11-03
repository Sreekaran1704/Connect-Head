import Foundation
import IOBluetooth
import os

/// Owns the RFCOMM link to the headphones, runs the request/ACK queue, and publishes state.
///
/// IOBluetooth callbacks may arrive on the main thread or a CoreBluetooth queue; the delegate
/// methods funnel everything onto the main actor via `onMain`.
@MainActor
final class HeadphoneController: NSObject, ObservableObject {
    enum Status: Equatable {
        case noDevice
        case disconnected
        case connecting
        case connected
        /// The headphones are on, but another device (Connect Head on the phone) holds the
        /// single control link they allow.
        case inUseElsewhere
        case failed(String)
    }

    /// Starts as `.connecting` so the window doesn't flash "Disconnected" before `start()` runs.
    @Published private(set) var status: Status = .connecting
    /// True once the replies to the initial queries are in. Until then replies collect in
    /// `loadingState` and are published in one go, so the UI appears complete instead of
    /// filling in field by field.
    @Published private(set) var loaded = false
    private var loadingState = HeadphoneState()
    private var loadTimer: Timer?
    @Published private(set) var deviceName: String?
    @Published private(set) var pairedDevices: [IOBluetoothDevice] = []
    @Published var state = HeadphoneState() {
        didSet {
            if state.battery != oldValue.battery || state.charging != oldValue.charging {
                batteryAlerts.update(level: state.battery, charging: state.charging, deviceName: deviceName)
            }
        }
    }
    private let batteryAlerts = BatteryAlerts()
    private var hotKey: HotKey?

    /// This Mac's Bluetooth address, formatted like the headphones report it (AA:BB:…).
    @Published private(set) var hostAddress: String?

    private static let serviceUUIDs = [
        "956C7B26-D49A-4BA8-B03F-B17D393CB6E2", // protocol v2
        "96CC203E-5068-46AD-B32D-E316F5E069BA", // protocol v1
    ]
    private static let selectedAddressKey = "selectedDeviceAddress"
    private let log = Logger(subsystem: "local.sonycontrol", category: "bt")

    private var device: IOBluetoothDevice?
    private var closingOnPurpose = false

    /// The headphones' Bluetooth address (AA:BB:…). Phones paired with the same headphones know
    /// it too, which is what lets the phone app read this Mac's Now Playing.
    /// Known whether or not the control link is up (the headphones allow one control link at
    /// a time, so the phone app may be holding it).
    var headphonesAddress: String? {
        (device ?? preferredDevice())?.addressString?.replacingOccurrences(of: "-", with: ":").uppercased()
    }
    private var channel: IOBluetoothRFCOMMChannel?
    private var parser = FrameParser()

    private var seq: UInt8 = 0
    private var queue: [Request] = []
    private var awaitingAck = false
    private var gotInitReply = false
    private var ackTimer: Timer?
    private var initTimer: Timer?
    private var sdpTimer: Timer?
    private var batteryTimer: Timer?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotification: IOBluetoothUserNotification?

    override init() {
        super.init()
        hotKey = HotKey { [weak self] in
            MainActor.assumeIsolated { self?.cycleNoiseMode() }
        }

        // Protocol probing: `scripts/send.swift 0c 66 17` posts a raw request to the running app.
        DistributedNotificationCenter.default().addObserver(
            forName: .init("local.sonycontrol.send"), object: nil, queue: .main
        ) { [weak self] note in
            let hex = (note.object as? String ?? "").split(separator: " ").compactMap { UInt8($0, radix: 16) }
            guard hex.count >= 2, let type = MessageType(rawValue: hex[0]) else { return }
            MainActor.assumeIsolated { self?.send(Request(type, Array(hex.dropFirst()))) }
        }
    }

    /// Starts Bluetooth. Kept out of `init` because the first IOBluetooth call blocks the main
    /// thread until the user answers the Bluetooth permission prompt, so the UI must be up first.
    func start() {
        guard connectNotification == nil else { return }
        hostAddress = IOBluetoothHostController.default()?.addressAsString()?
            .replacingOccurrences(of: "-", with: ":").uppercased()
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(deviceDidConnect(_:device:)))
        refreshPairedDevices()
        connect()
    }

    #if PREVIEW
    /// Used by scripts/preview.swift to render the UI with sample data and no Bluetooth.
    func setPreview(name: String, host: String) {
        status = .connected
        loaded = true
        deviceName = name
        hostAddress = host
    }
    #endif

    // MARK: Device selection

    func refreshPairedDevices() {
        let all = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        pairedDevices = all.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    func select(_ device: IOBluetoothDevice) {
        UserDefaults.standard.set(device.addressString, forKey: Self.selectedAddressKey)
        disconnect()
        connect()
    }

    private func preferredDevice() -> IOBluetoothDevice? {
        if let saved = UserDefaults.standard.string(forKey: Self.selectedAddressKey),
           let match = pairedDevices.first(where: { $0.addressString == saved }) {
            return match
        }
        return pairedDevices.first { device in
            let name = (device.name ?? "").uppercased()
            return ["ULT", "WH-", "WF-", "SONY"].contains { name.contains($0) }
        }
    }

    // MARK: Connection

    func connect() {
        // (`device` is nil only before the first attempt, while status already reads connecting.)
        guard channel == nil, device == nil || status != .connecting else { return }
        refreshPairedDevices()
        log.info("paired devices: \(self.pairedDevices.map { $0.name ?? "?" }.joined(separator: ", "), privacy: .public)")
        guard let device = preferredDevice() else {
            status = .noDevice
            return
        }
        self.device = device
        deviceName = device.name
        status = .connecting
        log.info("connecting to \(device.name ?? "?", privacy: .public), linked=\(device.isConnected(), privacy: .public)")

        if !device.isConnected() {
            // Bring up the baseband link (also makes macOS route audio to the headphones).
            let result = device.openConnection()
            guard result == kIOReturnSuccess else {
                status = .failed("Headphones not reachable. Turn them on and try again.")
                return
            }
        }
        let services = (device.services as? [IOBluetoothSDPServiceRecord]) ?? []
        log.info("cached services: \(services.compactMap { $0.getServiceName() }.joined(separator: ", "), privacy: .public)")

        // Use the cached SDP records when they already list the Sony service.
        if controlChannelID() != nil {
            openChannel()
            return
        }
        // Otherwise refresh them. The completion callback doesn't always arrive, so fall back
        // to trying again after a few seconds.
        let uuids = Self.serviceUUIDs.compactMap(Self.sdpUUID)
        let sdp = device.performSDPQuery(self, uuids: uuids)
        log.info("SDP query started: \(sdp, privacy: .public)")
        if sdp != kIOReturnSuccess {
            openChannel()
            return
        }
        sdpTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.channel == nil, self.status == .connecting else { return }
                self.log.warning("SDP callback timed out; trying cached records")
                self.openChannel()
            }
        }
    }

    private func controlChannelID() -> BluetoothRFCOMMChannelID? {
        guard let device else { return nil }
        for uuidString in Self.serviceUUIDs {
            var channelID: BluetoothRFCOMMChannelID = 0
            if let uuid = Self.sdpUUID(uuidString),
               let record = device.getServiceRecord(for: uuid),
               record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess {
                return channelID
            }
        }
        return nil
    }

    func disconnect() {
        closingOnPurpose = true
        channel?.close()
        resetLink()
        status = .disconnected
    }

    private func openChannel() {
        sdpTimer?.invalidate()
        guard let device, channel == nil else { return }
        let channelID = controlChannelID()
        log.info("control service channel: \(channelID.map(String.init) ?? "none", privacy: .public)")
        guard let channelID else {
            status = .failed("This device doesn't expose the Sony control service.")
            return
        }
        var newChannel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&newChannel, withChannelID: channelID, delegate: self)
        log.info("RFCOMM open requested: \(result, privacy: .public)")
        guard result == kIOReturnSuccess, let newChannel else {
            status = .failed("Couldn't open the control channel (\(String(format: "0x%08x", result))).")
            return
        }
        channel = newChannel
    }

    private func channelOpened() {
        log.info("RFCOMM channel open")
        status = .connected
        disconnectNotification = device?.register(
            forDisconnectNotification: self, selector: #selector(deviceDidDisconnect(_:device:)))
        sendInit(attempt: 0)
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.send(Commands.battery)
                self?.send(Commands.codec)
            }
        }
    }

    private func resetLink() {
        channel = nil
        parser = FrameParser()
        seq = 0
        queue.removeAll()
        awaitingAck = false
        gotInitReply = false
        [ackTimer, initTimer, batteryTimer, loadTimer].forEach { $0?.invalidate() }
        loaded = false
        loadingState = HeadphoneState()
        disconnectNotification?.unregister()
        disconnectNotification = nil
    }

    /// The headphones sometimes ignore the first init, so retry a couple of times.
    private func sendInit(attempt: Int) {
        write(Frame(type: .command1, seq: seq, payload: Commands.initialize.payload))
        awaitingAck = true
        initTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.gotInitReply, self.channel != nil else { return }
                if attempt < 3 {
                    self.sendInit(attempt: attempt + 1)
                } else {
                    self.status = .failed("Headphones didn't answer. Close the Sony app on your phone and retry.")
                }
            }
        }
    }

    // MARK: Request queue

    func send(_ request: Request) {
        queue.append(request)
        pump()
    }

    func send(_ requests: [Request]) {
        queue += requests
        pump()
    }

    /// Sends the next request once the previous one has been ACKed.
    private func pump() {
        guard channel != nil, gotInitReply, !awaitingAck, !queue.isEmpty else { return }
        let request = queue.removeFirst()
        write(Frame(type: request.type, seq: seq, payload: request.payload))
        awaitingAck = true
        ackTimer?.invalidate()
        ackTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.log.warning("ACK timeout, moving on")
                self?.awaitingAck = false
                self?.pump()
            }
        }
    }

    private func write(_ frame: Frame) {
        guard let channel else { return }
        var bytes = frame.encode()
        log.debug("→ \(Self.hex(bytes), privacy: .public)")
        let result = bytes.withUnsafeMutableBytes {
            channel.writeSync($0.baseAddress, length: UInt16($0.count))
        }
        if result != kIOReturnSuccess {
            log.error("write failed: \(result)")
        }
    }

    private func handle(_ frame: Frame) {
        log.debug("← \(String(describing: frame.type), privacy: .public) seq=\(frame.seq, privacy: .public) \(Self.hex(frame.payload), privacy: .public)")
        switch frame.type {
        case .ack:
            seq = frame.seq
            awaitingAck = false
            ackTimer?.invalidate()
            pump()
            if !loaded, gotInitReply, queue.isEmpty, !awaitingAck {
                // Last initial query ACKed; its reply follows right behind.
                loadTimer?.invalidate()
                loadTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.finishLoading() }
                }
            }

        case .command1, .command2:
            write(Frame(type: .ack, seq: 1 &- frame.seq, payload: []))
            if frame.type == .command1, frame.payload.first == 0x01, !gotInitReply {
                gotInitReply = true
                initTimer?.invalidate()
                send(Commands.initialQueries)
                // Show whatever has arrived if some query never gets an answer.
                loadTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.finishLoading() }
                }
            } else if frame.type == .command2, frame.payload.first == 0x3d {
                // A device connected/disconnected/unpaired: refresh the list.
                send(Commands.deviceList)
            } else if !(loaded ? state.apply(frame.type, frame.payload) : loadingState.apply(frame.type, frame.payload)) {
                log.info("unhandled payload \(Self.hex(frame.payload), privacy: .public)")
            }
        }
    }

    private func finishLoading() {
        guard !loaded, channel != nil else { return }
        loadTimer?.invalidate()
        state = loadingState
        loaded = true
        log.info("initial state loaded")
    }

    // MARK: Helpers

    private static func sdpUUID(_ string: String) -> IOBluetoothSDPUUID? {
        guard let uuid = UUID(uuidString: string) else { return nil }
        var bytes = uuid.uuid
        return withUnsafeBytes(of: &bytes) { IOBluetoothSDPUUID(bytes: $0.baseAddress, length: 16) }
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}

// MARK: - IOBluetooth callbacks

extension HeadphoneController: IOBluetoothRFCOMMChannelDelegate {
    @objc nonisolated func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        onMain { [self] in
            log.info("SDP query complete: \(status, privacy: .public)")
            openChannel()
        }
    }

    nonisolated func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        onMain { [self] in
            log.info("RFCOMM open complete: \(error, privacy: .public)")
            if error == kIOReturnSuccess {
                channelOpened()
            } else {
                resetLink()
                status = .failed("Couldn't open the control channel (\(String(format: "0x%08x", error))).")
            }
        }
    }

    nonisolated func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let bytes = Array(UnsafeRawBufferPointer(start: dataPointer, count: dataLength))
        onMain { [self] in
            for frame in parser.feed(bytes) { handle(frame) }
        }
    }

    nonisolated func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        onMain { [self] in
            log.info("RFCOMM channel closed")
            resetLink()
            // Closed by the headphones while they're still on: the phone app took the controls.
            let elsewhere = !closingOnPurpose && device?.isConnected() == true
            closingOnPurpose = false
            status = elsewhere ? .inUseElsewhere : .disconnected
        }
    }

    @objc nonisolated func deviceDidConnect(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let address = device.addressString
        onMain { [self] in
            guard channel == nil, address == preferredDevice()?.addressString else { return }
            // Give the audio profiles a moment to settle before opening our channel.
            Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.connect() }
            }
        }
    }

    @objc nonisolated func deviceDidDisconnect(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        onMain { [self] in
            channel = nil
            resetLink()
            status = .disconnected
        }
    }
}

/// IOBluetooth calls back on the main thread for some events but on a CoreBluetooth queue for
/// others (device connect notifications on macOS 27), so hop to the main actor explicitly.
private func onMain(_ body: @escaping @MainActor () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated(body)
    } else {
        DispatchQueue.main.async { MainActor.assumeIsolated(body) }
    }
}
