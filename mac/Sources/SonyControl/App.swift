import SwiftUI

@main
struct ConnectHeadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some Scene {
        Window("Connect Head", id: "main") {
            MainWindow()
                .environmentObject(appDelegate.controller)
        }
        .defaultSize(width: 900, height: 640)
        // The page paper runs to the top edge; the contents column leaves room for the window buttons.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            ContentView()
                .environmentObject(appDelegate.controller)
        } label: {
            MenuBarLabel(controller: appDelegate.controller)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = HeadphoneController()

    func applicationWillTerminate(_ notification: Notification) {
        ListeningLog.shared.save()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItem.enableOnFirstInstalledLaunch()
        // Let the window draw before Bluetooth (and its permission prompt) gets going.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [controller] in controller.start() }
        // Now Playing (and the listening history it feeds) runs whether or not the window is open.
        NowPlaying.shared.headphonesName = { [weak controller] in controller?.deviceName }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NowPlaying.shared.start() }
        // Lets Connect Head on the phone show (and control) what this Mac is playing.
        NowPlayingServer.shared.headphonesAddress = { [weak controller] in controller?.headphonesAddress }
        NowPlayingServer.shared.controller = controller
        NowPlayingServer.shared.onHandBack = { [weak controller] in
            // Give the phone's link a moment to close before taking the controls back.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { controller?.connect() }
        }
        NowPlayingServer.shared.start()
        // When started at login, stay out of the way: no window, just the menu-bar icon.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if launchedAtLogin {
            DispatchQueue.main.async {
                NSApp.windows.filter { $0.identifier?.rawValue == "main" }.forEach { $0.close() }
            }
        }
    }

    /// Keep running in the menu bar after the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

private struct MenuBarLabel: View {
    @ObservedObject var controller: HeadphoneController

    var body: some View {
        if controller.status == .connected, let battery = controller.state.battery {
            Label("\(battery)%", systemImage: "headphones")
                .labelStyle(.titleAndIcon)
        } else {
            Image(systemName: controller.status == .connected ? "headphones" : "headphones.slash")
        }
    }
}
