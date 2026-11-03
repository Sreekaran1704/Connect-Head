import SwiftUI

/// Only settings the headphones reported are shown, so unsupported ones stay hidden.
struct SettingsPage: View {
    @EnvironmentObject private var hp: HeadphoneController
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var confirmPowerOff = false
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Settings", subtitle: "Headphone and app preferences")

            Card(title: "Audio", systemImage: "waveform") {
                toggle("DSEE upsampling", "Restores detail lost in compressed music", hp.state.dseeUpsampling, hp.setDseeUpsampling)
                toggle("Prioritize sound quality", "Prefer LDAC over a more stable connection", hp.state.preferSoundQuality, hp.setPreferSoundQuality)
            }

            Card(title: "Connection", systemImage: "antenna.radiowaves.left.and.right") {
                toggle("Connect to 2 devices", "Stay connected to a phone and a computer at once", hp.state.multipoint, hp.setMultipoint)
                toggle("Capture voice during calls", "Picks up your voice more clearly on calls", hp.state.captureVoiceDuringCall, hp.setCaptureVoiceDuringCall)
            }

            Card(title: "Headphones", systemImage: "headphones") {
                if let v = hp.state.autoPowerOff {
                    SettingRow(title: "Auto power off") {
                        Picker("", selection: Binding(get: { v }, set: { hp.setAutoPowerOff($0) })) {
                            ForEach(AutoPowerOff.allCases) { Text($0.name).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                    }
                }
                if let v = hp.state.voiceAssistant {
                    SettingRow(title: "Voice assistant") {
                        Picker("", selection: Binding(get: { v }, set: { hp.setVoiceAssistant($0) })) {
                            ForEach(VoiceAssistant.allCases) { Text($0.name).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                    }
                }
                toggle("Pause when taken off", nil, hp.state.pauseWhenTakenOff, hp.setPauseWhenTakenOff)
                toggle("Voice guidance", "Spoken prompts for power, modes and battery", hp.state.voiceGuidance, hp.setVoiceGuidance)
                if let vol = hp.state.voiceGuidanceVolume, hp.state.voiceGuidance == true {
                    SettingRow(title: "Guidance volume") {
                        Stepper("\(vol > 0 ? "+" : "")\(vol)",
                                value: Binding(get: { vol }, set: { hp.setVoiceGuidanceVolume($0) }), in: -2...2)
                    }
                }
                SettingRow(title: "Power off headphones") {
                    Button("Power Off…", role: .destructive) { confirmPowerOff = true }
                }
            }

            Card(title: "App", systemImage: "app.badge") {
                SettingRow(title: "Launch at login", detail: "Starts quietly in the menu bar") {
                    Toggle("", isOn: Binding(get: { launchAtLogin },
                                             set: { LoginItem.set($0); launchAtLogin = LoginItem.isEnabled }))
                        .toggleStyle(PrintToggleStyle()).labelsHidden()
                }
                SettingRow(title: "Show in menu bar", detail: "Battery and quick controls in the menu bar") {
                    Toggle("", isOn: $showMenuBarIcon).toggleStyle(PrintToggleStyle()).labelsHidden()
                }
                SettingRow(title: "Listening history", detail: "Kept on this Mac for 120 days, for the Listening page") {
                    Button("Clear History…") { confirmClear = true }
                }
            }

        }
        .confirmationDialog("Clear your listening history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { ListeningLog.shared.clear() }
        }
        .confirmationDialog("Power off \(hp.deviceName ?? "the headphones")?", isPresented: $confirmPowerOff) {
            Button("Power Off", role: .destructive) { hp.powerOff() }
        }
    }

    @ViewBuilder
    private func toggle(_ title: String, _ detail: String?, _ value: Bool?, _ set: @escaping (Bool) -> Void) -> some View {
        if let value {
            SettingRow(title: title, detail: detail) {
                Toggle("", isOn: Binding(get: { value }, set: set)).toggleStyle(PrintToggleStyle()).labelsHidden()
            }
        }
    }
}
