import AppKit
import Combine

class WindowManager: ObservableObject {
    static let shared = WindowManager()

    private let floatingKey = "windowFloating"

    @Published var isFloating: Bool {
        didSet {
            UserDefaults.standard.set(isFloating, forKey: floatingKey)
            updateWindowLevel()
        }
    }

    private init() {
        self.isFloating = UserDefaults.standard.bool(forKey: floatingKey)
    }

    func toggleFloating() {
        isFloating.toggle()
    }

    private func updateWindowLevel() {
        guard let window = NSApp.windows.first(where: { !$0.className.contains("NSStatusBar") }) else { return }

        if isFloating {
            window.level = .floating
        } else {
            window.level = .normal
        }
    }

    func applyInitialSettings() {
        // Apply settings at startup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.updateWindowLevel()
        }
    }
}
