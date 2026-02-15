import Testing
@testable import DictCore

@Suite("Snippet matching")
struct SnippetMatchTests {
    let entries: [(trigger: String, value: String)] = [
        (trigger: "my email", value: "user@example.com"),
        (trigger: "my address", value: "123 Main St"),
    ]

    @Test func exactMatch() {
        #expect(matchSnippet("my email", against: entries) == "user@example.com")
    }

    @Test func caseInsensitive() {
        #expect(matchSnippet("My Email", against: entries) == "user@example.com")
        #expect(matchSnippet("MY EMAIL", against: entries) == "user@example.com")
    }

    @Test func extraWhitespace() {
        #expect(matchSnippet("  my   email  ", against: entries) == "user@example.com")
    }

    @Test func trailingPunctuation() {
        #expect(matchSnippet("my email.", against: entries) == "user@example.com")
        #expect(matchSnippet("my email!", against: entries) == "user@example.com")
    }

    @Test func noMatch() {
        #expect(matchSnippet("something else", against: entries) == nil)
    }

    @Test func emptyEntries() {
        let empty: [(trigger: String, value: String)] = []
        #expect(matchSnippet("my email", against: empty) == nil)
    }

    @Test func emptyInput() {
        #expect(matchSnippet("", against: entries) == nil)
    }
}
