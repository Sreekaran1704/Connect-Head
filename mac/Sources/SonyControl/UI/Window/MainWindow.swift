import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case sound = "Sound"
    case equalizer = "Equalizer"
    case listening = "Listening"
    case devices = "Devices"
    case settings = "Settings"
    var id: Self { self }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .sound: "ear.and.waveform"
        case .equalizer: "slider.vertical.3"
        case .listening: "chart.bar"
        case .devices: "laptopcomputer.and.iphone"
        case .settings: "gearshape"
        }
    }
}

struct MainWindow: View {
    @EnvironmentObject private var hp: HeadphoneController
    @State private var page: Page?

    init(initialPage: Page? = .overview) {
        _page = State(initialValue: initialPage)
    }

    private var ready: Bool { hp.status == .connected && hp.loaded }

    var body: some View {
        HStack(spacing: 0) {
            ContentsColumn(page: $page)
                .frame(width: 208)
            Rectangle().fill(Theme.ink.opacity(0.85)).frame(width: 0.75)
                .padding(.vertical, 18)

            Group {
                if ready {
                    ScrollView {
                        detail
                            .padding(.horizontal, 32)
                            .padding(.top, 34)
                            .padding(.bottom, 28)
                            .frame(maxWidth: 760, alignment: .leading)
                            .frame(maxWidth: .infinity)
                    }
                    .scrollContentBackground(.hidden)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    DisconnectedView()
                        .transition(.opacity)
                }
            }
            // Crossfade between the connecting screen and the page instead of cutting.
            .animation(.easeInOut(duration: 0.45), value: ready)
            .frame(minWidth: 560, minHeight: 560)
        }
        .foregroundStyle(Theme.ink)
        .buttonStyle(PrintButtonStyle())
        .tint(Theme.ink)
        .background(PaperBackground())
        .navigationTitle(hp.deviceName ?? "Connect Head")
    }

    @ViewBuilder private var detail: some View {
        switch page ?? .overview {
        case .overview: OverviewPage(page: $page)
        case .sound: SoundPage()
        case .equalizer: EqualizerPage()
        case .listening: ListeningPage()
        case .devices: DevicesPage()
        case .settings: SettingsPage()
        }
    }
}

/// The window's navigation: sections in serif (the selected one inked in) and a small status
/// panel at the foot.
private struct ContentsColumn: View {
    @EnvironmentObject private var hp: HeadphoneController
    @Binding var page: Page?
    @State private var hovered: Page?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Page.allCases) { item in
                let selected = (page ?? .overview) == item
                Button { page = item } label: {
                    Text(item.rawValue).font(.headline(15, weight: selected ? .semibold : .regular))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(selected ? Theme.sheet : Theme.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(selected ? Theme.ink : hovered == item ? Theme.ink.opacity(0.06) : .clear,
                                in: RoundedRectangle(cornerRadius: 3))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? item : (hovered == item ? nil : hovered) }
                .padding(.vertical, 1)
            }

            Spacer(minLength: 20)
            status
        }
        .padding(.horizontal, 16)
        .padding(.top, 46)   // clear of the window buttons
        .padding(.bottom, 16)
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(hp.status == .connected ? Theme.accent : Theme.ink.opacity(0.3)).frame(width: 6, height: 6)
                Text(statusText).font(.system(size: 9.5, weight: .semibold)).tracking(1.6).textCase(.uppercase)
            }
            Text(hp.deviceName ?? "No headphones").font(.headline(15, weight: .medium)).lineLimit(1)
            if hp.status == .connected, let battery = hp.state.battery {
                Text("\(battery)% battery\(hp.state.charging ? ", charging" : "")")
                    .font(.headline(12, weight: .regular)).italic().foregroundStyle(.secondary)
            } else if hp.status != .connecting {
                Button("Reconnect") { hp.connect() }
                    .buttonStyle(.link)
                    .font(.headline(12, weight: .regular))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .printPanel(offset: 2)
    }

    private var statusText: String {
        switch hp.status {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .failed: "Not connected"
        case .inUseElsewhere: "On your phone"
        case .noDevice: "Not paired"
        case .disconnected: "Off"
        }
    }
}

private struct DisconnectedView: View {
    @EnvironmentObject private var hp: HeadphoneController

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.ink.opacity(0.06)).frame(width: 140, height: 140)
                if hp.status == .connecting {
                    Circle()
                        .stroke(Theme.ink.opacity(0.35), lineWidth: 2)
                        .frame(width: 140, height: 140)
                        .phaseAnimator([false, true]) { ring, grown in
                            ring.scaleEffect(grown ? 1.35 : 1).opacity(grown ? 0 : 1)
                        } animation: { grown in grown ? .easeOut(duration: 1.4) : .linear(duration: 0) }
                }
                Image(systemName: "headphones").font(.system(size: 60, weight: .light)).foregroundStyle(.tint)
            }

            switch hp.status {
            case .connecting:
                Text("Connecting to \(hp.deviceName ?? "your headphones")…").font(.title2.weight(.semibold))
                ProgressView().controlSize(.small)
            case .failed(let message):
                Text("Couldn't connect").font(.title2.weight(.semibold))
                Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            case .inUseElsewhere:
                Text("In use on your phone").font(.headline(24, weight: .medium))
                Text("Connect Head on your phone has the headphone controls.\nIt hands them back when you leave it, or take them here.")
                    .font(.headline(14, weight: .regular)).italic()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .noDevice:
                Text("No Sony headphones paired").font(.title2.weight(.semibold))
                Text("Pair them in System Settings → Bluetooth, then come back.").foregroundStyle(.secondary)
            default:
                Text("Headphones are off").font(.headline(24, weight: .medium))
                Text("Press and hold the power button on the headphones for about 2 seconds.\nConnect Head reconnects as soon as they're on.")
                    .font(.headline(14, weight: .regular)).italic()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if hp.status != .connecting {
                HStack {
                    Button(hp.status == .inUseElsewhere ? "Use Here" : "Connect") { hp.connect() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    Menu("Choose Device") {
                        ForEach(hp.pairedDevices, id: \.addressString) { device in
                            Button(device.name ?? device.addressString) { hp.select(device) }
                        }
                    }
                    .controlSize(.large)
                    .fixedSize()
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.3), value: hp.status)
    }
}
