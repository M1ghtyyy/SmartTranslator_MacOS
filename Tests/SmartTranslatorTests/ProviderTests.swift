import AppKit
import Foundation
import Testing
@testable import SmartTranslatorCore

struct OpenAICompatibleProviderTests {
    private let request = TranslationRequest(text: "break the ice", targetLanguage: "Russian")

    @Test func buildsStreamingChatRequest() throws {
        let provider = OpenAICompatibleProvider(config: ProviderConfig(
            baseURL: "https://generativelanguage.googleapis.com/v1beta/openai/",
            model: "gemini-flash-latest",
            apiKey: " secret ",
            extraBody: ["reasoning_effort": "low"]
        ))
        let urlRequest = try provider.makeChatRequest(for: request)

        #expect(urlRequest.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
        #expect(urlRequest.httpMethod == "POST")
        #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer secret")

        let body = try #require(urlRequest.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "gemini-flash-latest")
        #expect(json["stream"] as? Bool == true)
        #expect(json["reasoning_effort"] as? String == "low")
        #expect((json["messages"] as? [[String: String]])?.count == 2)
    }

    @Test func omitsAuthorizationWithoutKey() throws {
        let provider = OpenAICompatibleProvider(config: ProviderConfig(
            baseURL: "http://localhost:11434/v1",
            model: "qwen2.5:7b",
            apiKey: nil
        ))
        let urlRequest = try provider.makeChatRequest(for: request)
        #expect(urlRequest.url?.absoluteString == "http://localhost:11434/v1/chat/completions")
        #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func rejectsMissingModelAndBadURL() {
        let noModel = OpenAICompatibleProvider(config: ProviderConfig(baseURL: "https://api.groq.com/openai/v1", model: " ", apiKey: "k"))
        #expect(throws: TranslationError.missingModel) { try noModel.makeChatRequest(for: request) }

        let badURL = OpenAICompatibleProvider(config: ProviderConfig(baseURL: "not a url", model: "m", apiKey: "k"))
        #expect(throws: TranslationError.invalidBaseURL("not a url")) { try badURL.makeChatRequest(for: request) }
    }

    @Test func presetsHaveUniqueIDsAndValidURLs() {
        let ids = ProviderPresets.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for preset in ProviderPresets.all where !preset.baseURL.isEmpty {
            #expect(URL(string: preset.baseURL)?.host != nil, "\(preset.id)")
        }
        #expect(ProviderPresets.preset(id: "unknown").id == ProviderPresets.defaultID)
    }
}

struct ContextExtractorTests {
    @Test func returnsSentenceAroundSelection() {
        let text = "First sentence here. We're exhausted, so let's call it a day. Third one follows."
        let range = (text as NSString).range(of: "call it a day")
        #expect(ContextExtractor.surroundingText(in: text, selection: range) == "We're exhausted, so let's call it a day.")
    }

    @Test func returnsNilWhenSelectionIsWholeSentenceOrInvalid() {
        let text = "Break a leg!"
        #expect(ContextExtractor.surroundingText(in: text, selection: NSRange(location: 0, length: 12)) == nil)
        #expect(ContextExtractor.surroundingText(in: text, selection: NSRange(location: 5, length: 100)) == nil)
        #expect(ContextExtractor.surroundingText(in: text, selection: NSRange(location: 3, length: 0)) == nil)
    }
}

struct PasteboardSnapshotTests {
    @Test func restoresAllItemsAndTypes() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("SmartTranslatorTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        let first = NSPasteboardItem()
        first.setString("original", forType: .string)
        first.setString("<b>original</b>", forType: .html)
        let second = NSPasteboardItem()
        second.setString("second", forType: .string)
        pasteboard.clearContents()
        pasteboard.writeObjects([first, second])

        let snapshot = PasteboardSnapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("copied selection", forType: .string)
        snapshot.restore(to: pasteboard)

        let items = try #require(pasteboard.pasteboardItems)
        #expect(items.count == 2)
        #expect(items[0].string(forType: .string) == "original")
        #expect(items[0].string(forType: .html) == "<b>original</b>")
        #expect(items[1].string(forType: .string) == "second")
    }
}
