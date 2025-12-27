# Messenger for macOS

A lightweight native macOS wrapper for Facebook Messenger web, providing a seamless desktop experience with native notifications and system integration.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- **Native macOS App** - Clean wrapper using WKWebView, no Electron bloat
- **Smart Notifications** - Shows sender name and message preview in notifications
- **Filter Groups & Pages** - Option to filter out notifications from groups and pages
- **Menu Bar Icon** - Quick access with unread badge counter
- **Dock Badge** - Shows unread message count
- **Dark/Light Mode** - Automatically syncs with macOS appearance
- **Do Not Disturb** - Respects macOS Focus mode
- **Video Calls** - Popup windows for video/audio calls
- **File Uploads** - Native file picker for attachments
- **Downloads** - Save files with native save dialog
- **Window Position** - Remembers window size and position
- **Always on Top** - Optional floating window mode
- **Localization** - English and Czech language support

## Screenshots

*Coming soon*

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0+ (for building)

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

## Privacy

This app is just a wrapper around the official Messenger web interface. Your credentials and messages are handled directly by Facebook - this app does not collect, store, or transmit any of your data.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Disclaimer

This is an unofficial app and is not affiliated with, authorized, maintained, sponsored, or endorsed by Meta/Facebook or any of its affiliates or subsidiaries.
