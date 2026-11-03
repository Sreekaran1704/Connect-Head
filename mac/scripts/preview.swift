// Renders each page of the main window to build/preview/*.png using sample data (no Bluetooth).
// Build: see the swiftc line in scripts/preview.sh
import AppKit
import SwiftUI

@main
struct Preview {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let hp = HeadphoneController()
        hp.setPreview(name: "ULT WEAR", host: "A0:9A:8E:04:79:45")
        var st = HeadphoneState()
        st.firmware = "2.0.5"; st.codec = .aac; st.battery = 57
        st.noiseMode = .ambient; st.ambientLevel = 12; st.focusOnVoice = true
        st.ncButtonMode = .ncAmbientOff
        st.eqPreset = .manual; st.clearBass = 7; st.eqBands = [3, 1, -2, 2, 5]
        st.voiceAssistant = .off; st.dseeUpsampling = true; st.preferSoundQuality = true
        st.multipoint = true; st.captureVoiceDuringCall = true; st.voiceGuidance = true; st.voiceGuidanceVolume = 0
        st.devices = [
            SourceDevice(address: "7C:F0:E5:B3:44:B8", name: "OnePlus Nord 5", slot: 2, classOfDevice: 0x7a420c),
            SourceDevice(address: "A0:9A:8E:04:79:45", name: "Sreekaran’s MacBook Air", slot: 1, classOfDevice: 0x28010c),
            SourceDevice(address: "3C:9C:0F:2A:8B:35", name: "DESKTOP-K2L7IFS", slot: 0, classOfDevice: 0x0a410c),
        ]
        st.playbackDevice = "A0:9A:8E:04:79:45"
        hp.state = st
        NowPlaying.previewTrack = .init(source: .spotify, title: "Midnight City", artist: "M83",
                                        album: "Hurry Up, We're Dreaming", playing: true,
                                        position: 96, duration: 244, artworkURL: nil)
        NowPlaying.shared.start()
        // A week of made-up listening for the Listening page.
        var sessions: [ListeningLog.Session] = [], volume: [ListeningLog.VolumeMinute] = []
        let catalog = [("Midnight City", "M83", "Spotify"), ("Redbone", "Childish Gambino", "Spotify"),
                       ("Lofi beats to study to", "Lofi Girl", "YouTube"), ("Nights", "Frank Ocean", "Music"),
                       ("Blinding Lights", "The Weeknd", "YouTube Music"), ("Wait", "M83", "Spotify")]
        var rng = SystemRandomNumberGenerator()
        let today = Calendar.current.startOfDay(for: .now)
        for day in 0..<7 {
            let base = today.addingTimeInterval(Double(-day) * 86_400)
            for _ in 0..<Int.random(in: 4...14, using: &rng) {
                let (t, a, svc) = catalog.randomElement(using: &rng)!
                let start = base.addingTimeInterval(Double([8, 9, 13, 18, 20, 21, 22].randomElement(using: &rng)!) * 3600 + Double.random(in: 0...3000))
                let secs = Double.random(in: 180...1500, using: &rng)
                sessions.append(.init(title: t, artist: a, service: svc, start: start, seconds: secs))
                let level = Double.random(in: 0.45...0.85, using: &rng)
                for m in 0..<Int(secs / 60) {
                    volume.append(.init(minute: start.addingTimeInterval(Double(m) * 60), level: level, seconds: 60))
                }
            }
        }
        ListeningLog.shared.setPreview(sessions: sessions.sorted { $0.start < $1.start }, volume: volume)
        let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/preview")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        for page in Page.allCases {
            // Snapshots skip the window's own background, so paint it explicitly.
            let root = PreviewWindow(page: page).environmentObject(hp)
                .background(Theme.paper)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: Double(ProcessInfo.processInfo.environment["PREVIEW_HEIGHT"] ?? "") ?? 660),
                                  styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: CommandLine.arguments.contains("dark") ? .darkAqua : .aqua)
            window.contentView = NSHostingView(rootView: root)
            window.orderFrontRegardless()
            for _ in 0..<20 { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            let view = window.contentView!
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: rep)
            try! rep.representation(using: .png, properties: [:])!
                .write(to: out.appendingPathComponent("\(page.rawValue.lowercased()).png"))
            window.close()
        }
        print(out.path)
    }
}

private struct PreviewWindow: View {
    @State var page: Page?
    var body: some View { MainWindow(initialPage: page) }
}
