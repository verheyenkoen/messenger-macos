import AppKit
import SwiftUI
import Combine

class MenuBarManager: NSObject, ObservableObject {
    static let shared = MenuBarManager()

    private var statusItem: NSStatusItem?
    @Published var unreadCount: Int = 0

    private override init() {
        super.init()
        #if DEBUG
        print("[MenuBar] Initializing MenuBarManager")
        #endif
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
    private var filterMenuItem: NSMenuItem?
    private var contextMenu: NSMenu?

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self

        menu.addItem(NSMenuItem(title: String(localized: "menu.openMessenger"), action: #selector(showWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: String(localized: "menu.newMessage"), action: #selector(newMessage), keyEquivalent: "n"))
        menu.addItem(NSMenuItem.separator())

        floatingMenuItem = NSMenuItem(title: String(localized: "menu.alwaysOnTop"), action: #selector(toggleFloating), keyEquivalent: "")
        menu.addItem(floatingMenuItem!)
        
        filterMenuItem = NSMenuItem(title: String(localized: "menu.filterMessages"), action: #selector(toggleFilter), keyEquivalent: "")
        menu.addItem(filterMenuItem!)

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
    
    @objc private func toggleFilter() {
        let key = "filterGroupsAndPages"
        let current = UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(!current, forKey: key)
        // State update handled in menuWillOpen, but we can update immediately too
        filterMenuItem?.state = !current ? .on : .off
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
            #if DEBUG
            print("[MenuBar] Updating badge to: \(count)")
            #endif
            self.unreadCount = count
            self.updateIcon()
        }
    }

    private func findMainWindow() -> NSWindow? {
        let windows = NSApp.windows
        #if DEBUG
        print("[MenuBar] Available windows: \(windows.count)")
        for (index, window) in windows.enumerated() {
            print("[MenuBar]   Window \(index): \(window.className), level: \(window.level.rawValue), visible: \(window.isVisible)")
        }
        #endif

        // Find first window that is not a status bar popup
        let mainWindow = windows.first { window in
            !window.className.contains("NSStatusBar") &&
            !window.className.contains("PopUp") &&
            window.contentView != nil
        }
        #if DEBUG
        print("[MenuBar] Found main window: \(mainWindow?.className ?? "nil")")
        #endif
        return mainWindow
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else {
            #if DEBUG
            print("[MenuBar] statusItemClicked: no current event")
            #endif
            return
        }

        #if DEBUG
        print("[MenuBar] statusItemClicked: event type = \(event.type.rawValue)")
        #endif

        if event.type == .rightMouseUp {
            // Right click - show menu
            #if DEBUG
            print("[MenuBar] Right click - showing menu")
            #endif
            statusItem?.menu = contextMenu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            // Left click - toggle window
            #if DEBUG
            print("[MenuBar] Left click - toggling window")
            #endif
            toggleWindow()
        }
    }

    @objc private func toggleWindow() {
        #if DEBUG
        print("[MenuBar] toggleWindow called")
        #endif
        if let window = findMainWindow() {
            #if DEBUG
            print("[MenuBar] Window visible: \(window.isVisible)")
            #endif
            if window.isVisible {
                window.orderOut(nil)
                #if DEBUG
                print("[MenuBar] Window hidden")
                #endif
            } else {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                #if DEBUG
                print("[MenuBar] Window shown and activated")
                #endif
            }
        } else {
            #if DEBUG
            print("[MenuBar] ERROR: No main window found!")
            #endif
        }
    }

    @objc private func showWindow() {
        #if DEBUG
        print("[MenuBar] showWindow called")
        #endif
        if let window = findMainWindow() {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            #if DEBUG
            print("[MenuBar] Window shown and activated")
            #endif
        } else {
            #if DEBUG
            print("[MenuBar] ERROR: No main window found!")
            #endif
        }
    }

    @objc private func newMessage() {
        #if DEBUG
        print("[MenuBar] newMessage called")
        #endif
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
        
        // Update checkmark for "Filter Messages"
        filterMenuItem?.state = UserDefaults.standard.bool(forKey: "filterGroupsAndPages") ? .on : .off
    }
}
