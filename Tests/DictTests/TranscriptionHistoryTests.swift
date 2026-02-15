import Testing
@testable import DictCore

@Suite("HistoryStore (TranscriptionHistory logic)")
struct TranscriptionHistoryTests {
    @Test func addAndRetrieve() {
        var store = HistoryStore()
        store.add(raw: "hello world", cleaned: "Hello world.", app: "Notes", engine: "apple")
        #expect(store.entries.count == 1)
        #expect(store.entries[0].raw == "hello world")
        #expect(store.entries[0].cleaned == "Hello world.")
        #expect(store.entries[0].app == "Notes")
        #expect(store.entries[0].engine == "apple")
    }

    @Test func searchRawText() {
        var store = HistoryStore()
        store.add(raw: "hello world", cleaned: "Hello world.", app: "Notes", engine: "apple")
        store.add(raw: "goodbye", cleaned: "Goodbye.", app: "Notes", engine: "apple")
        let results = store.search("hello")
        #expect(results.count == 1)
        #expect(results[0].raw == "hello world")
    }

    @Test func searchCleanedText() {
        var store = HistoryStore()
        store.add(raw: "um hello", cleaned: "Hello world.", app: "Notes", engine: "apple")
        let results = store.search("world")
        #expect(results.count == 1)
    }

    @Test func searchCaseInsensitive() {
        var store = HistoryStore()
        store.add(raw: "Hello World", cleaned: "Hello World", app: "Notes", engine: "apple")
        #expect(store.search("hello").count == 1)
        #expect(store.search("WORLD").count == 1)
    }

    @Test func maxEntriesTrim() {
        var store = HistoryStore(maxEntries: 500)
        for i in 0...500 {
            store.add(raw: "entry \(i)", cleaned: "Entry \(i)", app: "Notes", engine: "apple")
        }
        // 501 added, trimmed to last 500
        #expect(store.entries.count == 500)
        #expect(store.entries[0].raw == "entry 1")
        #expect(store.entries[499].raw == "entry 500")
    }

    @Test func clearEmptiesList() {
        var store = HistoryStore()
        store.add(raw: "hello", cleaned: "Hello", app: "Notes", engine: "apple")
        store.add(raw: "world", cleaned: "World", app: "Notes", engine: "apple")
        #expect(store.entries.count == 2)
        store.clear()
        #expect(store.entries.isEmpty)
    }
}
