import AppKit

@main
enum SmartTranslatorMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let coordinator = AppCoordinator()
    private var statusItem: NSStatusItem?
    private lazy var permissionItem = NSMenuItem(
        title: "⚠️ Grant Accessibility Access…",
        action: #selector(openPermissions),
        keyEquivalent: ""
    )
    private lazy var diagnosticsItem = NSMenuItem(
        title: "Verbose Logging",
        action: #selector(toggleDiagnostics),
        keyEquivalent: ""
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
        NSApp.servicesProvider = coordinator.servicesProvider
        NSUpdateDynamicServices()
        setUpStatusItem()
        if !Permissions.accessibilityGranted {
            coordinator.showSettings()
            Permissions.requestAccessibility()
        }
    }

    /// smarttranslator://translate?text=… — for Shortcuts, Raycast, Alfred and scripts.
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(coordinator.handle(url:))
    }

    func menuWillOpen(_ menu: NSMenu) {
        permissionItem.isHidden = Permissions.accessibilityGranted
        diagnosticsItem.state = AppSettings.shared.diagnostics ? .on : .off
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "translate", accessibilityDescription: "SmartTranslator")

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Translate Selection", action: #selector(translateSelection), keyEquivalent: "")
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Open Log", action: #selector(openLog), keyEquivalent: "")
        menu.addItem(diagnosticsItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit SmartTranslator", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for menuItem in menu.items where menuItem.action != #selector(NSApplication.terminate(_:)) {
            menuItem.target = self
        }
        item.menu = menu
        statusItem = item
    }

    @objc private func translateSelection() {
        coordinator.translateCurrentSelection()
    }

    @objc private func openSettings() {
        coordinator.showSettings()
    }

    @objc private func openPermissions() {
        Permissions.requestAccessibility()
        Permissions.openAccessibilitySettings()
    }

    @objc private func openLog() {
        DiagnosticsLog.shared.reveal()
    }

    @objc private func toggleDiagnostics() {
        AppSettings.shared.diagnostics.toggle()
    }
}
