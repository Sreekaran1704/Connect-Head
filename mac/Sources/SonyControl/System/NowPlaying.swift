import AppKit
import os

/// What's playing on this Mac. macOS keeps the system-wide Now Playing info private to Apple's
/// own apps, so this asks the players directly over AppleScript:
/// - Music and Spotify, through their scripting dictionaries;
/// - YouTube and YouTube Music tabs in Safari and Chromium browsers. The tab's title and URL
///   are always readable; play state, progress, artwork and controls need the browser's
///   "Allow JavaScript from Apple Events" option (then the page's media session is read).
/// Only apps that are already running are asked, so polling never launches anything. The first
/// query to each app triggers macOS's Automation permission prompt.
@MainActor
final class NowPlaying: ObservableObject {
    /// Runs for the app's lifetime so listening history is recorded even with the window closed.
    static let shared = NowPlaying()
    /// Name of the connected headphones, so volume is only logged when they're the output.
    var headphonesName: () -> String? = { nil }
    struct Track: Equatable {
        var source: Source
        var title: String
        var artist: String
        var album: String
        var playing: Bool
        var position: Double
        var duration: Double
        var artworkURL: String?
        /// False for a browser tab whose page can't be scripted (JavaScript from Apple Events off).
        var controllable = true

        /// The service, without the browser: "Spotify", "Music", "YouTube", "YouTube Music".
        var service: String {
            switch source {
            case .music: "Music"
            case .spotify: "Spotify"
            case .browser(_, _, _, let url): url.contains("music.youtube") ? "YouTube Music" : "YouTube"
            }
        }

        var sourceLabel: String {
            switch source {
            case .music: "Music · this Mac"
            case .spotify: "Spotify · this Mac"
            case .browser(let b, _, _, let url): "\(url.contains("music.youtube") ? "YouTube Music" : "YouTube") · \(b.name)"
            }
        }
    }

    enum Source: Equatable {
        case music, spotify
        /// Browser, window index, tab index, tab URL.
        case browser(Browser, Int, Int, String)
    }

    struct Browser: Equatable {
        let name: String
        let bundleID: String
        var isSafari: Bool { bundleID == "com.apple.Safari" }
    }

