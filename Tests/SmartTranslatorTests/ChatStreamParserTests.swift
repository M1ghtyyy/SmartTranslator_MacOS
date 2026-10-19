import Foundation
import Testing
@testable import SmartTranslatorCore

struct ChatStreamParserTests {
    @Test func parsesContentDelta() {
        let line = #"data: {"choices":[{"index":0,"delta":{"content":"Привет"}}]}"#
        #expect(ChatStreamParser.parse(line: line) == .delta("Привет"))
    }

    @Test func parsesDoneMarker() {
        #expect(ChatStreamParser.parse(line: "data: [DONE]") == .done)
    }

    @Test func ignoresRoleOnlyDeltasCommentsAndBlankLines() {
        #expect(ChatStreamParser.parse(line: #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#) == .ignored)
        #expect(ChatStreamParser.parse(line: #"data: {"choices":[{"delta":{"content":""}}]}"#) == .ignored)
        #expect(ChatStreamParser.parse(line: ": OPENROUTER PROCESSING") == .ignored)
        #expect(ChatStreamParser.parse(line: "") == .ignored)
    }

    @Test func parsesInStreamError() {
        let line = #"data: {"error":{"message":"Rate limit exceeded","code":429}}"#
        #expect(ChatStreamParser.parse(line: line) == .error("Rate limit exceeded"))
    }

    @Test func extractsErrorMessageFromBodies() {
        let openAI = Data(#"{"error":{"message":"Invalid API key","type":"invalid_request_error"}}"#.utf8)
        #expect(ChatStreamParser.errorMessage(from: openAI) == "Invalid API key")

        let gemini = Data(#"[{"error":{"code":429,"message":"Quota exceeded","status":"RESOURCE_EXHAUSTED"}}]"#.utf8)
        #expect(ChatStreamParser.errorMessage(from: gemini) == "Quota exceeded")

        let ollama = Data(#"{"error":"model \"qwen\" not found"}"#.utf8)
        #expect(ChatStreamParser.errorMessage(from: ollama) == #"model "qwen" not found"#)

        #expect(ChatStreamParser.errorMessage(from: Data("Bad Gateway".utf8)) == "Bad Gateway")
        #expect(ChatStreamParser.errorMessage(from: Data()) == nil)
    }

    @Test func parsesModelListAndStripsGeminiPrefix() {
        let body = Data(#"{"object":"list","data":[{"id":"models/gemini-flash-latest"},{"id":"llama:free"},{"id":"llama:free"}]}"#.utf8)
        #expect(ModelListParser.parse(body) == ["gemini-flash-latest", "llama:free"])
    }
}
