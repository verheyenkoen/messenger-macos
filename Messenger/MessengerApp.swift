import SwiftUI
import WebKit

@main
struct MessengerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var windowManager = WindowManager.shared

    var body: some Scene {
        Window("Messenger", id: "main") {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            // Replace File menu
            CommandGroup(replacing: .newItem) {
                Button(String(localized: "menu.newMessage")) {
                    WebViewStore.shared.newConversation()
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            // View menu - navigation
            CommandGroup(after: .toolbar) {
                Button(String(localized: "menu.back")) {
                    WebViewStore.shared.goBack()
                }
                .keyboardShortcut("[", modifiers: .command)

                Button(String(localized: "menu.forward")) {
                    WebViewStore.shared.goForward()
                }
                .keyboardShortcut("]", modifiers: .command)

                Divider()

                Button(String(localized: "menu.refresh")) {
                    WebViewStore.shared.reload()
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            // Edit menu - search
            CommandGroup(after: .pasteboard) {
                Button(String(localized: "menu.search")) {
                    WebViewStore.shared.focusSearch()
                }
                .keyboardShortcut("f", modifiers: .command)
            }

            // Window menu
            CommandGroup(before: .windowArrangement) {
                Toggle(String(localized: "menu.alwaysOnTop"), isOn: $windowManager.isFloating)
                    .keyboardShortcut("t", modifiers: [.command, .shift])

                Divider()

                Button(String(localized: "menu.hideWindow")) {
                    NSApp.windows.first?.orderOut(nil)
                }
                .keyboardShortcut("w", modifiers: .command)

                Button(String(localized: "menu.showWindow")) {
                    if let window = NSApp.windows.first {
                        window.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            
            #if DEBUG
            // Debug menu
            CommandMenu("Debug") {
                Button("Test Notification") {
                    NotificationManager.shared.showNotification(
                        title: "Test Notification",
                        body: "This is a test message from the Debug menu."
                    )
                }
                
                Button("Force Scrape") {
                    print("[Debug] Forcing scraper execution")
                    WebViewStore.shared.webView?.evaluateJavaScript(WebView.getScraperJS(), completionHandler: nil)
                }
                
                Button("Dump HTML") {
                    print("[Debug] Dumping HTML structure")
                    WebViewStore.shared.webView?.evaluateJavaScript(WebView.getDebugInspectorJS(), completionHandler: nil)
                }
            }
            #endif
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var menuBarManager: MenuBarManager?
    static let lastURLKey = "lastMessengerURL"

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Set autosave name BEFORE window is shown to prevent position jump
        DispatchQueue.main.async {
            if let window = NSApp.windows.first(where: { !$0.className.contains("NSStatusBar") }) {
                window.setFrameAutosaveName("MainWindow")
                window.delegate = self
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize menu bar icon
        menuBarManager = MenuBarManager.shared

        // Apply window settings (floating etc.)
        WindowManager.shared.applyInitialSettings()

        // Request notification permissions
        NotificationManager.shared.requestAuthorization()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't terminate - app runs in background with menu bar icon
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // No visible window - show main window when clicking Dock icon
            if let window = NSApp.windows.first(where: { !$0.className.contains("NSStatusBar") }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide window instead of closing - preserves WebView and session
        sender.orderOut(nil)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Save current URL before termination
        saveCurrentURL()
    }

    func applicationDidResignActive(_ notification: Notification) {
        // Save current URL when app goes to background
        saveCurrentURL()
    }

    // MARK: - URL Persistence

    private func saveCurrentURL() {
        if let url = WebViewStore.shared.webView?.url?.absoluteString {
            UserDefaults.standard.set(url, forKey: Self.lastURLKey)
            UserDefaults.standard.synchronize()
        }
    }

    static func getLastURL() -> URL {
        if let urlString = UserDefaults.standard.string(forKey: lastURLKey),
           let url = URL(string: urlString),
           url.host?.contains("messenger.com") == true || url.host?.contains("facebook.com") == true {
            return url
        }
        return URL(string: "https://www.messenger.com")!
    }
}
