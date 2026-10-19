import Foundation

public struct ProviderConfig: Sendable, Equatable {
    public var baseURL: String
    public var model: String
    public var apiKey: String?
    public var extraBody: [String: String]

    public init(baseURL: String, model: String, apiKey: String?, extraBody: [String: String] = [:]) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.extraBody = extraBody
    }
}

/// Streams translations from any OpenAI-compatible `/chat/completions` endpoint
/// (Gemini, OpenRouter, Groq, DeepSeek, Ollama…).
public struct OpenAICompatibleProvider: TranslationProvider {
    /// Overloaded or briefly unavailable upstream (e.g. Gemini "high demand" 503).
    static let retryableStatuses: Set<Int> = [500, 502, 503, 504, 529]
    static let maxRetries = 2

    public let config: ProviderConfig
    public var temperature = 0.2
    // Generous because reasoning models count thinking tokens against this limit.
    public var maxTokens = 2048

    public init(config: ProviderConfig) {
        self.config = config
    }

    public func makeChatRequest(for request: TranslationRequest) throws -> URLRequest {
        guard !config.model.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw TranslationError.missingModel
        }
        var body: [String: Any] = [
            "model": config.model,
            "messages": PromptBuilder.messages(for: request),
            "stream": true,
            "temperature": temperature,
            "max_tokens": maxTokens,
        ]
        for (key, value) in config.extraBody {
            body[key] = value
        }
        var urlRequest = URLRequest(url: try endpoint("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 60
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        authorize(&urlRequest)
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    public func stream(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try makeChatRequest(for: request)
                    var (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    var status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    var attempt = 0
                    while Self.retryableStatuses.contains(status) && attempt < Self.maxRetries {
                        attempt += 1
                        try await Task.sleep(nanoseconds: UInt64(attempt) * 800_000_000)
                        (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                        status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    }
                    guard (200..<300).contains(status) else {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count > 64_000 { break }
                        }
                        throw TranslationError.http(status: status, message: ChatStreamParser.errorMessage(from: body))
                    }
                    var receivedText = false
                    lines: for try await line in bytes.lines {
                        switch ChatStreamParser.parse(line: line) {
                        case .delta(let text):
                            receivedText = true
                            continuation.yield(text)
                        case .done:
                            break lines
                        case .error(let message):
                            throw TranslationError.http(status: status, message: message)
                        case .ignored:
                            continue
                        }
                    }
                    if !receivedText { throw TranslationError.emptyResponse }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func listModels() async throws -> [String] {
        var urlRequest = URLRequest(url: try endpoint("models"))
        urlRequest.timeoutInterval = 20
        authorize(&urlRequest)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw TranslationError.http(status: status, message: ChatStreamParser.errorMessage(from: data))
        }
        return ModelListParser.parse(data)
    }

    private func endpoint(_ path: String) throws -> URL {
        var base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: "\(base)/\(path)"),
              let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil
        else { throw TranslationError.invalidBaseURL(config.baseURL) }
        return url
    }

    private func authorize(_ request: inout URLRequest) {
        if let key = config.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        // Optional attribution headers used by OpenRouter; ignored elsewhere.
        request.setValue("SmartTranslator", forHTTPHeaderField: "X-Title")
    }
}
