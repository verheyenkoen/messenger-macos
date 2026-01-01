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

        // Setup user content controller for notifications and logging
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "notificationHandler")
        contentController.add(context.coordinator, name: "logHandler")

        // JavaScript to intercept web notifications
        let notificationScript = WKUserScript(
            source: Self.notificationOverrideJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        contentController.addUserScript(notificationScript)
        
        // JavaScript to pipe console.log to native
        let logScript = WKUserScript(
            source: Self.consoleOverrideJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        contentController.addUserScript(logScript)
        
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        // Store reference for keyboard shortcuts
        WebViewStore.shared.webView = webView

        // Observe title changes for badge
        context.coordinator.observeTitle(webView: webView)

        // Observe URL changes for conversation tracking
        context.coordinator.observeURL(webView: webView)

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
        // We defer logging until the console override is active, or use specific prefix
        // ...
        
        // Store original Notification
        const OriginalNotification = window.Notification;

        // Override Notification constructor
        window.Notification = function(title, options) {
            console.log("[JS-Notification] New notification - title: " + title);
            console.log("[JS-Notification] Options: " + JSON.stringify(options));

            // Send to native code
            window.webkit.messageHandlers.notificationHandler.postMessage({
                title: title,
                body: options?.body || '',
                tag: options?.tag || '',
                data: options?.data ? JSON.stringify(options.data) : ''
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
    
    // JavaScript to pipe console logs to native
    private static let consoleOverrideJS = """
    (function() {
        var originalLog = console.log;
        var originalWarn = console.warn;
        var originalError = console.error;

        function formatArgs(args) {
            return Array.from(args).map(arg => {
                if (typeof arg === 'object') {
                    try {
                        return JSON.stringify(arg);
                    } catch(e) {
                        return String(arg);
                    }
                }
                return String(arg);
            }).join(' ');
        }

        console.log = function() {
            var msg = formatArgs(arguments);
            window.webkit.messageHandlers.logHandler.postMessage(msg);
            originalLog.apply(console, arguments);
        };

        console.warn = function() {
            var msg = "[WARN] " + formatArgs(arguments);
            window.webkit.messageHandlers.logHandler.postMessage(msg);
            originalWarn.apply(console, arguments);
        };

        console.error = function() {
            var msg = "[ERROR] " + formatArgs(arguments);
            window.webkit.messageHandlers.logHandler.postMessage(msg);
            originalError.apply(console, arguments);
        };
        
        console.log("[JS-LogBridge] Console override installed");
    })();
    """

    // Helper to get localized scraper JS
    static func getScraperJS() -> String {
        let statusPhrases = String(localized: "scraper.statusPhrases")
        let skipPhrases = String(localized: "scraper.skipPhrases")
        let newMessageFallback = String(localized: "scraper.newMessageFallback")

        return """
        (function() {
            const localizedStatus = \"\(statusPhrases)\".split(\",\").map(s => s.trim().toLowerCase()).filter(s => s.length > 0);
            const localizedSkip = \"\(skipPhrases)\".split(\",\").map(s => s.trim().toLowerCase()).filter(s => s.length > 0);
            const fallbackText = \"\(newMessageFallback)\";

            // 0. Safety check
            const url = window.location.href;
            if (url.includes(\"login\") || url.includes(\"checkpoint\") || url.includes(\"two_step_verification\")) {
                console.log("[JS-Scraper] On login/auth page, skipping scrape.");
                return;
            }

            console.log("[JS-Scraper] Attempting to scrape last message with localized phrases...");

            const selectors = ['[role="grid"]', '[aria-label="Chats"]', '[aria-label="Konverzace"]', '[role="navigation"]', 'div[data-testid="mwthreadlist-item-list"]'];
            let container = null;
            for (const s of selectors) {
                container = document.querySelector(s);
                if (container && container.innerText.length > 10) break;
            }
            if (!container) {
                const fbRows = document.querySelectorAll('[role="row"], a[href*="/t/"]');
                if (fbRows.length > 0) container = fbRows[0].parentElement;
            }
            if (!container) return;

            const rows = container.querySelectorAll('[role="row"], a[href*="/t/"]');
            let targetRow = null;
            for (let i = 0; i < rows.length; i++) {
                 if (rows[i].innerText.trim().length > 0) { targetRow = rows[i]; break; }
            }
            if (!targetRow) return;

            let isUnread = false;
            const allTextElements = targetRow.querySelectorAll('*');
            for (let el of allTextElements) {
                const style = window.getComputedStyle(el);
                if (parseInt(style.fontWeight) >= 600) { isUnread = true; break; }
                const label = el.getAttribute('aria-label');
                if (label && (label.includes('unread') || label.includes('nepřečten'))) { isUnread = true; break; }
            }
            if (!isUnread) {
                const rl = targetRow.getAttribute('aria-label');
                if (rl && (rl.includes('unread') || rl.includes('nepřečten'))) isUnread = true;
            }

            console.log("[JS-Scraper] Is Top Conversation Unread? " + isUnread);
            const lines = targetRow.innerText.split('\\n').map(s => s.trim()).filter(line => line.length > 0);
            console.log("[JS-Scraper] Scraped data: " + JSON.stringify(lines));

            // Try to find emoji from img alt attributes
            const imgs = targetRow.querySelectorAll('img[alt]');
            let emojiAlt = null;
            for (const img of imgs) {
                const alt = img.alt;
                // Skip profile pictures and other non-emoji images
                if (alt && alt.length > 0 && alt.length <= 10 && !alt.toLowerCase().includes('profile') && !alt.toLowerCase().includes('photo')) {
                    emojiAlt = alt;
                    console.log("[JS-Scraper] Found emoji from img alt: " + emojiAlt);
                    break;
                }
            }

            if (!isUnread) {
                 console.log("[JS-Scraper] Top conversation is READ. Ignoring badge update (likely a Bell notification).");
                 window.webkit.messageHandlers.notificationHandler.postMessage({ title: "IGNORE", body: "Read", tag: 'ignore_read' });
                 return;
            }

            let senderIndex = 0;
            while (lines.length > senderIndex && (localizedStatus.some(p => lines[senderIndex].toLowerCase().includes(p)) || lines[senderIndex].length <= 2)) {
                senderIndex++;
            }

            if (lines.length > senderIndex) {
                let sender = lines[senderIndex];
                let body = "";
                for (let i = senderIndex + 1; i < lines.length; i++) {
                    const line = lines[i];
                    const low = line.toLowerCase().trim();

                    // Skip localized phrases to ignore
                    if (localizedSkip.some(phrase => low.includes(phrase))) continue;

                    // Skip labels ending with colon
                    if (line.trim().endsWith(":")) continue;

                    // Skip separators (dots, bullets) but ALLOW emojis/short text like "Ok", "👍"
                    if (line === "·" || line === "•" || line === "-") continue;

                    // Skip simple timestamps (digit + unit)
                    if (line.match(/^\\\\d+\\\\s*(min|h|d|týd|let|y|w|m)$/)) continue;

                    body = line;
                    break;
                }

                // If no body found from text, try emoji from img alt
                if (!body && emojiAlt) {
                    body = emojiAlt;
                    console.log("[JS-Scraper] Using emoji as body: " + body);
                }

                // Fallback if still no body
                if (!body || body.match(/^\\\\d+\\\\s*(min|h|d|týd|let|y|w|m)$/)) {
                    body = fallbackText;
                    console.log("[JS-Scraper] Using fallback text: " + body);
                }

                // Extract conversation ID - check if targetRow IS or CONTAINS the link
                let conversationId = null;
                let href = targetRow.getAttribute('href');  // targetRow might be the <a> itself
                if (!href) {
                    const link = targetRow.querySelector('a[href*="/t/"]');
                    if (link) href = link.getAttribute('href');
                }
                if (!href) {
                    // Check parent elements
                    const parentLink = targetRow.closest('a[href*="/t/"]');
                    if (parentLink) href = parentLink.getAttribute('href');
                }
                if (href) {
                    const match = href.match(/\\/t\\/([^\\/?]+)/);  // Match any chars until / or ?
                    if (match) {
                        conversationId = match[1];
                        console.log("[JS-Scraper] Extracted conversation ID: " + conversationId);
                    }
                } else {
                    console.log("[JS-Scraper] WARNING: Could not find href with /t/ in targetRow");
                }

                console.log("[JS-Scraper] Final match - Sender: " + sender + ", Body: " + body);
                window.webkit.messageHandlers.notificationHandler.postMessage({ title: sender, body: body, tag: conversationId || 'scraped_fallback' });
            }
        })();
        """
    }
    
    // Debug script to inspect conversation list structure
    static func getDebugInspectorJS() -> String {
        return """
        (function() {
            console.log("[JS-Inspector] Analyzing list items...");
            const selectors = ['[role="grid"]', '[aria-label="Chats"]', '[aria-label="Konverzace"]', '[role="navigation"]'];
            let container = null;
            for (const selector of selectors) {
                container = document.querySelector(selector);
                if (container && container.innerText.length > 10) break;
            }
            if (!container) return;
            const rows = container.querySelectorAll('[role="row"], a[href*="/t/"]');
            for (let i = 0; i < Math.min(rows.length, 5); i++) {
                const row = rows[i];
                const text = row.innerText.split('\\n').join(' | ');
                console.log("ROW " + i + ": " + text);
            }
        })();
        """
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private var titleObservation: NSKeyValueObservation?
        private var urlObservation: NSKeyValueObservation?
        private var appearanceObservation: NSKeyValueObservation?
        private var lastUnreadCount: Int = 0
        private var lastBadgeValue: String? = nil
        private var pendingBadgeCount: Int? = nil
        private var lastNotifiedMessage: String? = nil
        private var popupWindows: [NSWindow] = []
        private var lastCallAlertTitle: String? = nil  // Track to avoid duplicate call alerts
        private var callResetTimer: DispatchWorkItem? = nil  // Timer to reset call tracking

        func observeTitle(webView: WKWebView) {
            titleObservation = webView.observe(\.title, options: [.new]) { [weak self] _, change in
                guard let self = self else { return }
                // Flatten double-optional: String?? -> String?
                let title: String? = change.newValue.flatMap { $0 }

                // Check for incoming call in title (e.g. "Romča volá")
                if let titleStr = title, self.isCallTitle(titleStr) {
                    // Cancel any pending reset timer
                    self.callResetTimer?.cancel()
                    self.callResetTimer = nil

                    // Only show alert once per call (avoid duplicates)
                    if titleStr != self.lastCallAlertTitle {
                        self.lastCallAlertTitle = titleStr
                        print("[Call] Detected call from title: \(titleStr)")
                        DispatchQueue.main.async {
                            self.showCallAlert()
                        }
                    }
                } else {
                    // Schedule reset after 30 seconds of no call title
                    // This prevents repeated alerts when title oscillates during a call
                    self.callResetTimer?.cancel()
                    let resetWork = DispatchWorkItem { [weak self] in
                        self?.lastCallAlertTitle = nil
                        print("[Call] Reset call tracking after timeout")
                    }
                    self.callResetTimer = resetWork
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: resetWork)
                }

                self.updateBadge(from: title)
            }
        }

        func observeURL(webView: WKWebView) {
            urlObservation = webView.observe(\.url, options: [.new]) { webView, _ in
                DispatchQueue.main.async {
                    WebViewStore.shared.currentURL = webView.url
                    #if DEBUG
                    print("[URL] URL changed to: \(webView.url?.absoluteString ?? "nil")")
                    #endif
                }
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
            if message.name == "logHandler" {
                #if DEBUG
                if let log = message.body as? String {
                    print("[WebLog] \(log)")
                }
                #endif
                return
            }

            guard message.name == "notificationHandler",
                  let body = message.body as? [String: Any],
                  let title = body["title"] as? String else {
                return
            }

            let notificationBody = body["body"] as? String ?? ""
            let tag = body["tag"] as? String

            // 0. Check if this is a call notification - offer to open in browser
            if isCallNotification(title: title, body: notificationBody) {
                print("[Call] Detected call notification: \(title) - \(notificationBody)")
                DispatchQueue.main.async {
                    self.showCallAlert()
                }
                return  // Don't process as regular notification
            }

            // 1. Handle "ignore_read" tag FIRST (from Bell notification detection)
            if tag == "ignore_read" {
                #if DEBUG
                print("[Badge] Scraper detected READ conversation. Ignoring badge update (Bell notification).")
                #endif
                self.pendingBadgeCount = nil
                return
            }
            
            // 2. Shared Logic: Check if sender is blocked
            if NotificationManager.shared.isSenderBlocked(title) {
                #if DEBUG
                print("[Badge] Blocked content from: \(title) - ignoring badge update and notification")
                #endif
                // Clear pending badge count since we ignored this update
                self.pendingBadgeCount = nil
                return
            }

            // 3. If allowed, and we have a pending badge update, apply it now
            if let pending = self.pendingBadgeCount {
                NSApp.dockTile.badgeLabel = String(pending)
                NSApp.dockTile.display()
                MenuBarManager.shared.updateBadge(pending)
                self.lastUnreadCount = pending
                self.pendingBadgeCount = nil
                #if DEBUG
                print("[Badge] Applying delayed badge update: \(pending)")
                #endif
            }

            // 4. Duplicate Check
            // If the same sender and message content comes in again, suppress the notification
            // (This happens when bell notification triggers a re-scrape of an existing unread message)
            let messageKey = "\(title)|\(notificationBody)"
            if messageKey == self.lastNotifiedMessage {
                #if DEBUG
                print("[Notification] Suppressing duplicate notification for: \(title)")
                #endif
                return
            }
            self.lastNotifiedMessage = messageKey

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
                    #if DEBUG
                    print("[Badge] Title is nil, clearing badge")
                    #endif
                    return
                }

                #if DEBUG
                print("[Badge] Title changed: \(title)")
                #endif

                // Messenger uses format "(5) Messenger" for unread messages
                let pattern = "\\((\\d+)\\)"
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
                   let countRange = Range(match.range(at: 1), in: title) {
                    let count = String(title[countRange])
                    let newCount = Int(count) ?? 0

                    // Only update if badge value actually changed
                    guard count != self.lastBadgeValue else {
                        #if DEBUG
                        print("[Badge] Badge unchanged, skipping update")
                        #endif
                        return
                    }
                    self.lastBadgeValue = count

                    // LOGIC CHANGE:
                    // If filter is ON, we do NOT update badge immediately. We wait for scraper/notification.
                    // Unless count is 0 (messages read), then we always clear.
                    
                    let filterEnabled = UserDefaults.standard.bool(forKey: "filterGroupsAndPages")
                    
                    if newCount == 0 || !filterEnabled {
                        // Standard behavior
                        self.lastUnreadCount = newCount
                        self.pendingBadgeCount = nil // clear any pending
                        NSApp.dockTile.badgeLabel = count
                        NSApp.dockTile.display()
                        MenuBarManager.shared.updateBadge(newCount)
                        #if DEBUG
                        print("[Badge] Set badge to: \(count)")
                        #endif
                    } else {
                        // Filter enabled AND newCount > 0
                        // Store pending count and WAIT for scraper
                        self.pendingBadgeCount = newCount
                        #if DEBUG
                        print("[Badge] Filter ON: Deferring badge update (\(count)) until sender verified...")
                        #endif
                    }
                    
                    // Always trigger scraper if count increased, to verify sender (or as fallback for notification)
                    // We wait a brief moment for the DOM to update
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        WebViewStore.shared.webView?.evaluateJavaScript(WebView.getScraperJS(), completionHandler: nil)
                    }
                } else {
                    // Title without number (e.g. "Messenger", "Name Surname", "Someone is typing...")
                    
                    // If it contains "píše" or "typing", it's just a typing indicator.
                    // We ignore it to prevent the badge from flickering if it was previously set.
                    // However, if we just opened a chat, the title might be "Name" and then "Name is typing".
                    // For safety, we only clear if it's NOT a typing indicator.
                    
                    let isTyping = title.lowercased().contains("píše") || title.lowercased().contains("typing")
                    
                    if !isTyping {
                        // No number and not typing -> Cleared / Read
                        guard self.lastBadgeValue != nil else { return }
                        self.lastBadgeValue = nil
                        self.lastUnreadCount = 0
                        self.pendingBadgeCount = nil
                        self.lastNotifiedMessage = nil // Clear duplicate check history
                        NSApp.dockTile.badgeLabel = nil
                        NSApp.dockTile.display()
                        MenuBarManager.shared.updateBadge(0)
                        #if DEBUG
                        print("[Badge] Cleared badge (no unread messages)")
                        #endif
                    } else {
                        #if DEBUG
                        print("[Badge] Ignoring typing indicator: \(title)")
                        #endif
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Open external links in browser
            if let url = navigationAction.request.url,
               navigationAction.navigationType == .linkActivated,
               let host = url.host {

                // l.messenger.com/l.facebook.com are redirect services
                let isRedirect = host == "l.messenger.com" || host == "l.facebook.com"
                let isExternal = !host.contains("messenger.com") && !host.contains("facebook.com")

                if isRedirect || isExternal {
                    openInBrowser(url: url)
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }

        // MARK: - Post-Auth Redirect Detection

        private var hasRedirectedAfterAuth = false
        private var wasOnLoginPage = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url,
                  let host = url.host else { return }

            // Update current URL for floating button visibility
            DispatchQueue.main.async {
                WebViewStore.shared.currentURL = url
            }

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

        // MARK: - WKUIDelegate (Popup Windows)

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {

            guard let url = navigationAction.request.url else { return nil }

            let urlString = url.absoluteString
            let urlLower = urlString.lowercased()
            let host = url.host?.lowercased() ?? ""

            #if DEBUG
            print("[Popup] ========== POPUP REQUEST ==========")
            print("[Popup] URL: \(urlString)")
            print("[Popup] Host: \(host)")
            #endif

            // Check if this is a call-related URL
            let isCallUrl = urlLower.contains("/calls/") ||
                            urlLower.contains("/groupcall/") ||
                            urlLower.contains("/call/") ||
                            urlLower.contains("rtc") ||
                            urlLower.contains("webrtc")

            if isCallUrl {
                #if DEBUG
                print("[Popup] >>> CALL URL - showing alert")
                #endif
                DispatchQueue.main.async {
                    self.showCallAlert()
                }
                return nil
            }

            // l.messenger.com is a redirect service - open in browser
            let isRedirectLink = host == "l.messenger.com" || host == "l.facebook.com"

            // External links (not messenger/facebook) - open in browser
            let isExternal = !host.contains("messenger.com") && !host.contains("facebook.com")

            if isRedirectLink || isExternal {
                #if DEBUG
                print("[Popup] >>> EXTERNAL/REDIRECT - opening in browser")
                #endif
                openInBrowser(url: url)
                return nil
            }

            // Facebook/Messenger internal popup - create with shared session
            #if DEBUG
            print("[Popup] >>> INTERNAL FB/MESSENGER - creating popup with shared session")
            #endif

            // IMPORTANT: Use shared processPool and dataStore for session sharing
            configuration.processPool = WebView.processPool
            configuration.websiteDataStore = .default()

            let popupWebView = WKWebView(frame: .zero, configuration: configuration)
            popupWebView.navigationDelegate = self
            popupWebView.uiDelegate = self
            popupWebView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

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

            return popupWebView
        }

        /// Open URL in browser (Chrome if "Open calls in Chrome" is enabled, otherwise default)
        private func openInBrowser(url: URL) {
            let useChrome = UserDefaults.standard.bool(forKey: "openCallsInChrome")

            if useChrome {
                // Try to open in Chrome
                let chromeUrl = "googlechrome://\(url.absoluteString.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: ""))"
                if let chromeURL = URL(string: chromeUrl) {
                    if NSWorkspace.shared.urlForApplication(toOpen: chromeURL) != nil {
                        NSWorkspace.shared.open(chromeURL)
                        return
                    }
                }
            }

            // Fallback to default browser
            NSWorkspace.shared.open(url)
        }

        private func showCallAlert() {
            let alert = NSAlert()
            alert.messageText = String(localized: "call.detected")
            alert.informativeText = String(localized: "call.openInBrowserQuestion")
            alert.addButton(withTitle: String(localized: "call.openInBrowser"))
            alert.addButton(withTitle: String(localized: "call.cancel"))
            alert.alertStyle = .informational

            if alert.runModal() == .alertFirstButtonReturn {
                WebViewStore.shared.openInChrome()
            }
        }

        /// Check if notification title/body indicates an incoming call
        private func isCallNotification(title: String, body: String) -> Bool {
            let callKeywordsString = String(localized: "call.keywords")
            let callKeywords = callKeywordsString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

            let titleLower = title.lowercased()
            let bodyLower = body.lowercased()

            for keyword in callKeywords {
                if titleLower.contains(keyword) || bodyLower.contains(keyword) {
                    return true
                }
            }
            return false
        }

        /// Check if page title indicates an incoming call (e.g. "Name volá", "Name is calling")
        private func isCallTitle(_ title: String) -> Bool {
            let callKeywordsString = String(localized: "call.keywords")
            let callKeywords = callKeywordsString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

            let titleLower = title.lowercased()

            for keyword in callKeywords {
                if titleLower.contains(keyword) {
                    return true
                }
            }
            return false
        }

        func webViewDidClose(_ webView: WKWebView) {
            if let window = webView.window {
                window.close()
                popupWindows.removeAll { $0 == window }
                #if DEBUG
                print("[Popup] Closed popup window")
                #endif
            }
        }

        // MARK: - Media Capture (Camera/Microphone)

        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            let host = origin.host
            // Auto-grant for Messenger and Facebook domains
            if host.contains("messenger.com") || host.contains("facebook.com") {
                #if DEBUG
                print("[Media] Granting \(type) permission for \(host)")
                #endif
                decisionHandler(.grant)
            } else {
                #if DEBUG
                print("[Media] Prompting for \(type) permission for \(host)")
                #endif
                decisionHandler(.prompt)
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

        // MARK: - Error Recovery & Auto-Reconnect

        /// Called when the web content process terminates (crash or memory pressure)
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            #if DEBUG
            print("[WebView] WebContent process terminated - reloading...")
            #endif
            // Reload the page to recover
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                webView.reload()
            }
        }

        /// Called when navigation fails before the page starts loading
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError

            // Ignore cancelled requests (user navigated away)
            if nsError.code == NSURLErrorCancelled { return }

            #if DEBUG
            print("[WebView] Provisional navigation failed: \(error.localizedDescription)")
            #endif

            // Retry after a short delay for network errors
            if nsError.domain == NSURLErrorDomain {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    webView.reload()
                }
            }
        }

        /// Called when navigation fails after the page started loading
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError

            // Ignore cancelled requests
            if nsError.code == NSURLErrorCancelled { return }

            #if DEBUG
            print("[WebView] Navigation failed: \(error.localizedDescription)")
            #endif

            // Retry for network errors
            if nsError.domain == NSURLErrorDomain {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    webView.reload()
                }
            }
        }
    }
}
