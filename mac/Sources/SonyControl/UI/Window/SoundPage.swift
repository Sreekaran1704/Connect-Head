import SwiftUI

struct SoundPage: View {
    @EnvironmentObject private var hp: HeadphoneController
    @State private var draftLevel: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Sound", subtitle: "Noise cancelling and ambient sound")

            HStack(spacing: 14) {
                ForEach(NoiseMode.allCases) { NoiseModeCard(mode: $0) }
            }

            Card(title: "Ambient sound", systemImage: "ear") {
                if hp.state.noiseMode == .ambient {
                    let level = draftLevel ?? Double(hp.state.ambientLevel)
                    SettingRow(title: "Level", detail: "How much of your surroundings you hear") {
                        Text("\(Int(level))").font(.title3.monospacedDigit().weight(.semibold))
                    }
                    HStack {
                        Image(systemName: "speaker").foregroundStyle(.secondary)
                        Slider(value: Binding(get: { level }, set: { draftLevel = $0 }), in: 1...20, step: 1) { editing in
                            if !editing, let d = draftLevel {
                                hp.setAmbientLevel(Int(d))
                                draftLevel = nil
                            }
                        }
                        Image(systemName: "speaker.wave.3").foregroundStyle(.secondary)
                    }
                    Divider()
                    SettingRow(title: "Focus on voice", detail: "Lets voices through while reducing other noise") {
                        Toggle("", isOn: Binding(get: { hp.state.focusOnVoice }, set: { hp.setFocusOnVoice($0) }))
                            .toggleStyle(PrintToggleStyle()).labelsHidden()
                    }
                } else {
                    Text("Switch to Ambient Sound to adjust the level and focus on voice.")
                        .foregroundStyle(.secondary)
                }
            }

            Card(title: "Controls", systemImage: "button.programmable") {
                if let mode = hp.state.ncButtonMode {
                    SettingRow(title: "NC/AMB button", detail: "What the button on the headphones cycles through") {
                        Picker("", selection: Binding(get: { mode }, set: { hp.setNcButtonMode($0) })) {
                            ForEach(NcButtonMode.allCases) { Text($0.name).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    Divider()
                }
                SettingRow(title: "Keyboard shortcut", detail: "Cycles Noise Cancelling → Ambient → Off from any app") {
                    Text("⌃⌥N")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.ink.opacity(0.35), lineWidth: 1))
                }
            }
        }
    }
}
