import AppKit
import Combine
import SmartTranslatorCore

/// Trigger → read selection → stream translation into the panel.
@MainActor
final class AppCoordinator {
    private static let maxLength = 6000

    let servicesProvider = ServicesProvider()
    private let settings = AppSettings.shared
    private let forceClickMonitor = ForceClickMonitor()
    private let hotkeyMonitor = HotkeyMonitor()
    private let panel = TranslationPanelController()
    private let settingsWindow = SettingsWindowController()
    private var translationTask: Task<Void, Never>?
    private var settingsObserver: AnyCancellable?
    private var permissionTimer: Timer?

    func start() {
        forceClickMonitor.onForceClick = { [weak self] point in
            Task { @MainActor in self?.handleForceClick(at: point) }
        }
        hotkeyMonitor.onHotkey = { [weak self] in
            Task { @MainActor in self?.translateCurrentSelection() }
        }
        servicesProvider.onText = { [weak self] text in
            Task { @MainActor in self?.translate(text, context: nil, near: NSEvent.mouseLocation) }
        }
        panel.onOpenSettings = { [weak self] in self?.showSettings() }
        panel.onClose = { [weak self] in self?.translationTask?.cancel() }

        // objectWillChange fires before the new value is stored, so apply on the next turn.
        settingsObserver = settings.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.applySettings() }
        }
        applySettings()
        if !Permissions.accessibilityGranted {
            waitForAccessibility()
        }
    }

    func showSettings() {
        settingsWindow.show()
    }

    func handle(url: URL) {
        guard url.scheme == "smarttranslator", url.host == "translate",
              let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "text" })?.value
        else {
            DiagnosticsLog.shared.log("Unknown URL: \(url.absoluteString)", force: true)
            return
        }
        translate(text, context: nil, near: NSEvent.mouseLocation)
    }

    func translateCurrentSelection() {
        let point = NSEvent.mouseLocation
        guard Permissions.accessibilityGranted else {
            panel.showMessage("SmartTranslator needs Accessibility access to read the selected text.", near: point)
            Permissions.requestAccessibility()
            return
        }
        Task {
            guard let selection = await SelectionReader.read(trigger: .explicit) else {
                panel.showMessage("Couldn't get the selected text. Select some text and try again.", near: point)
                return
            }
            translate(selection.text, context: selection.context, near: point, selectionBounds: selection.bounds)
        }
    }

    private func handleForceClick(at point: CGPoint) {
        // A force click on the panel itself (e.g. on translated text) is not a new request.
        if panel.isShown && panel.frame.contains(point) { return }
        Task {
            guard let selection = await SelectionReader.read(trigger: .forceClick(point)) else {
                DiagnosticsLog.shared.log("Force click: no selected text found", force: true)
                return
            }
            translate(selection.text, context: selection.context, near: point, selectionBounds: selection.bounds)
        }
    }

    private func translate(_ rawText: String, context: String?, near point: CGPoint, selectionBounds: NSRect? = nil) {
        translationTask?.cancel()
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let limited = text.count > Self.maxLength ? String(text.prefix(Self.maxLength)) : text

        let preset = settings.preset
        let model = panel.model
        let width: CGFloat = PromptBuilder.kind(of: limited) == .text ? 420 : 340
        model.reset(source: limited, footer: "\(preset.name) · \(settings.model)", width: width)
        panel.show(near: point, selectionBounds: selectionBounds)

        let config = settings.providerConfig()
        if preset.requiresAPIKey && (config.apiKey ?? "").isEmpty {
            model.error = TranslationError.missingAPIKey(provider: preset.name).errorDescription
            return
        }

        let provider = OpenAICompatibleProvider(config: config)
        let request = TranslationRequest(text: limited, context: context, targetLanguage: settings.targetLanguage)
        DiagnosticsLog.shared.log("Translation requested (\(limited.count) chars)")
        translationTask = Task {
            let started = Date()
            do {
                for try await chunk in provider.stream(request) {
                    if model.text.isEmpty {
                        DiagnosticsLog.shared.log(String(format: "First chunk after %.1f s", Date().timeIntervalSince(started)))
                    }
                    model.text += chunk
                }
                // A cancelled task ends the stream quietly instead of throwing.
                guard !Task.isCancelled else {
                    DiagnosticsLog.shared.log("Translation cancelled")
                    return
                }
                DiagnosticsLog.shared.log(String(format: "Translation finished in %.1f s (%d chars)", Date().timeIntervalSince(started), model.text.count))
                if limited.count < text.count {
                    model.footer += " · translated the first \(Self.maxLength) characters"
                }
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                DiagnosticsLog.shared.log("Translation failed: \(error)", force: true)
                model.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func applySettings() {
        DiagnosticsLog.shared.enabled = settings.diagnostics
        hotkeyMonitor.register(Hotkey.byID(settings.hotkeyID))
        forceClickMonitor.suppressLookUp = settings.suppressLookUp
        if settings.forceClickEnabled && Permissions.accessibilityGranted {
            forceClickMonitor.start(diagnostic: settings.diagnostics)
        } else {
            forceClickMonitor.stop()
        }
    }

    private func waitForAccessibility() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard Permissions.accessibilityGranted else { return }
            timer.invalidate()
            Task { @MainActor in self?.applySettings() }
        }
    }
}
