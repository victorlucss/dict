import Foundation
import Testing
@testable import DictCore

@Suite("LLM response parsing")
struct LLMParsingTests {
    // MARK: - OpenAI

    @Test func validOpenAIResponse() {
        let json = """
        {
            "choices": [{
                "message": {"role": "assistant", "content": "Hello world"}
            }]
        }
        """
        #expect(parseOpenAIResponse(Data(json.utf8)) == "Hello world")
    }

    @Test func openAIWhitespaceContent() {
        let json = """
        {"choices": [{"message": {"content": "  trimmed  "}}]}
        """
        #expect(parseOpenAIResponse(Data(json.utf8)) == "trimmed")
    }

    @Test func openAIEmptyChoices() {
        let json = """
        {"choices": []}
        """
        #expect(parseOpenAIResponse(Data(json.utf8)) == nil)
    }

    @Test func openAIMissingFields() {
        let json = """
        {"choices": [{"index": 0}]}
        """
        #expect(parseOpenAIResponse(Data(json.utf8)) == nil)
    }

    @Test func openAIMalformedJSON() {
        #expect(parseOpenAIResponse(Data("not json".utf8)) == nil)
    }

    // MARK: - Anthropic

    @Test func validAnthropicResponse() {
        let json = """
        {
            "content": [{
                "type": "text",
                "text": "Hello world"
            }]
        }
        """
        #expect(parseAnthropicResponse(Data(json.utf8)) == "Hello world")
    }

    @Test func anthropicWhitespaceContent() {
        let json = """
        {"content": [{"type": "text", "text": "  trimmed  "}]}
        """
        #expect(parseAnthropicResponse(Data(json.utf8)) == "trimmed")
    }

    @Test func anthropicEmptyContent() {
        let json = """
        {"content": []}
        """
        #expect(parseAnthropicResponse(Data(json.utf8)) == nil)
    }

    @Test func anthropicMissingFields() {
        let json = """
        {"content": [{"type": "text"}]}
        """
        #expect(parseAnthropicResponse(Data(json.utf8)) == nil)
    }

    @Test func anthropicMalformedJSON() {
        #expect(parseAnthropicResponse(Data("{bad".utf8)) == nil)
    }
}
