import SwiftUI

struct ContentView: View {
    @ObservedObject private var webViewStore = WebViewStore.shared

    var body: some View {
        ZStack {
            WebView()
                .frame(minWidth: 400, minHeight: 600)

            // Back button (top-left) - shown when on external FB page
            if webViewStore.isOnExternalPage {
                VStack {
                    HStack {
                        BackButton {
                            webViewStore.goBack()
                        }
                        .padding(.top, 60)
                        .padding(.leading, 16)
                        Spacer()
                    }
                    Spacer()
                }
            }

            // Call buttons (top-right)
            VStack {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        // Accept incoming call button (green, prominent)
                        if webViewStore.hasIncomingCall {
                            AcceptCallButton {
                                webViewStore.acceptCallInChrome()
                            }
                        }

                        // Open in Chrome button (when in conversation)
                        if webViewStore.isInConversation {
                            CallButton {
                                webViewStore.openInChrome()
                            }
                        }
                    }
                    .padding(.top, 60)
                    .padding(.trailing, 16)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Call Button (Video icon)

struct CallButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "video.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Color.blue)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .help(String(localized: "call.openInChrome"))
    }
}

// MARK: - Accept Call Button (Green, prominent)

struct AcceptCallButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(String(localized: "call.accept"))
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.green)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .help(String(localized: "call.acceptInChrome"))
    }
}

// MARK: - Back Button (for returning from external pages)

struct BackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                Text(String(localized: "menu.back"))
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.8))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .help(String(localized: "menu.back"))
    }
}
