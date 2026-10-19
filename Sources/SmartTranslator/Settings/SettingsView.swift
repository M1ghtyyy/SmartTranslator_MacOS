import AppKit
import SmartTranslatorCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView())
            controller.sizingOptions = []
            let window = NSWindow(contentViewController: controller)
            window.title = "SmartTranslator Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 580, height: 720))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var apiKey = ""
    @State private var models: [String] = []
    @State private var modelsError: String?
    @State private var isLoadingModels = false
    @State private var testResult = ""
    @State private var isTesting = false
    @State private var accessibilityGranted = Permissions.accessibilityGranted

    private let permissionTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Translation") {
                Picker("Translate into", selection: $settings.targetLanguage) {
                    ForEach(LanguageOption.all) { Text($0.title).tag($0.id) }
                }
            }

            Section("Model") {
                Picker("Provider", selection: $settings.presetID) {
                    ForEach(ProviderPresets.all) { Text($0.name).tag($0.id) }
                }
                Text(settings.preset.note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if settings.preset.requiresAPIKey || settings.preset.id == ProviderPresets.custom.id {
                    SecureField("API key", text: $apiKey)
                        .onChange(of: apiKey) { _, newValue in settings.apiKey = newValue }
                    if let keyURL = settings.preset.keyURL, let url = URL(string: keyURL) {
                        Link("Get a key →", destination: url)
                    }
                }
                TextField("API base URL", text: $settings.baseURL)
                HStack {
                    TextField("Model", text: $settings.model)
                    if !models.isEmpty {
                        Menu("Choose") {
                            ForEach(models, id: \.self) { model in
                                Button(model) { settings.model = model }
                            }
                        }
                        .fixedSize()
                    }
                    Button(isLoadingModels ? "Loading…" : "Load Models", action: loadModels)
                        .disabled(isLoadingModels)
                }
                if let modelsError {
                    Text(modelsError).font(.callout).foregroundStyle(.red)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Button(isTesting ? "Testing…" : "Test Translation", action: runTest)
                        .disabled(isTesting)
                    if !testResult.isEmpty {
                        Text(TranslationView.render(testResult))
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                }
            }

            Section("Triggers") {
                Toggle("Force Click on selected text", isOn: $settings.forceClickEnabled)
                Toggle("Suppress the system dictionary on Force Click (experimental)", isOn: $settings.suppressLookUp)
                Picker("Hotkey", selection: $settings.hotkeyID) {
                    Text("Off").tag(Hotkey.offID)
                    ForEach(Hotkey.all) { Text($0.title).tag($0.id) }
                }
                Text("Also: right-click the selection → Services → Translate with SmartTranslator.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                LabeledContent("Accessibility") {
                    if accessibilityGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Open System Settings") {
                            Permissions.requestAccessibility()
                            Permissions.openAccessibilitySettings()
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("To keep the system dictionary from opening over the translation: System Settings → Trackpad → Point & Click → Look up & data detectors → Tap with Three Fingers. Force Click then translates, and the dictionary stays on the three-finger tap.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Open Trackpad Settings", action: Permissions.openTrackpadSettings)
                }
            }

            Section("Diagnostics") {
                Toggle("Verbose logging", isOn: $settings.diagnostics)
                Button("Open Log") { DiagnosticsLog.shared.reveal() }
            }
        }
        .formStyle(.grouped)
        .onAppear { apiKey = settings.apiKey ?? "" }
        .onChange(of: settings.presetID) { _, _ in
            apiKey = settings.apiKey ?? ""
            models = []
            modelsError = nil
            testResult = ""
        }
        .onReceive(permissionTimer) { _ in
            accessibilityGranted = Permissions.accessibilityGranted
        }
    }

    private func loadModels() {
        isLoadingModels = true
        modelsError = nil
        let provider = OpenAICompatibleProvider(config: settings.providerConfig())
        let filter = settings.preset.modelFilter
        Task {
            do {
                var list = try await provider.listModels()
                if let filter {
                    list = list.filter { $0.contains(filter) }
                }
                models = list
                if list.isEmpty { modelsError = "The model list is empty." }
            } catch {
                modelsError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isLoadingModels = false
        }
    }

    private func runTest() {
        isTesting = true
        testResult = ""
        let provider = OpenAICompatibleProvider(config: settings.providerConfig())
        let request = TranslationRequest(
            text: "Let's call it a day — I can't see the wood for the trees anymore.",
            targetLanguage: settings.targetLanguage
        )
        Task {
            do {
                for try await chunk in provider.stream(request) {
                    testResult += chunk
                }
            } catch {
                testResult = "⚠️ " + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
            isTesting = false
        }
    }
}
