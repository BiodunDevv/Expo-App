import Foundation
import UserNotifications

/// macOS notifications for problems that happen while no Expo window can show them.
enum Notifier {
    /// While Expo is hidden from screen shares the banner stays generic, because
    /// notifications can appear in a share.
    static func post(_ message: String, discreet: Bool) {
        // Unavailable outside an app bundle.
        guard Bundle.main.bundleIdentifier != nil else { return }
        let body = discreet ? "Open Expo to check a problem." : message
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Expo"
            content.body = body
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "expo.problem", content: content, trigger: nil))
        }
    }
}
