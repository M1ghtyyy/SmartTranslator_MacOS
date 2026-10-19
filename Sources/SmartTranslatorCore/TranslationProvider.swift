import Foundation

public struct TranslationRequest: Sendable, Equatable {
    public var text: String
    /// Surrounding text used only to disambiguate the selection.
    public var context: String?
    /// Target language name in English, e.g. "Russian".
    public var targetLanguage: String

    public init(text: String, context: String? = nil, targetLanguage: String) {
        self.text = text
        self.context = context
        self.targetLanguage = targetLanguage
    }
}

public protocol TranslationProvider: Sendable {
    func stream(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error>
}

public enum TranslationError: LocalizedError, Equatable {
    case missingAPIKey(provider: String)
    case missingModel
    case invalidBaseURL(String)
    case http(status: Int, message: String?)
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "No API key for \(provider). Add one in Settings."
        case .missingModel:
            return "No model selected. Open Settings and click Load Models."
        case .invalidBaseURL(let url):
            return "Invalid API base URL: \(url)"
        case .http(let status, let message):
            let hint: String
            switch status {
            case 401, 403: hint = "The API key was rejected, or the service isn't available in your region."
            case 404: hint = "Model or API URL not found — check them in Settings."
            case 429: hint = "Free request limit reached. Wait a bit or switch to another provider."
            case 500...599: hint = "The service is temporarily unavailable. Try again."
            default: hint = "Request failed (status \(status))."
            }
            guard let message, !message.isEmpty else { return hint }
            return "\(hint)\n\(message)"
        case .emptyResponse:
            return "The model returned an empty response."
        }
    }
}
