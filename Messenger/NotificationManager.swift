import UserNotifications
import AppKit
import Combine
import WebKit

class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            print("[Notification] Permission granted: \(granted)")
            if let error = error {
                print("[Notification] Authorization error: \(error)")
            }
        }
    }

    func showNotification(title: String, body: String, conversationId: String? = nil) {
        print("[Notification] showNotification called - title: \(title), body: \(body)")

        // Check current permission status
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            print("[Notification] Current authorization status: \(settings.authorizationStatus.rawValue)")
            print("[Notification] Alert setting: \(settings.alertSetting.rawValue)")
            print("[Notification] Sound setting: \(settings.soundSetting.rawValue)")

            guard settings.authorizationStatus == .authorized else {
                print("[Notification] ERROR: Not authorized to show notifications!")
                return
            }

            // Respect Focus/Do Not Disturb mode
            guard settings.alertSetting == .enabled else {
                print("[Notification] Alerts disabled (Focus mode active)")
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            if let conversationId = conversationId {
                content.userInfo = ["conversationId": conversationId]
            }

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )

            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("[Notification] Failed to show notification: \(error)")
                } else {
                    print("[Notification] Notification scheduled successfully")
                }
            }
        }
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    // Show notification even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        print("[Notification] willPresent called")

        // Find main window (not status bar)
        let mainWindow = NSApp.windows.first { window in
            !window.className.contains("NSStatusBar") &&
            !window.className.contains("PopUp") &&
            window.contentView != nil
        }

        let isWindowVisible = mainWindow?.isVisible ?? false
        let isAppActive = NSApp.isActive

        print("[Notification] Main window visible: \(isWindowVisible), App active: \(isAppActive)")

        // Show notification if window is not visible OR app is not active
        if !isWindowVisible || !isAppActive {
            print("[Notification] Showing banner notification")
            completionHandler([.banner, .sound])
        } else {
            print("[Notification] Suppressing notification (window visible and app active)")
            completionHandler([])
        }
    }

    // Handle notification click
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Show window
        if let window = NSApp.windows.first(where: { !$0.className.contains("NSStatusBar") }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        // If we have conversationId, open specific conversation
        if let conversationId = response.notification.request.content.userInfo["conversationId"] as? String {
            openConversation(id: conversationId)
        }

        completionHandler()
    }

    private func openConversation(id: String) {
        let js = """
        (function() {
            window.location.href = 'https://www.messenger.com/t/\(id)';
        })()
        """
        WebViewStore.shared.webView?.evaluateJavaScript(js, completionHandler: nil)
    }
}
