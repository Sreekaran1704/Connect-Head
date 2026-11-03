import Foundation

/// User-facing actions: update local state optimistically, then tell the headphones.
/// The device echoes a notification afterwards, which corrects state if it disagreed.
extension HeadphoneController {
    func setNoiseMode(_ mode: NoiseMode) {
        state.noiseMode = mode
        sendAmbient()
    }

    func setAmbientLevel(_ level: Int) {
        state.ambientLevel = level
        sendAmbient()
    }

    func setFocusOnVoice(_ on: Bool) {
        state.focusOnVoice = on
        sendAmbient()
    }

    private func sendAmbient() {
        send(Commands.ambientSound(mode: state.noiseMode ?? .noiseCancelling,
                                   focusOnVoice: state.focusOnVoice,
                                   level: state.ambientLevel))
    }

    func setNcButtonMode(_ mode: NcButtonMode) {
        state.ncButtonMode = mode
        send(Commands.ncButtonMode(mode))
    }

    func setEqPreset(_ preset: EqPreset) {
        state.eqPreset = preset
        send(Commands.eqPreset(preset, extraByte: state.eqHasExtraByte))
        send(Request([0x56, 0x00])) // re-read the bands that preset implies
    }

    /// Band index 0 is Clear Bass, 1…5 are 400 Hz … 16 kHz.
    func setEqBand(_ index: Int, to value: Int) {
        if index == 0 { state.clearBass = value } else { state.eqBands[index - 1] = value }
        state.eqPreset = .manual
        send(Commands.eqBands(clearBass: state.clearBass, bands: state.eqBands, extraByte: state.eqHasExtraByte))
    }

    func resetEq() {
        state.clearBass = 0
        state.eqBands = [0, 0, 0, 0, 0]
        state.eqPreset = .manual
        send(Commands.eqBands(clearBass: 0, bands: state.eqBands, extraByte: state.eqHasExtraByte))
    }

    func setAutoPowerOff(_ value: AutoPowerOff) {
        state.autoPowerOff = value
        send(Commands.autoPowerOff(value))
    }

    func setPauseWhenTakenOff(_ on: Bool) {
        state.pauseWhenTakenOff = on
        send(Commands.pauseWhenTakenOff(on))
    }

    func setVoiceGuidance(_ on: Bool) {
        state.voiceGuidance = on
        send(Commands.voiceGuidance(on))
    }

    func setVoiceGuidanceVolume(_ v: Int) {
        state.voiceGuidanceVolume = v
        send(Commands.voiceGuidanceVolume(v))
    }

    func setVoiceAssistant(_ va: VoiceAssistant) {
        state.voiceAssistant = va
        send(Commands.voiceAssistant(va))
    }

    func setDseeUpsampling(_ on: Bool) {
        state.dseeUpsampling = on
        send(Commands.dseeUpsampling(on))
    }

    func setPreferSoundQuality(_ on: Bool) {
        state.preferSoundQuality = on
        send(Commands.preferSoundQuality(on))
    }

    func setMultipoint(_ on: Bool) {
        state.multipoint = on
        send(Commands.multipoint(on))
    }

    func setCaptureVoiceDuringCall(_ on: Bool) {
        state.captureVoiceDuringCall = on
        send(Commands.captureVoiceDuringCall(on))
    }

    func powerOff() {
        send(Commands.powerOff)
    }
}

extension HeadphoneController {
    func connectDevice(_ device: SourceDevice) {
        send(Commands.connectDevice(device.address))
    }

    func disconnectDevice(_ device: SourceDevice) {
        send(Commands.disconnectDevice(device.address))
    }

    func playFrom(_ device: SourceDevice) {
        state.playbackDevice = device.address
        send(Commands.playFrom(device.address))
    }

    func refreshDevices() {
        send(Commands.deviceList)
    }
}

extension HeadphoneController {
    /// Bound to the global hotkey: NC → Ambient → Off → NC, with an on-screen badge.
    func cycleNoiseMode() {
        guard status == .connected, let current = state.noiseMode else {
            HUD.show("Headphones not connected", symbol: "headphones.slash")
            return
        }
        let order: [NoiseMode] = [.noiseCancelling, .ambient, .off]
        let next = order[(order.firstIndex(of: current)! + 1) % order.count]
        setNoiseMode(next)
        HUD.show(next.rawValue, symbol: next.symbol)
    }
}
