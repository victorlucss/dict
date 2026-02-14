import Foundation

/// Stores transcription history locally at ~/.config/dict/history.json
class TranscriptionHistory {
    static let shared = TranscriptionHistory()

    struct Entry: Codable {
        let timestamp: Date
        let raw: String
        let cleaned: String
        let app: String
        let engine: String
    }

    private let filePath: URL
    private let maxEntries = 500
    private(set) var entries: [Entry] = []

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        filePath = home.appendingPathComponent(".config/dict/history.json")
        load()
    }

    func add(raw: String, cleaned: String, app: String, engine: String) {
        let entry = Entry(
            timestamp: Date(),
            raw: raw,
            cleaned: cleaned,
            app: app,
            engine: engine
        )
        entries.append(entry)

        // Trim old entries
        if entries.count > maxEntries {
            entries = Array(entries.suffix(maxEntries))
        }

        save()
    }

    func search(_ query: String) -> [Entry] {
        let q = query.lowercased()
        return entries.filter {
            $0.raw.lowercased().contains(q) || $0.cleaned.lowercased().contains(q)
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: filePath.path) else { return }
        do {
            let data = try Data(contentsOf: filePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([Entry].self, from: data)
        } catch {
            Log.info("Failed to load history: \(error)")
        }
    }

    private func save() {
        do {
            let dir = filePath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: filePath)
        } catch {
            Log.info("Failed to save history: \(error)")
        }
    }

    func clear() {
        entries = []
        save()
    }
}
