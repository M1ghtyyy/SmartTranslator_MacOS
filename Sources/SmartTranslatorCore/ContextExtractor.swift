import Foundation

public enum ContextExtractor {
    /// Returns the sentence(s) around `selection` (UTF-16 range, as Accessibility reports it),
    /// or nil when there is no context beyond the selection itself.
    public static func surroundingText(in fullText: String, selection: NSRange, radius: Int = 300) -> String? {
        let text = fullText as NSString
        guard selection.location != NSNotFound, selection.length > 0, NSMaxRange(selection) <= text.length else {
            return nil
        }
        let start = max(0, selection.location - radius)
        let end = min(text.length, NSMaxRange(selection) + radius)
        let window = NSRange(location: start, length: end - start)

        var covered: NSRange?
        text.enumerateSubstrings(in: window, options: [.bySentences, .substringNotRequired]) { _, range, enclosingRange, _ in
            guard NSIntersectionRange(enclosingRange, selection).length > 0 else { return }
            covered = covered.map { NSUnionRange($0, range) } ?? range
        }
        guard let covered else { return nil }

        let context = text.substring(with: covered).trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = text.substring(with: selection).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !context.isEmpty, context != selected else { return nil }
        return context
    }
}
