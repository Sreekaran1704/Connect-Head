import SwiftUI

/// Overview masthead, in the manner of a newspaper front page: date, title and edition line,
/// connection status, then a double rule.
/// "CONNECT HEAD" in the manner of the silver Sony wordmark: wide Clarendon capitals with a
/// brushed-metal fill (darker steel in light mode so it reads on paper). No glow.
struct Wordmark: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let stops: [Gradient.Stop] = scheme == .dark
            ? [.init(color: Color(white: 0.96), location: 0), .init(color: Color(white: 0.73), location: 0.45),
               .init(color: Color(white: 0.54), location: 0.5), .init(color: Color(white: 0.79), location: 0.75),
               .init(color: Color(white: 0.61), location: 1)]
            : [.init(color: Color(white: 0.56), location: 0), .init(color: Color(white: 0.37), location: 0.45),
               .init(color: Color(white: 0.23), location: 0.5), .init(color: Color(white: 0.40), location: 0.75),
               .init(color: Color(white: 0.29), location: 1)]
        Text("CONNECT HEAD")
            .font(.custom("Superclarendon-Bold", size: 22))
            .tracking(0.9)
            .foregroundStyle(LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom))
            .accessibilityLabel("Connect Head")
    }
}

struct Masthead: View {
    @EnvironmentObject private var hp: HeadphoneController

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Wordmark()
                    Text("The \(hp.deviceName ?? "Headphones") Edition")
                        .font(.system(size: 9.5, weight: .semibold)).tracking(2.2).textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
                .fixedSize()
                Spacer()
                connectionMenu
            }
            Rule(double: true)
        }
        .confirmationDialog("Turn off \(hp.deviceName ?? "the headphones")?", isPresented: $confirmPowerOff) {
            Button("Power Off", role: .destructive) { hp.powerOff() }
        } message: {
            Text("To turn them back on, press the power button on the headphones. Connect Head reconnects on its own.")
        }
    }

    @State private var confirmPowerOff = false
    @State private var hovering = false

    /// "● Connected" opens a menu: reconnect, disconnect, switch headphones, power off.
    private var connectionMenu: some View {
        Menu {
            Section(hp.deviceName ?? "Headphones") {
                Button("Reconnect") {
                    hp.disconnect()
                    hp.connect()
                }
                Button("Disconnect") { hp.disconnect() }
            }
            let others = hp.pairedDevices.filter { $0.addressString != nil }
            if others.count > 1 {
                Menu("Switch Headphones") {
                    ForEach(others, id: \.addressString) { device in
                        Button(device.name ?? device.addressString) { hp.select(device) }
                    }
                }
            }
            Divider()
            Button("Power Off…") { confirmPowerOff = true }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(Theme.accent).frame(width: 6, height: 6)
                Text("Connected").font(.system(size: 10, weight: .semibold)).tracking(1.6).textCase(.uppercase)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(hovering ? Theme.ink.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 3))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help("Connection options")
    }
}

/// Small outlined "Power off" button that asks before turning the headphones off.
struct PowerOffButton: View {
    @EnvironmentObject private var hp: HeadphoneController
    @State private var confirm = false

    var body: some View {
        Button { confirm = true } label: {
            Label("Power Off", systemImage: "power")
                .font(.system(size: 10, weight: .semibold)).tracking(1.4).textCase(.uppercase)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.ink.opacity(0.5), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .help("Turn the headphones off")
        .confirmationDialog("Turn off \(hp.deviceName ?? "the headphones")?", isPresented: $confirm) {
            Button("Power Off", role: .destructive) { hp.powerOff() }
        } message: {
            Text("To turn them back on, press the power button on the headphones. Connect Head reconnects on its own.")
        }
    }
}

/// The battery panel: a watch-style tick dial around the headphones (filled ticks are the
/// charge left), the percentage set large in serif, and the name with a dateline of details.
struct BatteryHero: View {
    @EnvironmentObject private var hp: HeadphoneController
    @State private var shownLevel: Double = 0

    private var level: Int { hp.state.battery ?? 0 }
    private var low: Bool { level <= 20 && !hp.state.charging }

    private var dateline: String {
        [hp.state.codec?.name, hp.state.firmware.map { "Firmware \($0)" }, hp.state.noiseMode?.rawValue]
            .compactMap { $0 }
            .joined(separator: "  ·  ")
    }

    var body: some View {
        HStack(spacing: 28) {
            ZStack {
                TickDial(level: shownLevel, fill: low ? Theme.accent : Theme.ink)
                HeadphoneIllustration(level: Double(level), showsGauge: false)
                    .frame(width: 92, height: 96)
            }
            .frame(width: 164, height: 164)

            VStack(alignment: .leading, spacing: 0) {
                Text(hp.state.charging ? "Charging" : "Battery")
                    .font(.system(size: 11, weight: .semibold)).tracking(1.6).textCase(.uppercase)
                Text("\(level)%")
                    .font(.headline(58, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(low ? Theme.accent : Theme.ink)
                    .contentTransition(.numericText(value: Double(level)))
                    .padding(.top, 2)
                Rule().frame(width: 220).padding(.vertical, 10)
                Text(hp.deviceName ?? "Headphones").font(.headline(19, weight: .medium))
                Text(dateline)
                    .font(.headline(12.5, weight: .regular)).italic()
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) { PowerOffButton().padding(16) }
        .printPanel()
        .onAppear {
            withAnimation(.easeOut(duration: 0.9).delay(0.1)) { shownLevel = Double(level) }
        }
        .onChange(of: level) { _, new in
            withAnimation(.easeOut(duration: 0.6)) { shownLevel = Double(new) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Sixty ticks round a hairline circle, like a watch bezel. Ticks up to the battery level are
/// inked; the rest are faint. Every fifth tick is longer.
private struct TickDial: View, Animatable {
    var level: Double
    let fill: Color

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2
            let lit = Int((min(max(level, 0), 100) / 100 * 60).rounded())
            for i in 0..<60 {
                let a = Double(i) / 60 * 2 * .pi - .pi / 2
                let major = i % 5 == 0
                let outer = r - 1, inner = r - (major ? 14 : 8)
                var tick = Path()
                tick.move(to: CGPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
                tick.addLine(to: CGPoint(x: c.x + cos(a) * outer, y: c.y + sin(a) * outer))
                ctx.stroke(tick, with: .color(i < lit ? fill : Theme.ink.opacity(0.16)),
                           style: StrokeStyle(lineWidth: major ? 2.4 : 1.6, lineCap: .butt))
            }
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r + 20, y: c.y - r + 20, width: 2 * (r - 20), height: 2 * (r - 20))),
                       with: .color(Theme.ink.opacity(0.25)), lineWidth: 0.75)
        }
    }
}
