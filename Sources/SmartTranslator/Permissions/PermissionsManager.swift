import AppKit
import ApplicationServices

enum Permissions {
    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that adds the app to Privacy → Accessibility.
    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openTrackpadSettings() {
        open("x-apple.systempreferences:com.apple.Trackpad-Settings.extension")
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