    /// Running browsers that can be scripted: Safari, plus any app whose scripting dictionary
    /// has Chromium's "execute javascript" command (Chrome, Arc, Brave, Edge, Ardia, Vivaldi…).
    private func runningBrowsers() -> [Browser] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier, let url = app.bundleURL else { return nil }
            let name = app.localizedName ?? url.deletingPathExtension().lastPathComponent
            if id == "com.apple.Safari" { return Browser(name: "Safari", bundleID: id) }
            return isChromiumScriptable(url, bundleID: id) ? Browser(name: name, bundleID: id) : nil
        }
    }

    private var scriptableCache: [String: Bool] = [:]

    private func isChromiumScriptable(_ url: URL, bundleID: String) -> Bool {
        if let known = scriptableCache[bundleID] { return known }
        let info = Bundle(url: url)?.infoDictionary
        let sdefName = info?["OSAScriptingDefinition"] as? String
        let sdef = sdefName.flatMap { try? String(contentsOf: url.appendingPathComponent("Contents/Resources/\($0)"), encoding: .utf8) }
        let result = sdef?.contains("CrSuExJa") ?? false   // Chromium's "execute … javascript" event code
        scriptableCache[bundleID] = result
        return result
    }

    private let log = Logger(subsystem: "local.sonycontrol", category: "nowplaying")
    private var lastError: String?

    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    private var timer: Timer?
    private var artworkKey: String?

    #if PREVIEW
    /// Used by scripts/preview.swift to show a sample track instead of asking real apps.
    static var previewTrack: Track?
    #endif

    func start() {
        #if PREVIEW
        if let t = Self.previewTrack { track = t; return }
        #endif
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Controls

    func playPause() {
        control(app: "playpause", page: "v.paused ? v.play() : v.pause()")
    }

    func next() {
        control(app: "next track",
                page: "(document.querySelector('.ytp-next-button') || document.querySelector('.next-button')).click()")
    }

    func previous() {
        control(app: "previous track",
                page: "v.currentTime > 3 ? (v.currentTime = 0) : ((document.querySelector('.previous-button') || {click: () => history.back()}).click())")
    }

    private func control(app verb: String, page js: String) {
        guard let track, track.controllable else { return }
        switch track.source {
        case .music: run("tell application \"Music\" to \(verb)")
        case .spotify: run("tell application \"Spotify\" to \(verb)")
        case .browser(let b, let w, let t, _):
            _ = javascript("(() => { const v = document.querySelector('video'); if (v) { \(js) } })()", browser: b, window: w, tab: t)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
    }

    // MARK: Polling

    private func refresh() {
        var found: [Track] = []
        if isRunning("com.spotify.client"), let t = queryApp("Spotify", source: .spotify) { found.append(t) }
        if isRunning("com.apple.Music"), let t = queryApp("Music", source: .music) { found.append(t) }
        for browser in runningBrowsers() {
            found += youTubeTabs(in: browser)
        }
        // Whatever is actually playing wins; otherwise a paused player that can be resumed.
        let current = found.first(where: \.playing) ?? found.first(where: \.controllable) ?? found.first
        if current != track { track = current }
        updateArtwork(for: current)
        ListeningLog.shared.record(current, headphonesName: headphonesName())
    }

    private func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private func queryApp(_ name: String, source: Source) -> Track? {
        let fields = source == .spotify
            ? "{name, artist, album} of current track & {player state as string, player position, (duration of current track) / 1000, artwork url of current track}"
            : "{name, artist, album} of current track & {player state as string, player position, duration of current track, \"\"}"
        let script = """
        tell application "\(name)"
            if player state is stopped then return {}
            return \(fields)
        end tell
        """
        guard let result = run(script), result.numberOfItems >= 7 else { return nil }
        func text(_ i: Int) -> String { result.atIndex(i)?.stringValue ?? "" }
        func number(_ i: Int) -> Double { Double(text(i).replacingOccurrences(of: ",", with: ".")) ?? 0 }
        let artwork = text(7)
        return Track(source: source, title: text(1), artist: text(2), album: text(3),
                     playing: text(4) == "playing", position: number(5), duration: number(6),
                     artworkURL: artwork.isEmpty ? nil : artwork)
    }

    /// Reads the page's video element and media session (title, artist, artwork) as JSON.
    private static let pageProbe = """
    (() => { const v = document.querySelector('video'); const m = navigator.mediaSession && navigator.mediaSession.metadata; \
    const art = m && m.artwork && m.artwork.length ? m.artwork[m.artwork.length - 1].src : ''; \
    return JSON.stringify({ playing: !!v && !v.paused && !v.ended, t: v ? v.currentTime : 0, \
    d: v && isFinite(v.duration) ? v.duration : 0, title: m && m.title ? m.title : '', \
    artist: m && m.artist ? m.artist : '', album: m && m.album ? m.album : '', art: art }); })()
    """

    private func youTubeTabs(in browser: Browser) -> [Track] {
        let titleProperty = browser.isSafari ? "name" : "title"
        let script = """
        tell application id "\(browser.bundleID)"
            set out to {}
            repeat with w from 1 to count windows
                repeat with t from 1 to count tabs of window w
                    set u to URL of tab t of window w
                    if u contains "youtube.com/watch" or u contains "music.youtube.com" or u contains "youtube.com/shorts" then
                        set end of out to {w, t, u, \(titleProperty) of tab t of window w}
                    end if
                end repeat
            end repeat
            return out
        end tell
        """
        guard let list = run(script), list.numberOfItems > 0 else { return [] }
        var tracks: [Track] = []
        for i in 1...list.numberOfItems {
            guard let item = list.atIndex(i), item.numberOfItems >= 4 else { continue }
            let w = Int(item.atIndex(1)?.int32Value ?? 1), t = Int(item.atIndex(2)?.int32Value ?? 1)
            let url = item.atIndex(3)?.stringValue ?? ""
            let tabTitle = (item.atIndex(4)?.stringValue ?? "")
                .replacingOccurrences(of: " - YouTube Music", with: "")
                .replacingOccurrences(of: " - YouTube", with: "")
                .replacingOccurrences(of: #"^\(\d+\) "#, with: "", options: .regularExpression)   // "(3) " notification count
            var track = Track(source: .browser(browser, w, t, url), title: tabTitle, artist: "", album: "",
                              playing: false, position: 0, duration: 0,
                              artworkURL: Self.thumbnail(for: url), controllable: false)
            if let json = javascript(Self.pageProbe, browser: browser, window: w, tab: t),
               let data = json.data(using: .utf8),
               let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                track.controllable = true
                track.playing = info["playing"] as? Bool ?? false
                track.position = info["t"] as? Double ?? 0
                track.duration = info["d"] as? Double ?? 0
                if let title = info["title"] as? String, !title.isEmpty { track.title = title }
                track.artist = info["artist"] as? String ?? ""
                track.album = info["album"] as? String ?? ""
                if let art = info["art"] as? String, !art.isEmpty { track.artworkURL = art }
            }
            tracks.append(track)
        }
        return tracks
    }

    private func javascript(_ js: String, browser: Browser, window w: Int, tab t: Int) -> String? {
        let escaped = js.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = browser.isSafari
            ? "tell application id \"com.apple.Safari\" to do JavaScript \"\(escaped)\" in tab \(t) of window \(w)"
            : "tell application id \"\(browser.bundleID)\" to execute tab \(t) of window \(w) javascript \"\(escaped)\""
        return run(script)?.stringValue
    }

    /// Video thumbnail from a watch / shorts URL, used when the page can't be scripted.
    private static func thumbnail(for url: String) -> String? {
        guard let comps = URLComponents(string: url) else { return nil }
        let id = comps.queryItems?.first(where: { $0.name == "v" })?.value
            ?? (comps.path.hasPrefix("/shorts/") ? String(comps.path.dropFirst("/shorts/".count)) : nil)
        return id.map { "https://i.ytimg.com/vi/\($0)/hqdefault.jpg" }
    }

    @discardableResult
    private func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? ""
            guard message != lastError else { return nil }   // log each distinct failure once
            lastError = message
            log.info("AppleScript failed: \(error[NSAppleScript.errorNumber] as? Int ?? 0, privacy: .public) \(error[NSAppleScript.errorMessage] as? String ?? "", privacy: .public)")
            return nil
        }
        return result
    }

    // MARK: Artwork

    private func updateArtwork(for track: Track?) {
        let key = track.map { "\($0.sourceLabel)|\($0.title)|\($0.album)|\($0.artworkURL ?? "")" }
        guard key != artworkKey else { return }
        artworkKey = key
        artwork = nil
        guard let track else { return }
        if let urlString = track.artworkURL, let url = URL(string: urlString) {
            Task {
                guard let (data, _) = try? await URLSession.shared.data(from: url), self.artworkKey == key else { return }
                self.artwork = NSImage(data: data)
            }
        } else if track.source == .music,
                  let data = run("tell application \"Music\" to get raw data of artwork 1 of current track")?.data {
            artwork = NSImage(data: data)
        }
    }
}
