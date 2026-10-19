import Foundation

public enum InputKind: String, Equatable {
    case word
    case phrase
    case text
}

public enum PromptBuilder {
    public static func kind(of text: String) -> InputKind {
        let words = text.split(whereSeparator: { $0.isWhitespace })
        if words.count <= 1 {
            // Scripts without spaces (Chinese, Japanese) put a whole sentence in one "word".
            return text.count > 12 ? .text : .word
        }
        return words.count <= 6 ? .phrase : .text
    }

    /// Language to translate into when the selection is already in the target language.
    public static func fallbackLanguage(for target: String) -> String {
        target.caseInsensitiveCompare("English") == .orderedSame ? "Russian" : "English"
    }

    public static func systemPrompt(targetLanguage target: String) -> String {
        let fallback = fallbackLanguage(for: target)
        return """
        You are a translation engine inside a macOS pop-up. Translate the user's selected text into \(target).

        Rules:
        - Translate meaning, not words. Idioms, phrasal verbs, collocations, slang and set phrases must become the natural equivalent in \(target), never a word-by-word calque (for example "break the ice", "call it a day", "give up").
        - If the selected text is already in \(target), translate it into \(fallback) instead.
        - The context, if given, is only for disambiguation. Translate only the selected text.
        - Output plain text with inline Markdown only (**bold**, _italic_). No headings, no code blocks, no preamble, no quotes around the answer. Write every label and explanation in the output language.

        Format by input type:
        - word: first line — the main translation(s) in bold, most common first, then the part of speech in italics. Up to two more lines for other common senses. Then one short example: original — translation.
        - phrase: first line — the meaning-based translation in bold. If a literal translation would differ noticeably, add a line "Literally: …" with the label in the output language. Optionally one line on usage or register.
        - text: the natural translation, keeping paragraphs. Then, only if the text contains idioms, phrasal verbs or non-obvious expressions, an empty line and up to five lines "• expression — meaning".
        """
    }

    public static func userMessage(for request: TranslationRequest) -> String {
        var message = """
        Input type: \(kind(of: request.text).rawValue)

        <selected>
        \(request.text)
        </selected>
        """
        let selected = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let context = request.context?.trimmingCharacters(in: .whitespacesAndNewlines),
           !context.isEmpty, context != selected {
            message += """


            <context>
            \(context)
            </context>
            """
        }
        return message
    }

    public static func messages(for request: TranslationRequest) -> [[String: String]] {
        [
            ["role": "system", "content": systemPrompt(targetLanguage: request.targetLanguage)],
            ["role": "user", "content": userMessage(for: request)],
        ]
    }
}
