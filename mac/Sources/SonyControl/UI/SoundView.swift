import SwiftUI

struct SoundView: View {
    @EnvironmentObject private var hp: HeadphoneController
    @State private var draftLevel: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach(NoiseMode.allCases) { ModeButton(mode: $0) }
            }

            if hp.state.noiseMode == .ambient {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Ambient level")
                        Spacer()
                        Text("\(Int(draftLevel ?? Double(hp.state.ambientLevel)))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    // Only send on release, so dragging doesn't flood the headphones.
                    Slider(
                        value: Binding(
                            get: { draftLevel ?? Double(hp.state.ambientLevel) },
                            set: { draftLevel = $0 }),
                        in: 1...20, step: 1
                    ) { editing in
                        if !editing, let level = draftLevel {
                            hp.setAmbientLevel(Int(level))
                            draftLevel = nil
                        }
                    }
                    Toggle("Focus on voice", isOn: Binding(
                        get: { hp.state.focusOnVoice },
                        set: { hp.setFocusOnVoice($0) }))
                }
            }

            Text("Shortcut: ⌃⌥N cycles modes from anywhere")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let mode = hp.state.ncButtonMode {
                Picker("NC/AMB button", selection: Binding(get: { mode }, set: { hp.setNcButtonMode($0) })) {
                    ForEach(NcButtonMode.allCases) { Text($0.name).tag($0) }
                }
            }
        }
    }
}

private struct ModeButton: View {
    @EnvironmentObject private var hp: HeadphoneController
    let mode: NoiseMode

    var body: some View {
        let selected = hp.state.noiseMode == mode
        Button { hp.setNoiseMode(mode) } label: {
            VStack(spacing: 6) {
                Image(systemName: mode.symbol).font(.title2)
                Text(mode.rawValue).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(selected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
