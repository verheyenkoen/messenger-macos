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
            #if DEBUG
            print("[Notification] Permission granted: \(granted)")
            if let error = error {
                print("[Notification] Authorization error: \(error)")
            }
            #endif
        }
    }

    func isSenderBlocked(_ name: String) -> Bool {
        guard UserDefaults.standard.bool(forKey: "filterGroupsAndPages") else {
            return false
        }
        
        // 1. Known bots/pages/system messages
        let blockedNames = ["Messenger"]
        if blockedNames.contains(where: { name.contains($0) }) {
            return true
        }
        
        return false
    }

    func showNotification(title: String, body: String, conversationId: String? = nil) {
        #if DEBUG
        print("[Notification] showNotification called - title: \(title), body: \(body)")
        #endif

        // Check current permission status
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            #if DEBUG
            print("[Notification] Current authorization status: \(settings.authorizationStatus.rawValue)")
            print("[Notification] Alert setting: \(settings.alertSetting.rawValue)")
            print("[Notification] Sound setting: \(settings.soundSetting.rawValue)")
            #endif

            guard settings.authorizationStatus == .authorized else {
                #if DEBUG
                print("[Notification] ERROR: Not authorized to show notifications!")
                #endif
                return
            }

            // Respect Focus/Do Not Disturb mode
            guard settings.alertSetting == .enabled else {
                #if DEBUG
                print("[Notification] Alerts disabled (Focus mode active)")
                #endif
                return
            }
            
            // Check filter using shared logic
            if self.isSenderBlocked(title) {
                #if DEBUG
                print("[Notification] Filtered out blocked sender: \(title)")
                #endif
                return
            }
            
            #if DEBUG
            print("[Notification] Passed filter: \(title)")
            #endif

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
                    #if DEBUG
                    print("[Notification] Failed to show notification: \(error)")
                    #endif
                } else {
                    #if DEBUG
                    print("[Notification] Notification scheduled successfully")
                    #endif
                }
            }
        }
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    // Show notification even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        #if DEBUG
        print("[Notification] willPresent called")
        #endif
        // Always show banner and sound, even if app is active
        completionHandler([.banner, .sound])
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
