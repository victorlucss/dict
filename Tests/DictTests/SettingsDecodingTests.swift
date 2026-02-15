import Foundation
import Testing
@testable import DictCore

@Suite("SettingsData decoding")
struct SettingsDecodingTests {
    @Test func fullValidJSON() throws {
        let json = """
        {
            "hotkeyMode": "toggle",
            "sttEngine": "whisper",
            "whisperModelPath": "/path/to/model",
            "whisperLanguage": "pt",
            "llmEnabled": true,
            "llmEndpoint": "https://api.example.com",
            "llmModel": "gpt-4",
            "llmApiKey": "sk-test",
            "llmProvider": "openai",
            "llmPrompt": "Fix this",
            "llmAccuracy": 5,
            "flowMode": true,
            "codeMode": true,
            "privacyMode": true,
            "verboseOverlay": true,
            "overlayPosition": "bottom",
            "onboardingDone": true
        }
        """
        let data = try JSONDecoder().decode(SettingsData.self, from: Data(json.utf8))
        #expect(data.hotkeyMode == .toggle)
        #expect(data.sttEngine == .whisper)
        #expect(data.whisperModelPath == "/path/to/model")
        #expect(data.whisperLanguage == "pt")
        #expect(data.llmEnabled == true)
        #expect(data.llmEndpoint == "https://api.example.com")
        #expect(data.llmModel == "gpt-4")
        #expect(data.llmApiKey == "sk-test")
        #expect(data.llmProvider == .openai)
        #expect(data.llmPrompt == "Fix this")
        #expect(data.llmAccuracy == 5)
        #expect(data.flowMode == true)
        #expect(data.codeMode == true)
        #expect(data.privacyMode == true)
        #expect(data.verboseOverlay == true)
        #expect(data.overlayPosition == .bottom)
        #expect(data.onboardingDone == true)
    }

    @Test func emptyJSONUsesDefaults() throws {
        let data = try JSONDecoder().decode(SettingsData.self, from: Data("{}".utf8))
        let defaults = SettingsData()
        #expect(data.hotkeyMode == defaults.hotkeyMode)
        #expect(data.sttEngine == defaults.sttEngine)
        #expect(data.llmEnabled == defaults.llmEnabled)
        #expect(data.llmProvider == defaults.llmProvider)
        #expect(data.overlayPosition == defaults.overlayPosition)
        #expect(data.onboardingDone == defaults.onboardingDone)
    }

    @Test func partialJSONDefaultsForMissing() throws {
        let json = """
        {"hotkeyMode": "toggle", "llmEnabled": true}
        """
        let data = try JSONDecoder().decode(SettingsData.self, from: Data(json.utf8))
        #expect(data.hotkeyMode == .toggle)
        #expect(data.llmEnabled == true)
        // Missing fields get defaults
        #expect(data.sttEngine == .apple)
        #expect(data.llmProvider == .ollama)
        #expect(data.overlayPosition == .top)
    }

    @Test func invalidEnumFallsBackToDefault() throws {
        let json = """
        {"hotkeyMode": "invalid_mode", "sttEngine": "nonexistent"}
        """
        let data = try JSONDecoder().decode(SettingsData.self, from: Data(json.utf8))
        let defaults = SettingsData()
        #expect(data.hotkeyMode == defaults.hotkeyMode)
        #expect(data.sttEngine == defaults.sttEngine)
    }

    @Test func extraUnknownKeysIgnored() throws {
        let json = """
        {"hotkeyMode": "toggle", "unknownKey": "value", "anotherUnknown": 42}
        """
        let data = try JSONDecoder().decode(SettingsData.self, from: Data(json.utf8))
        #expect(data.hotkeyMode == .toggle)
    }

    @Test func nonJSONDataFails() {
        let garbage = Data("not json at all".utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(SettingsData.self, from: garbage)
        }
    }
}
