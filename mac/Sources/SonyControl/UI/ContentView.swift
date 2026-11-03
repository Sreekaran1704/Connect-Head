import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var hp: HeadphoneController
    @State private var tab = Tab.sound

    enum Tab: String, CaseIterable, Identifiable {
        case sound = "Sound", equalizer = "EQ", devices = "Devices", settings = "Settings"
        var id: Self { self }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderView()
            Divider()

            if hp.status == .connected && hp.loaded {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Group {
                    switch tab {
                    case .sound: SoundView()
                    case .equalizer: EqualizerView()
                    case .devices: DevicesView()
                    case .settings: SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ConnectionView()
            }

            Divider()
            FooterView()
        }
        .padding(14)
        .frame(width: 340)
    }
}

private struct HeaderView: View {
    @EnvironmentObject private var hp: HeadphoneController

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "headphones")
                .font(.system(size: 26))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(hp.deviceName ?? "No headphones")
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let battery = hp.state.battery, hp.status == .connected {
                BatteryView(level: battery, charging: hp.state.charging)
            }
        }
    }

    private var subtitle: String {
        switch hp.status {
        case .connected:
            [hp.state.codec?.name, hp.state.firmware.map { "FW \($0)" }]
                .compactMap { $0 }.joined(separator: " · ").ifEmpty("Connected")
        case .connecting: "Connecting…"
        case .disconnected: "Disconnected"
        case .inUseElsewhere: "In use on your phone"
        case .noDevice: "No paired Sony headphones found"
        case .failed: "Connection failed"
        }
    }
}

private struct BatteryView: View {
    let level: Int
    let charging: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: charging ? "battery.100.bolt" : symbol)
                .foregroundStyle(level <= 20 && !charging ? .red : .primary)
            Text("\(level)%")
                .font(.callout.monospacedDigit())
        }
    }

    private var symbol: String {
        switch level {
        case ..<13: "battery.0"
        case ..<38: "battery.25"
        case ..<63: "battery.50"
        case ..<88: "battery.75"
        default: "battery.100"
        }
    }
}

private struct ConnectionView: View {
    @EnvironmentObject private var hp: HeadphoneController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch hp.status {
            case .connecting:
                HStack { ProgressView().controlSize(.small); Text("Talking to your headphones…") }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            case .noDevice:
                Text("Pair your headphones in System Settings → Bluetooth first.")
            case .inUseElsewhere:
                Text("Connect Head on your phone is using the headphone controls.")
            default:
                Text("Turn on your headphones, then connect.")
            }

            if hp.status != .connecting {
                Button(hp.status == .inUseElsewhere ? "Use Here" : "Connect") { hp.connect() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FooterView: View {
    @EnvironmentObject private var hp: HeadphoneController
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        HStack {
            Menu {
                ForEach(hp.pairedDevices, id: \.addressString) { device in
                    Button(device.name ?? device.addressString) { hp.select(device) }
                }
                Button("Refresh list") { hp.refreshPairedDevices() }
                Divider()
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { LoginItem.set($0); launchAtLogin = LoginItem.isEnabled }))
            } label: {
                Label("Options", systemImage: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            if hp.status == .connected {
                Button("Power Off") { hp.powerOff() }
            }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .controlSize(.small)
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
