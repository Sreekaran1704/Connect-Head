import SwiftUI

/// Only shows settings the headphones actually reported, so unsupported ones stay hidden.
struct SettingsView: View {
    @EnvironmentObject private var hp: HeadphoneController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let v = hp.state.autoPowerOff {
                    Picker("Auto power off", selection: Binding(get: { v }, set: { hp.setAutoPowerOff($0) })) {
                        ForEach(AutoPowerOff.allCases) { Text($0.name).tag($0) }
                    }
                }
                if let v = hp.state.voiceAssistant {
                    Picker("Voice assistant", selection: Binding(get: { v }, set: { hp.setVoiceAssistant($0) })) {
                        ForEach(VoiceAssistant.allCases) { Text($0.name).tag($0) }
                    }
                }

                section("Audio")
                toggle("DSEE upsampling", hp.state.dseeUpsampling, hp.setDseeUpsampling)
                toggle("Prioritize sound quality (LDAC)", hp.state.preferSoundQuality, hp.setPreferSoundQuality)

                section("Connection")
                toggle("Connect to 2 devices", hp.state.multipoint, hp.setMultipoint)
                toggle("Capture voice during call", hp.state.captureVoiceDuringCall, hp.setCaptureVoiceDuringCall)

                section("Behaviour")
                toggle("Pause when taken off", hp.state.pauseWhenTakenOff, hp.setPauseWhenTakenOff)
                toggle("Voice guidance", hp.state.voiceGuidance, hp.setVoiceGuidance)
                if let vol = hp.state.voiceGuidanceVolume, hp.state.voiceGuidance == true {
                    Stepper("Guidance volume: \(vol > 0 ? "+" : "")\(vol)",
                            value: Binding(get: { vol }, set: { hp.setVoiceGuidanceVolume($0) }),
                            in: -2...2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 320)
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    @ViewBuilder
    private func toggle(_ title: String, _ value: Bool?, _ set: @escaping (Bool) -> Void) -> some View {
        if let value {
            Toggle(title, isOn: Binding(get: { value }, set: set))
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}
