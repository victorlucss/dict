import Foundation

/// In-memory transcription history with search and trimming, used by TranscriptionHistory.
public struct HistoryStore {
    public struct Entry {
        public let timestamp: Date
        public let raw: String
        public let cleaned: String
        public let app: String
        public let engine: String

        public init(timestamp: Date = Date(), raw: String, cleaned: String, app: String, engine: String) {
            self.timestamp = timestamp
            self.raw = raw
            self.cleaned = cleaned
            self.app = app
            self.engine = engine
        }
    }

    public let maxEntries: Int
    public private(set) var entries: [Entry]

    public init(maxEntries: Int = 500, entries: [Entry] = []) {
        self.maxEntries = maxEntries
        self.entries = entries
    }

    public mutating func add(raw: String, cleaned: String, app: String, engine: String) {
        let entry = Entry(raw: raw, cleaned: cleaned, app: app, engine: engine)
        entries.append(entry)
        if entries.count > maxEntries {
            entries = Array(entries.suffix(maxEntries))
        }
    }

    public func search(_ query: String) -> [Entry] {
        let q = query.lowercased()
        return entries.filter {
            $0.raw.lowercased().contains(q) || $0.cleaned.lowercased().contains(q)
        }
    }

    public mutating func clear() {
        entries = []
    }
}
