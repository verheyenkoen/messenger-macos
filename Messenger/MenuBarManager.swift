import AppKit
import SwiftUI
import Combine

class MenuBarManager: NSObject, ObservableObject {
    static let shared = MenuBarManager()

    private var statusItem: NSStatusItem?
    @Published var unreadCount: Int = 0

    private override init() {
        super.init()
        print("[MenuBar] Initializing MenuBarManager")
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            updateIcon()
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        setupMenu()
    }

    private var floatingMenuItem: NSMenuItem?
    private var contextMenu: NSMenu?

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self

        menu.addItem(NSMenuItem(title: String(localized: "menu.openMessenger"), action: #selector(showWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: String(localized: "menu.newMessage"), action: #selector(newMessage), keyEquivalent: "n"))
        menu.addItem(NSMenuItem.separator())

        floatingMenuItem = NSMenuItem(title: String(localized: "menu.alwaysOnTop"), action: #selector(toggleFloating), keyEquivalent: "")
        menu.addItem(floatingMenuItem!)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: String(localized: "menu.quit"), action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }

        contextMenu = menu
    }

    @objc private func toggleFloating() {
        WindowManager.shared.toggleFloating()
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }

        // Use SF Symbol for message icon
        if let image = NSImage(systemSymbolName: "message.fill", accessibilityDescription: "Messenger") {
            image.isTemplate = true
            button.image = image
        }

        // Badge jako text vedle ikony
        if unreadCount > 0 {
            button.title = " \(unreadCount)"
        } else {
            button.title = ""
        }
    }

    func updateBadge(_ count: Int) {
        DispatchQueue.main.async {
            print("[MenuBar] Updating badge to: \(count)")
            self.unreadCount = count
            self.updateIcon()
        }
    }

    private func findMainWindow() -> NSWindow? {
        let windows = NSApp.windows
        print("[MenuBar] Available windows: \(windows.count)")
        for (index, window) in windows.enumerated() {
            print("[MenuBar]   Window \(index): \(window.className), level: \(window.level.rawValue), visible: \(window.isVisible)")
        }

        // Find first window that is not a status bar popup
        let mainWindow = windows.first { window in
            !window.className.contains("NSStatusBar") &&
            !window.className.contains("PopUp") &&
            window.contentView != nil
        }
        print("[MenuBar] Found main window: \(mainWindow?.className ?? "nil")")
        return mainWindow
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else {
            print("[MenuBar] statusItemClicked: no current event")
            return
        }

        print("[MenuBar] statusItemClicked: event type = \(event.type.rawValue)")

        if event.type == .rightMouseUp {
            // Right click - show menu
            print("[MenuBar] Right click - showing menu")
            statusItem?.menu = contextMenu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            // Left click - toggle window
            print("[MenuBar] Left click - toggling window")
            toggleWindow()
        }
    }

    @objc private func toggleWindow() {
        print("[MenuBar] toggleWindow called")
        if let window = findMainWindow() {
            print("[MenuBar] Window visible: \(window.isVisible)")
            if window.isVisible {
                window.orderOut(nil)
                print("[MenuBar] Window hidden")
            } else {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                print("[MenuBar] Window shown and activated")
            }
        } else {
            print("[MenuBar] ERROR: No main window found!")
        }
    }

    @objc private func showWindow() {
        print("[MenuBar] showWindow called")
        if let window = findMainWindow() {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            print("[MenuBar] Window shown and activated")
        } else {
            print("[MenuBar] ERROR: No main window found!")
        }
    }

    @objc private func newMessage() {
        print("[MenuBar] newMessage called")
        showWindow()
        NotificationCenter.default.post(name: .newMessageRequested, object: nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension Notification.Name {
    static let newMessageRequested = Notification.Name("newMessageRequested")
}

extension MenuBarManager: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Update checkmark for "Always on top"
        floatingMenuItem?.state = WindowManager.shared.isFloating ? .on : .off
    }
}
