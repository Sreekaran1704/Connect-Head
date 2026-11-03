import SwiftUI

struct OverviewPage: View {
    @EnvironmentObject private var hp: HeadphoneController
    @Binding var page: Page?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Masthead()
            BatteryHero()
            NowPlayingCard()

            Card(title: "Sound mode") {
                HStack(spacing: 12) {
                    ForEach(NoiseMode.allCases) { NoiseModeCard(mode: $0, compact: true) }
                }
                .fixedSize(horizontal: false, vertical: true)
                Text("Tip: press ⌃⌥N anywhere to cycle modes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 22) {
                devices
                Card(title: "Equalizer") {
                    // Preset name doubles as a preset picker.
                    Menu {
                        ForEach(EqPreset.allCases) { preset in
                            Button { hp.setEqPreset(preset) } label: {
                                if preset == hp.state.eqPreset { Label(preset.name, systemImage: "checkmark") } else { Text(preset.name) }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(hp.state.eqPreset?.name ?? "Unknown").font(.headline(19, weight: .medium))
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(Theme.ink)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    EditableEqCurve()
                        .frame(height: 96)
                    HStack {
                        Text("Drag a point to shape the sound.")
                            .font(.headline(11.5, weight: .regular)).italic().foregroundStyle(.secondary)
                        Spacer()
                        Button("More") { page = .equalizer }.buttonStyle(.link)
                    }
                }
            }
        }
    }

    /// The devices the headphones are connected to, set as a short list.
    private var devices: some View {
        let connected = hp.state.devices?.filter(\.connected) ?? []
        return Card(title: "Devices") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(connected) { device in
                    let playing = device.address == hp.state.playbackDevice
                    HStack(spacing: 14) {
                        Image(systemName: device.symbol)
                            .font(.system(size: 16))
                            .frame(width: 34, height: 34)
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.ink.opacity(0.35), lineWidth: 1))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(device.name).font(.headline(15, weight: .medium)).lineLimit(1)
                            Text(playing ? "Now playing" : "Connected")
                                .font(.headline(12, weight: .regular)).italic()
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if playing { Circle().fill(Theme.accent).frame(width: 6, height: 6) }
                    }
                    .padding(.vertical, 8)
                    if device.id != connected.last?.id { Rule().opacity(0.3) }
                }
                if connected.isEmpty {
                    Text("No devices connected").foregroundStyle(.secondary).padding(.vertical, 8)
                }
                Button("Manage devices") { page = .devices }
                    .buttonStyle(.link)
                    .padding(.top, 8)
            }
        }
    }
}

/// Three swatches for the ULT WEAR finishes.
struct ColorwayPicker: View {
    @Binding var selection: Colorway

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Colorway.allCases) { c in
                Button { withAnimation(.easeOut(duration: 0.2)) { selection = c } } label: {
                    Circle()
                        .fill(Color(nsColor: c.swatch))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                        .padding(3)
                        .overlay(Circle().strokeBorder(selection == c ? Color.accentColor : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .help(c.rawValue)
            }
        }
    }
}
