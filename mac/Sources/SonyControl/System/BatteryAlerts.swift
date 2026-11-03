import Foundation
import UserNotifications

/// Posts one notification when the battery drops to 20 % and another at 10 %.
/// Re-arms once the headphones charge back above the threshold.
@MainActor
final class BatteryAlerts {
    private static let thresholds = [20, 10]
    private var alerted: Set<Int> = []
    private var authorized = false

    init() {
        // UNUserNotificationCenter traps outside an app bundle (e.g. the preview renderer).
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in self.authorized = granted }
        }
    }

    func update(level: Int?, charging: Bool, deviceName: String?) {
        guard let level else { return }
        if charging {
            alerted.removeAll()
            return
        }
        alerted = alerted.filter { level <= $0 }

        // Only the lowest threshold we've just crossed gets a notification.
        guard let threshold = Self.thresholds.last(where: { level <= $0 }),
              !alerted.contains(threshold) else { return }
        alerted.formUnion(Self.thresholds.filter { $0 >= threshold })
        guard authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(deviceName ?? "Headphones") battery low"
        content.body = "\(level)% left. Time to charge."
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "battery-\(threshold)", content: content, trigger: nil))
    }
}
