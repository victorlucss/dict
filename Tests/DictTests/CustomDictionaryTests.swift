import Testing
@testable import DictCore

@Suite("WordList (CustomDictionary logic)")
struct CustomDictionaryTests {
    @Test func addWord() {
        var list = WordList()
        list.add("Anthropic")
        #expect(list.entries == ["Anthropic"])
    }

    @Test func addDuplicate() {
        var list = WordList(entries: ["Anthropic"])
        list.add("Anthropic")
        #expect(list.entries == ["Anthropic"])
    }

    @Test func addEmptyString() {
        var list = WordList()
        list.add("")
        #expect(list.entries.isEmpty)
    }

    @Test func addWhitespaceOnly() {
        var list = WordList()
        list.add("   ")
        #expect(list.entries.isEmpty)
    }

    @Test func addTrimsWhitespace() {
        var list = WordList()
        list.add("  Anthropic  ")
        #expect(list.entries == ["Anthropic"])
    }

    @Test func removeExisting() {
        var list = WordList(entries: ["Anthropic", "Claude"])
        list.remove("Anthropic")
        #expect(list.entries == ["Claude"])
    }

    @Test func removeNonExistent() {
        var list = WordList(entries: ["Anthropic"])
        list.remove("Claude")
        #expect(list.entries == ["Anthropic"])
    }
}
