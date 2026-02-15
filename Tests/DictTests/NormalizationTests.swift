import Testing
@testable import DictCore

@Suite("Transcription normalization")
struct NormalizationTests {
    @Test func lowercasing() {
        #expect(normalizeTranscription("Hello World") == "hello world")
    }

    @Test func whitespaceTrimming() {
        #expect(normalizeTranscription("  hello  ") == "hello")
    }

    @Test func whitespaceCollapsing() {
        #expect(normalizeTranscription("hello    world") == "hello world")
    }

    @Test func trailingPunctuationStripped() {
        #expect(normalizeTranscription("hello world.") == "hello world")
        #expect(normalizeTranscription("hello world!") == "hello world")
        #expect(normalizeTranscription("hello world?") == "hello world")
    }

    @Test func emptyString() {
        #expect(normalizeTranscription("") == "")
    }

    @Test func whitespaceOnly() {
        #expect(normalizeTranscription("   ") == "")
    }

    @Test func unicodeCharacters() {
        #expect(normalizeTranscription("  Café  Résumé  ") == "café résumé")
    }

    @Test func tabsCollapsed() {
        // Tabs are in .whitespaces so they get split and collapsed
        #expect(normalizeTranscription("\thello\t\tworld\t") == "hello world")
    }
}
