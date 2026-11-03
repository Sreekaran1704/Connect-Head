import ServiceManagement

/// Launch-at-login via the modern login items API (shows up in System Settings → General → Login Items).
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// On the first launch of the installed copy, opt in once; later the Options menu decides.
    static func enableOnFirstInstalledLaunch() {
        let key = "loginItemInitialized"
        guard Bundle.main.bundlePath.hasPrefix("/Applications/"),
              !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        set(true)
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Login item change failed: \(error)")
        }
    }
}
