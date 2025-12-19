import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    // Shared process pool ensures session persistence across WebView recreations
    private static let processPool = WKProcessPool()

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.processPool = Self.processPool
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        // Setup user content controller for notifications
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "notificationHandler")

        // JavaScript to intercept web notifications
        let notificationScript = WKUserScript(
            source: Self.notificationOverrideJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        contentController.addUserScript(notificationScript)
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        // Store reference for keyboard shortcuts
        WebViewStore.shared.webView = webView

        // Observe title changes for badge
        context.coordinator.observeTitle(webView: webView)

        // Observe system appearance changes for dark/light mode
        context.coordinator.observeAppearanceChanges(webView: webView)

        // Load last URL or default to messenger.com
        let url = AppDelegate.getLastURL()
        webView.load(URLRequest(url: url))

        return webView
    }

    // JavaScript to override Notification API
    private static let notificationOverrideJS = """
    (function() {
        // Store original Notification
        const OriginalNotification = window.Notification;

        // Override Notification constructor
        window.Notification = function(title, options) {
            // Send to native code
            window.webkit.messageHandlers.notificationHandler.postMessage({
                title: title,
                body: options?.body || '',
                tag: options?.tag || ''
            });

            // Also create original notification (for compatibility)
            return new OriginalNotification(title, options);
        };

        // Copy static properties
        window.Notification.permission = OriginalNotification.permission;
        window.Notification.requestPermission = OriginalNotification.requestPermission.bind(OriginalNotification);

        // Override requestPermission for automatic approval
        window.Notification.requestPermission = function(callback) {
            if (callback) callback('granted');
            return Promise.resolve('granted');
        };

        // Set permission as granted
        Object.defineProperty(window.Notification, 'permission', {
            get: function() { return 'granted'; }
        });
    })();
    """
    
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private var titleObservation: NSKeyValueObservation?
        private var appearanceObservation: NSKeyValueObservation?
        private var lastUnreadCount: Int = 0
        private var lastBadgeValue: String? = nil
        private var popupWindows: [NSWindow] = []

        func observeTitle(webView: WKWebView) {
            titleObservation = webView.observe(\.title, options: [.new]) { _, change in
                self.updateBadge(from: change.newValue ?? "")
            }
        }

        // MARK: - Dark/Light Mode Sync

        func observeAppearanceChanges(webView: WKWebView) {
            appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak webView] _, _ in
                // Notify web page about appearance change
                let js = "document.documentElement.style.colorScheme = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'"
                webView?.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        // MARK: - WKScriptMessageHandler

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "notificationHandler",
                  let body = message.body as? [String: Any],
                  let title = body["title"] as? String else {
                return
            }

            let notificationBody = body["body"] as? String ?? ""
            let tag = body["tag"] as? String

            NotificationManager.shared.showNotification(
                title: title,
                body: notificationBody,
                conversationId: tag
            )
        }
        
        private func updateBadge(from title: String?) {
            DispatchQueue.main.async {
                guard let title = title else {
                    NSApp.dockTile.badgeLabel = nil
                    NSApp.dockTile.display()
                    MenuBarManager.shared.updateBadge(0)
                    print("[Badge] Title is nil, clearing badge")
                    return
                }

                print("[Badge] Title changed: \(title)")

                // Messenger uses format "(5) Messenger" for unread messages
                let pattern = "\\((\\d+)\\)"
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
                   let countRange = Range(match.range(at: 1), in: title) {
                    let count = String(title[countRange])
                    let newCount = Int(count) ?? 0

                    // Only update if badge value actually changed
                    guard count != self.lastBadgeValue else {
                        print("[Badge] Badge unchanged, skipping update")
                        return
                    }
                    self.lastBadgeValue = count

                    // Send notification when unread count increases
                    if newCount > self.lastUnreadCount {
                        let message = newCount == 1
                            ? String(localized: "notification.newMessage")
                            : String(localized: "notification.unreadMessages \(newCount)")
                        NotificationManager.shared.showNotification(
                            title: "Messenger",
                            body: message
                        )
                        print("[Badge] Sending notification: \(message)")
                    }
                    self.lastUnreadCount = newCount

                    NSApp.dockTile.badgeLabel = count
                    NSApp.dockTile.display()
                    MenuBarManager.shared.updateBadge(newCount)
                    print("[Badge] Set badge to: \(count)")
                } else {
                    // Title without number (e.g. "Someone píše!") - DON'T clear badge
                    // Only clear if title contains "Messenger" without number (meaning no unread)
                    if title.contains("Messenger") && !title.contains("píše") {
                        guard self.lastBadgeValue != nil else { return }
                        self.lastBadgeValue = nil
                        self.lastUnreadCount = 0
                        NSApp.dockTile.badgeLabel = nil
                        NSApp.dockTile.display()
                        MenuBarManager.shared.updateBadge(0)
                        print("[Badge] Cleared badge (no unread messages)")
                    } else {
                        print("[Badge] Ignoring typing indicator: \(title)")
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Open external links in default browser
            if let url = navigationAction.request.url,
               navigationAction.navigationType == .linkActivated,
               let host = url.host,
               !host.contains("messenger.com") && !host.contains("facebook.com") {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        // MARK: - Post-Auth Redirect Detection

        private var hasRedirectedAfterAuth = false
        private var wasOnLoginPage = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url,
                  let host = url.host else { return }

            #if DEBUG
            print("[Nav] Page loaded: \(url.absoluteString)")
            #endif

            // Ignore messenger.com
            if host.contains("messenger.com") {
                hasRedirectedAfterAuth = false
                wasOnLoginPage = false
                return
            }

            // facebook.com/messages is the goal
            if host.contains("facebook.com") && url.path.lowercased().hasPrefix("/messages") {
                hasRedirectedAfterAuth = false
                wasOnLoginPage = false
                return
            }

            // Only handle facebook.com
            guard host.contains("facebook.com") else { return }

            let path = url.path.lowercased()

            // Track if we're on a login page
            let isLoginPage = path.contains("login") || path.contains("two_step") || path.contains("checkpoint")

            if isLoginPage {
                wasOnLoginPage = true
                return
            }

            // If we just came from login and landed on homepage, redirect to messages
            if wasOnLoginPage && !hasRedirectedAfterAuth && (path == "/" || path.isEmpty) {
                #if DEBUG
                print("[Nav] Redirecting from homepage to messages after login")
                #endif
                hasRedirectedAfterAuth = true
                wasOnLoginPage = false
                webView.load(URLRequest(url: URL(string: "https://www.facebook.com/messages")!))
            }
        }

        // MARK: - WKUIDelegate (File Upload)

        func webView(_ webView: WKWebView,
                     runOpenPanelWith parameters: WKOpenPanelParameters,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping ([URL]?) -> Void) {
            let openPanel = NSOpenPanel()
            openPanel.canChooseFiles = true
            openPanel.canChooseDirectories = false
            openPanel.allowsMultipleSelection = parameters.allowsMultipleSelection
            openPanel.begin { response in
                completionHandler(response == .OK ? openPanel.urls : nil)
            }
        }

        // MARK: - WKUIDelegate (Popup Windows for Video Calls)

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {

            // Create popup WebView
            let popupWebView = WKWebView(frame: .zero, configuration: configuration)
            popupWebView.navigationDelegate = self
            popupWebView.uiDelegate = self

            // Determine window size
            let width = windowFeatures.width?.doubleValue ?? 800
            let height = windowFeatures.height?.doubleValue ?? 600

            // Create window
            let window = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: width, height: height),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.contentView = popupWebView
            window.title = "Messenger"
            window.center()
            window.makeKeyAndOrderFront(nil)

            popupWindows.append(window)
            print("[Popup] Created popup window: \(navigationAction.request.url?.absoluteString ?? "unknown")")

            return popupWebView
        }

        func webViewDidClose(_ webView: WKWebView) {
            if let window = webView.window {
                window.close()
                popupWindows.removeAll { $0 == window }
                print("[Popup] Closed popup window")
            }
        }

        // MARK: - Downloads

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            // Check if it's a download (Content-Disposition: attachment)
            if let response = navigationResponse.response as? HTTPURLResponse,
               let contentDisposition = response.value(forHTTPHeaderField: "Content-Disposition"),
               contentDisposition.contains("attachment") {
                decisionHandler(.download)
                return
            }

            // Check MIME type for common downloadable files
            let downloadableMimeTypes = [
                "application/zip",
                "application/pdf",
                "application/octet-stream",
                "image/jpeg",
                "image/png",
                "image/gif",
                "video/mp4",
                "audio/mpeg"
            ]

            if let mimeType = navigationResponse.response.mimeType,
               downloadableMimeTypes.contains(mimeType) && !navigationResponse.canShowMIMEType {
                decisionHandler(.download)
                return
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            DownloadManager.shared.startDownload(download)
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            DownloadManager.shared.startDownload(download)
        }
    }
}
