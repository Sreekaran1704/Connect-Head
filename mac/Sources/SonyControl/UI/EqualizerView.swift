import SwiftUI

struct EqualizerView: View {
    @EnvironmentObject private var hp: HeadphoneController

    private let labels = ["Clear\nBass", "400", "1k", "2.5k", "6.3k", "16k"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let preset = hp.state.eqPreset {
                Picker("Preset", selection: Binding(get: { preset }, set: { hp.setEqPreset($0) })) {
                    ForEach(EqPreset.allCases) { Text($0.name).tag($0) }
                }
            }

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<6, id: \.self) { i in
                    BandSlider(label: labels[i], value: value(for: i)) { hp.setEqBand(i, to: $0) }
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 170)

            HStack {
                Text("Moving a band switches to Manual.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Flat") { hp.resetEq() }.controlSize(.small)
            }
        }
    }

    private func value(for index: Int) -> Int {
        index == 0 ? hp.state.clearBass : hp.state.eqBands[index - 1]
    }
}

/// A vertical -10…+10 slider that commits on release.
private struct BandSlider: View {
    let label: String
    let value: Int
    let onCommit: (Int) -> Void

    @State private var draft: Double?

    var body: some View {
        VStack(spacing: 4) {
            Text(String(format: "%+d", Int(draft ?? Double(value))))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(get: { draft ?? Double(value) }, set: { draft = $0 }),
                in: -10...10, step: 1
            ) { editing in
                if !editing, let d = draft {
                    onCommit(Int(d))
                    draft = nil
                }
            }
            .rotationEffect(.degrees(-90))
            .frame(width: 120, height: 24)
            .frame(width: 40, height: 120)
            Text(label)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .frame(height: 24)
        }
    }
}
