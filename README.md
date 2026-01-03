# Messenger for macOS

A lightweight native macOS wrapper for Facebook Messenger. The goal is simple: provide a clean, native desktop experience for Messenger without the bloat of Electron-based apps.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Quick Alternative

If you just want Messenger as a standalone app without building anything:

1. Open [messenger.com](https://www.messenger.com) in **Google Chrome** (Safari doesn't support this)
2. Click the three dots menu (⋮) → **Save and Share** → **Install page as app...**
3. Done! Messenger will now open as a standalone app

**Limitations of Chrome PWA:** No dock badge for unread count, and native macOS notifications may not work reliably. This native app solves these issues with proper dock badge, menu bar icon, and notification filtering.

## Why?

- **Lightweight** - Uses native WKWebView instead of bundling an entire Chromium browser
- **Fast startup** - Launches instantly, no heavy framework to load
- **Low memory** - Uses significantly less RAM than Electron alternatives
- **Native integration** - Real macOS notifications, menu bar icon, dock badge

## Features

### Messaging
- **Native Notifications** - Shows sender name and message preview
- **Filter Groups & Pages** - Option to filter out notifications from groups and pages
- **Menu Bar Icon** - Quick access with unread badge counter
- **Dock Badge** - Shows unread message count
- **Dark/Light Mode** - Automatically syncs with macOS appearance
- **Do Not Disturb** - Respects macOS Focus mode
- **Facebook Links** - Shared reels and posts open in a popup window with shared login session

### Calls (Video & Audio)

> **Note:** Facebook/Meta blocks WebRTC in WKWebView, so video and audio calls cannot work directly in the app.

**Workaround:** When you're in a conversation, a floating button appears that opens the conversation in Chrome (or your default browser), where calls work normally.

- Floating call button in conversations
- "Accept in Chrome" button for incoming calls
- Configurable: Chrome or default browser (Menu Bar → right-click → "Open calls in Chrome")

### Files & Media
- **File Uploads** - Native file picker for attachments
- **Downloads** - Save files with native save dialog

### Window Management
- **Window Position** - Remembers window size and position
- **Always on Top** - Optional floating window mode
- **Hide to Menu Bar** - Close window, app keeps running

### Localization
- English and Czech language support

## Requirements

- macOS 13.0 (Ventura) or later
- Google Chrome (recommended for video/audio calls)
- Xcode 15.0+ (for building from source)

## Installation

### Download

Download the latest release from the [Releases](https://github.com/ACiDekCZ/messenger-macos/releases) page.

### Build from Source

```bash
# Clone the repository
git clone https://github.com/ACiDekCZ/messenger-macos.git
cd messenger-macos

# Open in Xcode
open Messenger.xcodeproj

# Or build from command line
xcodebuild -project Messenger.xcodeproj -scheme Messenger -configuration Release build
```

## Usage

1. Launch the app
2. Sign in to your Facebook/Messenger account
3. Allow notifications when prompted
4. The app will run in the background with a menu bar icon

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd + N` | New message |
| `Cmd + F` | Search |
| `Cmd + R` | Refresh |
| `Cmd + [` | Back |
| `Cmd + ]` | Forward |
| `Cmd + W` | Hide window |
| `Cmd + Shift + O` | Show window |
| `Cmd + Shift + T` | Toggle always on top |

### Menu Bar Options (Right-click)

- **Open Messenger** - Show the main window
- **New Message** - Start a new conversation
- **Always on Top** - Toggle floating window
- **Filter Groups & Pages** - Toggle notification filtering
- **Open calls in Chrome** - Toggle Chrome for calls (default: on)
- **Quit** - Exit the app

## Privacy

This app is just a wrapper around the official Messenger web interface. Your credentials and messages are handled directly by Facebook - this app does not collect, store, or transmit any of your data.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Disclaimer

This is an unofficial app and is not affiliated with, authorized, maintained, sponsored, or endorsed by Meta/Facebook or any of its affiliates or subsidiaries.
