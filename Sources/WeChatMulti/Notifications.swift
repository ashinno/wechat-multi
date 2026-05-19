import Foundation
import UserNotifications

/// Thin wrapper around `UNUserNotificationCenter` for the few moments we
/// surface system banners — currently just "Slot N is ready" after the
/// multi-second clone prep step finishes.
///
/// Requests authorization lazily on first send. macOS only ever prompts once;
/// if the user denies, subsequent `send` calls fail silently and the rest of
/// the app continues to work fine.
enum AppNotifications {

    /// Post a banner. If the user has never granted/denied notifications,
    /// macOS will show its standard authorization prompt the first time this
    /// is called. Safe to call from any queue.
    static func send(title: String, body: String, identifier: String = UUID().uuidString) {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert])
            }
            // Re-read in case the request just changed it.
            let updated = await center.notificationSettings()
            guard updated.authorizationStatus == .authorized
                    || updated.authorizationStatus == .provisional
            else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            // No sound by default — these are status banners, not interruptions.

            let request = UNNotificationRequest(identifier: identifier,
                                                content: content,
                                                trigger: nil)
            try? await center.add(request)
        }
    }
}
