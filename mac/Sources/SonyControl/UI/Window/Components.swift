import SwiftUI

/// Editorial typography, after newspaper layouts: serif (New York) headlines and figures,
/// small tracked uppercase sans for labels.
extension Font {
    static func headline(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

extension Text {
    /// Small uppercase section label ("BATTERY", "2 DEVICES CONNECTED").
    func sectionLabel() -> some View {
        self.font(.system(size: 11, weight: .semibold)).tracking(1.6).textCase(.uppercase).foregroundStyle(.secondary)
    }
}

/// A print panel grouping content on the window's pages: a small kicker over a hairline
/// rule, then the content.
struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.system(size: 11, weight: .semibold)).tracking(1.6).textCase(.uppercase)
                    Rule()
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .printPanel()
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline(30, weight: .medium))
            Text(subtitle).font(.headline(14, weight: .regular)).italic().foregroundStyle(.secondary)
            Rule(double: true).padding(.top, 6)
        }
        .padding(.bottom, 4)
    }
}

/// Circular battery gauge.
struct BatteryRing: View {
    let level: Int
    let charging: Bool
    var size: CGFloat = 120

    private var color: Color {
        if charging { return .green }
        switch level {
        case ..<16: return .red
        case ..<31: return .orange
        default: return .accentColor
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: size * 0.09)
            Circle()
                .trim(from: 0, to: CGFloat(level) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: level)
            VStack(spacing: 0) {
                Text("\(level)%")
                    .font(.system(size: size * 0.24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Label(charging ? "Charging" : "Battery", systemImage: charging ? "bolt.fill" : "battery.75")
                    .font(.system(size: size * 0.09))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Large selectable card for a noise mode.
struct NoiseModeCard: View {
    @EnvironmentObject private var hp: HeadphoneController
    let mode: NoiseMode
    var compact = false

    private var subtitle: String {
        switch mode {
        case .noiseCancelling: "Block out the world"
        case .ambient: "Hear your surroundings"
        case .off: "Plain playback"
        }
    }

    var body: some View {
        let selected = hp.state.noiseMode == mode
        Button { hp.setNoiseMode(mode) } label: {
            VStack(alignment: .center, spacing: compact ? 6 : 10) {
                Image(systemName: mode.symbol)
                    .font(.system(size: compact ? 18 : 24, weight: .regular))
                    .foregroundStyle(selected ? Theme.sheet : Theme.ink)
                Text(mode.rawValue)
                    .font(.headline(compact ? 14 : 15))
                    .foregroundStyle(selected ? Theme.sheet : Theme.ink)
                if !compact {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(selected ? Theme.sheet.opacity(0.75) : Color.secondary)
                }
            }
            .padding(compact ? 12 : 16)
            .frame(maxWidth: .infinity, minHeight: compact ? 70 : 120, maxHeight: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
            .background(selected ? Theme.ink : Color.clear, in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.ink.opacity(selected ? 1 : 0.35), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 3))
            .animation(.easeOut(duration: 0.2), value: selected)
        }
        .buttonStyle(.plain)
    }
}

/// Labelled row with a trailing control, for settings lists.
struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 16)
            control
        }
    }
}
