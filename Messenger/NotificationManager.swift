import UserNotifications
import AppKit
import Combine
import WebKit

class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    private static let incomingCallCategoryId = "INCOMING_CALL"
    private static let acceptCallActionId = "ACCEPT_CALL"

    private var callDismissWorkItem: DispatchWorkItem?

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        registerNotificationCategories()
    }

    private func registerNotificationCategories() {
        let acceptAction = UNNotificationAction(
            identifier: Self.acceptCallActionId,
            title: String(localized: "call.acceptInChrome"),
            options: [.foreground]
        )

        let callCategory = UNNotificationCategory(
            identifier: Self.incomingCallCategoryId,
            actions: [acceptAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([callCategory])
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

    /// Check if notification indicates an incoming call
    private func isIncomingCall(title: String, body: String) -> Bool {
        let keywordsString = String(localized: "call.keywords")
        let keywords = keywordsString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

        let combinedText = "\(title) \(body)".lowercased()
        return keywords.contains { combinedText.contains($0) }
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

            // Check if this is an incoming call
            let isCall = self.isIncomingCall(title: title, body: body)

            if isCall {
                content.categoryIdentifier = Self.incomingCallCategoryId

                // Set in-app accept button state
                if let conversationId = conversationId {
                    DispatchQueue.main.async {
                        self.setIncomingCall(conversationId: conversationId)
                    }
                }

                #if DEBUG
                print("[Notification] Incoming call detected from: \(title)")
                #endif
            }

            if let conversationId = conversationId {
                content.userInfo = ["conversationId": conversationId, "isCall": isCall]
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

    /// Set incoming call state with auto-dismiss after 60 seconds
    private func setIncomingCall(conversationId: String) {
        // Cancel any previous dismiss timer
        callDismissWorkItem?.cancel()

        // Set the incoming call conversation ID
        WebViewStore.shared.incomingCallConversationID = conversationId

        // Auto-dismiss after 60 seconds (call likely ended or went to voicemail)
        let workItem = DispatchWorkItem { [weak self] in
            WebViewStore.shared.dismissIncomingCall()
            #if DEBUG
            print("[Notification] Auto-dismissed incoming call after 60s")
            #endif
        }
        callDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: workItem)
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

    // Handle notification click or action
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let conversationId = userInfo["conversationId"] as? String

        // Handle "Accept in Chrome" action
        if response.actionIdentifier == Self.acceptCallActionId {
            if let conversationId = conversationId {
                WebViewStore.shared.incomingCallConversationID = conversationId
                WebViewStore.shared.acceptCallInChrome()
            }
            completionHandler()
            return
        }

        // Default action (notification tap) - show window and open conversation
        if let window = NSApp.windows.first(where: { !$0.className.contains("NSStatusBar") }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        if let conversationId = conversationId {
            openConversation(id: conversationId)
        }

        completionHandler()
    }

    private func openConversation(id: String) {
        // Skip navigation for internal tags (not real conversation IDs)
        let internalTags = ["scraped_fallback", "ignore_read"]
        guard !internalTags.contains(id) else {
            #if DEBUG
            print("[Notification] Skipping navigation for internal tag: \(id)")
            #endif
            return
        }

        // Use SPA-friendly navigation: click on sidebar link instead of changing URL
        let js = """
        (function() {
            // Find conversation link in sidebar and click it (SPA navigation, no reload)
            const link = document.querySelector('a[href*="/t/\(id)"]');
            if (link) {
                console.log("[JS-Nav] Found sidebar link, clicking for SPA navigation");
                link.click();
                return true;
            }
            // Fallback: change URL (causes reload but works)
            console.log("[JS-Nav] Sidebar link not found, falling back to URL change");
            window.location.href = 'https://www.messenger.com/t/\(id)';
            return false;
        })()
        """
        WebViewStore.shared.webView?.evaluateJavaScript(js, completionHandler: nil)
    }
}
