import WebKit
import AppKit

class DownloadManager: NSObject {
    static let shared = DownloadManager()

    private var activeDownloads: [WKDownload: URL] = [:]

    private override init() {
        super.init()
    }

    func startDownload(_ download: WKDownload) {
        download.delegate = self
    }
}

extension DownloadManager: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        // Show save dialog
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = suggestedFilename
        savePanel.canCreateDirectories = true

        // Set default folder to Downloads
        if let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            savePanel.directoryURL = downloadsURL
        }

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                self.activeDownloads[download] = url
                completionHandler(url)
            } else {
                completionHandler(nil)
            }
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = activeDownloads.removeValue(forKey: download) else { return }

        // Completion notification
        NotificationManager.shared.showNotification(
            title: String(localized: "download.complete"),
            body: url.lastPathComponent
        )

        // Bounce in Dock
        NSApp.requestUserAttention(.informationalRequest)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        activeDownloads.removeValue(forKey: download)

        NotificationManager.shared.showNotification(
            title: String(localized: "download.failed"),
            body: error.localizedDescription
        )
    }
}
