import Foundation

public struct ProviderPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let baseURL: String
    public let defaultModel: String
    public let requiresAPIKey: Bool
    public let keyURL: String?
    public let note: String
    /// Substring that model ids must contain to be offered in the model list.
    public let modelFilter: String?
    /// Extra JSON fields sent with every chat request.
    public let extraBody: [String: String]
}

/// OpenAI-compatible endpoints that have a free (or almost free) tier.
public enum ProviderPresets {
    public static let gemini = ProviderPreset(
        id: "gemini",
        name: "Google Gemini (free)",
        baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
        defaultModel: "gemini-flash-latest",
        requiresAPIKey: true,
        keyURL: "https://aistudio.google.com/apikey",
        note: "Free tier with a daily request limit. May be unavailable in some regions.",
        modelFilter: "gemini",
        extraBody: ["reasoning_effort": "low"]
    )

    public static let openRouter = ProviderPreset(
        id: "openrouter",
        name: "OpenRouter (free :free models)",
        baseURL: "https://openrouter.ai/api/v1",
        defaultModel: "",
        requiresAPIKey: true,
        keyURL: "https://openrouter.ai/keys",
        note: "Click Load Models and pick a model ending in :free. Without credits — about 50 requests a day.",
        modelFilter: ":free",
        extraBody: [:]
    )

    public static let groq = ProviderPreset(
        id: "groq",
        name: "Groq (free tier)",
        baseURL: "https://api.groq.com/openai/v1",
        defaultModel: "llama-3.3-70b-versatile",
        requiresAPIKey: true,
        keyURL: "https://console.groq.com/keys",
        note: "Very fast responses. Free tier with per-minute and daily limits.",
        modelFilter: nil,
        extraBody: [:]
    )

    public static let deepSeek = ProviderPreset(
        id: "deepseek",
        name: "DeepSeek (paid, very cheap)",
        baseURL: "https://api.deepseek.com/v1",
        defaultModel: "deepseek-chat",
        requiresAPIKey: true,
        keyURL: "https://platform.deepseek.com/api_keys",
        note: "Not free, but a translation costs a fraction of a cent. Requires a top-up.",
        modelFilter: nil,
        extraBody: [:]
    )

    public static let ollama = ProviderPreset(
        id: "ollama",
        name: "Ollama (local, offline)",
        baseURL: "http://localhost:11434/v1",
        defaultModel: "qwen2.5:7b",
        requiresAPIKey: false,
        keyURL: nil,
        note: "Completely free and offline. Install: brew install ollama, then ollama pull qwen2.5:7b.",
        modelFilter: nil,
        extraBody: [:]
    )

    public static let custom = ProviderPreset(
        id: "custom",
        name: "Custom OpenAI-compatible API",
        baseURL: "",
        defaultModel: "",
        requiresAPIKey: false,
        keyURL: nil,
        note: "Any service with an OpenAI-compatible /chat/completions endpoint.",
        modelFilter: nil,
        extraBody: [:]
    )

    public static let all: [ProviderPreset] = [gemini, openRouter, groq, deepSeek, ollama, custom]
    public static let defaultID = gemini.id

    public static func preset(id: String) -> ProviderPreset {
        all.first { $0.id == id } ?? gemini
    }
}
