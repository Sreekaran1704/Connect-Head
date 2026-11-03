import SwiftUI

struct DevicesPage: View {
    @EnvironmentObject private var hp: HeadphoneController

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                PageHeader(title: "Devices", subtitle: "Phones and computers paired with your headphones")
                Spacer()
                Button { hp.refreshDevices() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }

            if hp.state.multipoint == false {
                Label("“Connect to 2 devices” is off, so only one device can be connected at a time. Turn it on in Settings.",
                      systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }

            Card {
                if let devices = hp.state.devices {
                    if devices.isEmpty {
                        Text("No paired devices reported.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(devices.enumerated()), id: \.element.id) { i, device in
                        if i > 0 { Divider() }
                        DeviceRow(device: device)
                    }
                } else {
                    HStack { ProgressView().controlSize(.small); Text("Loading devices…") }
                }
            }
        }
    }
}

private struct DeviceRow: View {
    @EnvironmentObject private var hp: HeadphoneController
    let device: SourceDevice

    private var isThisMac: Bool { device.address == hp.hostAddress }
    private var isPlaying: Bool { device.address == hp.state.playbackDevice }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Theme.ink.opacity(device.connected ? 0.6 : 0.25), lineWidth: 1)
                    .frame(width: 40, height: 40)
                Image(systemName: device.symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(device.connected ? Theme.ink : .secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(device.name).font(.headline(15, weight: .medium)).lineLimit(1)
                    if isThisMac {
                        Text("This Mac")
                            .font(.system(size: 9, weight: .semibold)).tracking(1.2).textCase(.uppercase)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.ink.opacity(0.5), lineWidth: 0.75))
                    }
                }
                HStack(spacing: 6) {
                    Circle().fill(device.connected ? Theme.ink : Theme.ink.opacity(0.25)).frame(width: 5, height: 5)
                    Text(statusText).font(.headline(12, weight: .regular)).italic().foregroundStyle(.secondary)
                }
            }

            Spacer()

            if device.connected {
                if isPlaying {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.accent).frame(width: 6, height: 6)
                        Text("Playing").font(.system(size: 10, weight: .semibold)).tracking(1.4).textCase(.uppercase)
                    }
                } else {
                    Button("Play Here") { hp.playFrom(device) }
                        .help("Switch the audio to this device")
                }
                // Disconnecting this Mac would cut the app's own link.
                if !isThisMac {
                    Button("Disconnect") { hp.disconnectDevice(device) }
                }
            } else {
                Button("Connect") { hp.connectDevice(device) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusText: String {
        guard device.connected else { return "Not connected" }
        return isPlaying ? "Connected · playing audio" : "Connected"
    }
}
