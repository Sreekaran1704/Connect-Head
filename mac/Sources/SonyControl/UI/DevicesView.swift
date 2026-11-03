import SwiftUI

/// The phones/computers paired with the headphones, with multipoint connect/switch controls.
struct DevicesView: View {
    @EnvironmentObject private var hp: HeadphoneController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let devices = hp.state.devices {
                ForEach(devices) { DeviceRow(device: $0) }
                if devices.isEmpty {
                    Text("No paired devices reported.").foregroundStyle(.secondary)
                }
            } else {
                HStack { ProgressView().controlSize(.small); Text("Loading devices…") }
            }

            HStack {
                if hp.state.multipoint == false {
                    Text("Turn on “Connect to 2 devices” in Settings to use two at once.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") { hp.refreshDevices() }.controlSize(.small)
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
        HStack(spacing: 10) {
            Image(systemName: device.symbol)
                .font(.title3)
                .frame(width: 26)
                .foregroundStyle(device.connected ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name + (isThisMac ? " (this Mac)" : ""))
                    .lineLimit(1)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if device.connected {
                if !isPlaying {
                    Button("Play here") { hp.playFrom(device) }
                        .help("Switch the audio to this device")
                }
                // Disconnecting this Mac would cut the app's own link.
                if !isThisMac {
                    Button("Disconnect") { hp.disconnectDevice(device) }
                }
            } else {
                Button("Connect") { hp.connectDevice(device) }
            }
        }
        .controlSize(.small)
        .padding(8)
        .background(Color.secondary.opacity(isPlaying ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusText: String {
        guard device.connected else { return "Not connected" }
        return isPlaying ? "Connected · playing audio" : "Connected"
    }
}
