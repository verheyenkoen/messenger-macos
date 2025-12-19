import WebKit
import Combine

class WebViewStore: ObservableObject {
    static let shared = WebViewStore()

    weak var webView: WKWebView?

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
}
