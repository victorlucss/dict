import Foundation

/// User-editable word list for jargon, names, and acronyms.
/// Stored at ~/.config/dict/dictionary.json as a simple JSON array of strings.
/// These words are injected into the LLM prompt so it uses the correct spellings.
class CustomDictionary {
    static let shared = CustomDictionary()

    private let filePath: URL
    private(set) var entries: [String] = []

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        filePath = home.appendingPathComponent(".config/dict/dictionary.json")
        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            // Create default empty dictionary file
            save()
            return
        }
        do {
            let data = try Data(contentsOf: filePath)
            entries = try JSONDecoder().decode([String].self, from: data)
        } catch {
            Log.info("Failed to load custom dictionary: \(error)")
            entries = []
        }
    }

    func save() {
        do {
            let dir = filePath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            let json = try JSONSerialization.jsonObject(with: data)
            let prettyData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
            try prettyData.write(to: filePath)
        } catch {
            Log.info("Failed to save custom dictionary: \(error)")
        }
    }

    func add(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !entries.contains(trimmed) else { return }
        entries.append(trimmed)
        save()
    }

    func remove(_ word: String) {
        entries.removeAll { $0 == word }
        save()
    }
}
