import WebKit
import Combine
import AppKit

class WebViewStore: ObservableObject {
    static let shared = WebViewStore()

    weak var webView: WKWebView?
    @Published var currentURL: URL?
    @Published var incomingCallConversationID: String?

    /// Returns true if currently viewing a conversation
    var isInConversation: Bool {
        // Use live URL from webView, fall back to cached
        guard let url = (webView?.url ?? currentURL)?.absoluteString else { return false }
        return url.contains("/t/") || url.contains("/e2ee/t/")
    }

    /// Returns true if there's an incoming call waiting
    var hasIncomingCall: Bool {
        incomingCallConversationID != nil
    }

    /// Extract conversation ID from current URL
    var currentConversationID: String? {
        // Use live URL from webView, fall back to cached
        guard let url = (webView?.url ?? currentURL)?.absoluteString else { return nil }
        if let range = url.range(of: "/t/") {
            let afterT = url[range.upperBound...]
            // Handle query params or trailing slashes
            if let endRange = afterT.range(of: "/") {
                return String(afterT[..<endRange.lowerBound])
            }
            if let queryRange = afterT.range(of: "?") {
                return String(afterT[..<queryRange.lowerBound])
            }
            return String(afterT)
        }
        return nil
    }

    private init() {
        // Listen for new message notification from menu bar
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNewMessage),
            name: .newMessageRequested,
            object: nil
        )
    }

    // MARK: - Navigace

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        webView?.reload()
    }

    // MARK: - Messenger akce

    @objc func handleNewMessage() {
        newConversation()
    }

    func newConversation() {
        // Click the new message button
        let js = """
        (function() {
            // Find new message button - has aria-label "New message"
            const btn = document.querySelector('[aria-label="New message"]') ||
                        document.querySelector('[aria-label="Nová zpráva"]');
            if (btn) {
                btn.click();
                return true;
            }
            return false;
        })()
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    func focusSearch() {
        // Focus on search field
        let js = """
        (function() {
            const search = document.querySelector('[aria-label="Search Messenger"]') ||
                           document.querySelector('[aria-label="Hledat v Messengeru"]') ||
                           document.querySelector('input[type="search"]');
            if (search) {
                search.focus();
                return true;
            }
            return false;
        })()
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    func openSettings() {
        // Open Messenger settings
        let js = """
        (function() {
            const settingsBtn = document.querySelector('[aria-label="Settings"]') ||
                                document.querySelector('[aria-label="Nastavení"]') ||
                                document.querySelector('[aria-label="Menu"]');
            if (settingsBtn) {
                settingsBtn.click();
                return true;
            }
            return false;
        })()
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - External browser integration

    /// Open current conversation in external browser for video calls
    func openInChrome() {
        guard let conversationID = currentConversationID else { return }
        openConversationInBrowser(conversationID)
    }

    /// Accept incoming call by opening conversation in external browser
    func acceptCallInChrome() {
        guard let conversationID = incomingCallConversationID else { return }
        openConversationInBrowser(conversationID)
        DispatchQueue.main.async {
            self.incomingCallConversationID = nil
        }
    }

    /// Dismiss incoming call notification
    func dismissIncomingCall() {
        incomingCallConversationID = nil
    }

    private func openConversationInBrowser(_ conversationID: String) {
        let urlString = "https://www.facebook.com/messages/t/\(conversationID)"
        guard let url = URL(string: urlString) else { return }

        // Ensure default is set (in case user clicks before opening menu)
        if !UserDefaults.standard.bool(forKey: "openCallsInChromeSet") {
            UserDefaults.standard.set(true, forKey: "openCallsInChrome")
            UserDefaults.standard.set(true, forKey: "openCallsInChromeSet")
        }

        let useChrome = UserDefaults.standard.bool(forKey: "openCallsInChrome")

        if useChrome {
            NSWorkspace.shared.open(
                [url],
                withAppBundleIdentifier: "com.google.Chrome",
                options: [],
                additionalEventParamDescriptor: nil,
                launchIdentifiers: nil
            )
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
