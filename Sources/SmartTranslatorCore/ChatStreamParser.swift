import Foundation

public enum ChatStreamEvent: Equatable {
    case delta(String)
    case done
    case error(String)
    case ignored
}

/// Parses Server-Sent Events of the OpenAI-compatible `/chat/completions` stream.
public enum ChatStreamParser {
    public static func parse(line: String) -> ChatStreamEvent {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return .ignored }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .ignored }
        if let message = errorMessage(in: object) { return .error(message) }
        guard let choices = object["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String,
              !content.isEmpty
        else { return .ignored }
        return .delta(content)
    }

    /// Extracts a human-readable message from an error response body.
    public static func errorMessage(from body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) else {
            let text = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : String(text.prefix(300))
        }
        if let dictionary = object as? [String: Any] {
            return errorMessage(in: dictionary)
        }
        // Gemini sometimes wraps the error in an array.
        if let array = object as? [[String: Any]] {
            return array.lazy.compactMap(errorMessage(in:)).first
        }
        return nil
    }

    static func errorMessage(in object: [String: Any]) -> String? {
        if let error = object["error"] as? [String: Any] {
            return error["message"] as? String ?? "Unknown error"
        }
        return object["error"] as? String
    }
}

public enum ModelListParser {
    /// Parses `GET /models` (`{"data": [{"id": ...}]}`) into sorted model ids.
    public static func parse(_ data: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["data"] as? [[String: Any]]
        else { return [] }
        let ids = items
            .compactMap { $0["id"] as? String }
            .map { $0.hasPrefix("models/") ? String($0.dropFirst("models/".count)) : $0 }
        return Array(Set(ids)).sorted()
    }
}
