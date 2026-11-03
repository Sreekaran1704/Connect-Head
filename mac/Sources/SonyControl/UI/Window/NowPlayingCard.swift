import SwiftUI

/// "Now playing" panel for the Overview: artwork, title and artist, a hairline progress bar,
/// and previous / play-pause / next. When the headphones are playing from another device the
/// panel says so (track details are only readable for Music and Spotify on this Mac).
struct NowPlayingCard: View {
    @EnvironmentObject private var hp: HeadphoneController
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        Card(title: "Now playing") {
            if let track = player.track {
                HStack(spacing: 16) {
                    artwork
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title).font(.headline(18, weight: .medium)).lineLimit(1)
                        Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " — "))
                            .font(.headline(13, weight: .regular)).italic()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(track.sourceLabel)
                            .font(.system(size: 9.5, weight: .semibold)).tracking(1.4).textCase(.uppercase)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    Spacer(minLength: 12)
                    if track.controllable { controls(playing: track.playing) }
                }
                if track.controllable {
                    progress(track)
                } else {
                    Text("To see progress and control YouTube from here, turn on “Allow JavaScript from Apple Events” in your browser’s Developer menu.")
                        .font(.headline(11.5, weight: .regular)).italic()
                        .foregroundStyle(.secondary)
                }
            } else if let device = otherPlaybackDevice {
                HStack(spacing: 14) {
                    Image(systemName: device.symbol)
                        .font(.system(size: 18))
                        .frame(width: 56, height: 56)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.ink.opacity(0.35), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Playing from \(device.name)").font(.headline(17, weight: .medium)).lineLimit(1)
                        Text("Track details are shown for Music, Spotify and YouTube on this Mac.")
                            .font(.headline(12.5, weight: .regular)).italic().foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(spacing: 14) {
                    Image(systemName: "music.note")
                        .font(.system(size: 18))
                        .frame(width: 56, height: 56)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.ink.opacity(0.35), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Nothing playing").font(.headline(17, weight: .medium))
                        Text("Start something in Music, Spotify or YouTube and it will appear here.")
                            .font(.headline(12.5, weight: .regular)).italic().foregroundStyle(.secondary)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: player.track?.title)
    }

    private var otherPlaybackDevice: SourceDevice? {
        guard let address = hp.state.playbackDevice, address != hp.hostAddress else { return nil }
        return hp.state.devices?.first { $0.address == address }
    }

    private var artwork: some View {
        Group {
            if let image = player.artwork {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
            } else {
                Image(systemName: "music.note").font(.system(size: 20)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.ink, lineWidth: 1))
    }

    private func controls(playing: Bool) -> some View {
        HStack(spacing: 8) {
            control("backward.fill", help: "Previous") { player.previous() }
            control(playing ? "pause.fill" : "play.fill", help: playing ? "Pause" : "Play", prominent: true) { player.playPause() }
            control("forward.fill", help: "Next") { player.next() }
        }
    }

    private func control(_ symbol: String, help: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 14 : 11))
                .frame(width: prominent ? 38 : 30, height: prominent ? 38 : 30)
                .foregroundStyle(prominent ? Theme.sheet : Theme.ink)
                .background(prominent ? Theme.ink : .clear, in: RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.ink.opacity(prominent ? 1 : 0.5), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func progress(_ track: NowPlaying.Track) -> some View {
        let fraction = track.duration > 0 ? min(max(track.position / track.duration, 0), 1) : 0
        return HStack(spacing: 10) {
            Text(Self.time(track.position)).font(.headline(11, weight: .regular)).monospacedDigit().foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.ink.opacity(0.2)).frame(height: 1)
                    Rectangle().fill(Theme.ink).frame(width: geo.size.width * fraction, height: 2)
                }
                .frame(maxHeight: .infinity)
                .animation(.linear(duration: track.playing ? 2 : 0.2), value: fraction)
            }
            .frame(height: 8)
            Text(Self.time(track.duration)).font(.headline(11, weight: .regular)).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private static func time(_ seconds: Double) -> String {
        let s = Int(max(seconds, 0))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
