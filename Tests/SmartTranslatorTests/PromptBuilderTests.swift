import Foundation
import Testing
@testable import SmartTranslatorCore

struct PromptBuilderTests {
    @Test func classifiesInputKind() {
        #expect(PromptBuilder.kind(of: "ice") == .word)
        #expect(PromptBuilder.kind(of: "  give up ") == .phrase)
        #expect(PromptBuilder.kind(of: "break the ice") == .phrase)
        #expect(PromptBuilder.kind(of: "It's raining cats and dogs, so I'll call it a day.") == .text)
        #expect(PromptBuilder.kind(of: "猫") == .word)
        #expect(PromptBuilder.kind(of: "今日はとても良い天気ですね、散歩に行きましょう") == .text)
    }

    @Test func systemPromptNamesTargetAndFallback() {
        let russian = PromptBuilder.systemPrompt(targetLanguage: "Russian")
        #expect(russian.contains("into Russian"))
        #expect(russian.contains("translate it into English instead"))

        let english = PromptBuilder.systemPrompt(targetLanguage: "English")
        #expect(english.contains("translate it into Russian instead"))
    }

    @Test func userMessageIncludesContextOnlyWhenItAddsSomething() {
        let withContext = PromptBuilder.userMessage(for: TranslationRequest(
            text: "call it a day",
            context: "We're tired, let's call it a day.",
            targetLanguage: "Russian"
        ))
        #expect(withContext.contains("Input type: phrase"))
        #expect(withContext.contains("<selected>\ncall it a day\n</selected>"))
        #expect(withContext.contains("<context>\nWe're tired, let's call it a day.\n</context>"))

        let sameAsSelection = PromptBuilder.userMessage(for: TranslationRequest(
            text: "call it a day",
            context: " call it a day ",
            targetLanguage: "Russian"
        ))
        #expect(!sameAsSelection.contains("<context>"))
    }

    @Test func messagesAreSystemThenUser() {
        let messages = PromptBuilder.messages(for: TranslationRequest(text: "ice", targetLanguage: "Russian"))
        #expect(messages.map { $0["role"] } == ["system", "user"])
    }
}
