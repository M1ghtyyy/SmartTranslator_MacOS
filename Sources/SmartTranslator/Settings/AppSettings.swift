import Foundation
import SmartTranslatorCore

struct LanguageOption: Identifiable, Hashable {
    /// English name, used in the prompt.
    let id: String
    let title: String

    static let all: [LanguageOption] = [
        LanguageOption(id: "Russian", title: "Русский"),
        LanguageOption(id: "English", title: "English"),
        LanguageOption(id: "Ukrainian", title: "Українська"),
        LanguageOption(id: "German", title: "Deutsch"),
        LanguageOption(id: "French", title: "Français"),
        LanguageOption(id: "Spanish", title: "Español"),
        LanguageOption(id: "Italian", title: "Italiano"),
        LanguageOption(id: "Portuguese", title: "Português"),
        LanguageOption(id: "Polish", title: "Polski"),
        LanguageOption(id: "Turkish", title: "Türkçe"),
        LanguageOption(id: "Chinese (Simplified)", title: "中文"),
        LanguageOption(id: "Japanese", title: "日本語"),
        LanguageOption(id: "Korean", title: "한국어"),
    ]
}

/// User settings in UserDefaults; API keys live in the Keychain, one per provider preset.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let targetLanguage = "targetLanguage"
        static let presetID = "presetID"
        static let hotkeyID = "hotkeyID"
        static let forceClickEnabled = "forceClickEnabled"
        static let suppressLookUp = "suppressLookUp"
        static let diagnostics = "diagnostics"
        static func model(_ presetID: String) -> String { "model.\(presetID)" }
        static func baseURL(_ presetID: String) -> String { "baseURL.\(presetID)" }
    }

    private let defaults = UserDefaults.standard

    @Published var targetLanguage: String {
        didSet { defaults.set(targetLanguage, forKey: Keys.targetLanguage) }
    }
    @Published var presetID: String {
        didSet {
            defaults.set(presetID, forKey: Keys.presetID)
            loadPresetValues()
        }
    }
    @Published var model: String {
        didSet { store(model, forKey: Keys.model(presetID), default: preset.defaultModel) }
    }
    @Published var baseURL: String {
        didSet { store(baseURL, forKey: Keys.baseURL(presetID), default: preset.baseURL) }
    }
    @Published var hotkeyID: String {
        didSet { defaults.set(hotkeyID, forKey: Keys.hotkeyID) }
    }
    @Published var forceClickEnabled: Bool {
        didSet { defaults.set(forceClickEnabled, forKey: Keys.forceClickEnabled) }
    }
    @Published var suppressLookUp: Bool {
        didSet { defaults.set(suppressLookUp, forKey: Keys.suppressLookUp) }
    }
    @Published var diagnostics: Bool {
        didSet { defaults.set(diagnostics, forKey: Keys.diagnostics) }
    }

    var preset: ProviderPreset { ProviderPresets.preset(id: presetID) }

    var apiKey: String? {
        get { KeychainStore.get(account: presetID) }
        set { KeychainStore.set(newValue, account: presetID) }
    }

    func providerConfig() -> ProviderConfig {
        ProviderConfig(baseURL: baseURL, model: model, apiKey: apiKey, extraBody: preset.extraBody)
    }

    private init() {
        let preset = ProviderPresets.preset(id: defaults.string(forKey: Keys.presetID) ?? ProviderPresets.defaultID)
        targetLanguage = defaults.string(forKey: Keys.targetLanguage) ?? "Russian"
        presetID = preset.id
        model = defaults.string(forKey: Keys.model(preset.id)) ?? preset.defaultModel
        baseURL = defaults.string(forKey: Keys.baseURL(preset.id)) ?? preset.baseURL
        hotkeyID = defaults.string(forKey: Keys.hotkeyID) ?? Hotkey.defaultID
        forceClickEnabled = defaults.object(forKey: Keys.forceClickEnabled) as? Bool ?? true
        suppressLookUp = defaults.bool(forKey: Keys.suppressLookUp)
        diagnostics = defaults.bool(forKey: Keys.diagnostics)
    }

    private func loadPresetValues() {
        model = defaults.string(forKey: Keys.model(presetID)) ?? preset.defaultModel
        baseURL = defaults.string(forKey: Keys.baseURL(presetID)) ?? preset.baseURL
    }

    /// Stores only values that differ from the preset, so updated defaults reach existing users.
    private func store(_ value: String, forKey key: String, default defaultValue: String) {
        if value == defaultValue {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(value, forKey: key)
        }
    }
}
