import DictCore
import Foundation

/// Voice-triggered text snippets. When transcribed speech matches a trigger phrase,
/// the corresponding expansion text is pasted instead of the raw transcription.
/// Stored at ~/.config/dict/snippets.json
class Snippets {
    static let shared = Snippets()

    struct Snippet: Codable {
        var trigger: String
        var text: String
    }

    private let filePath: URL
    private(set) var entries: [Snippet] = []

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        filePath = home.appendingPathComponent(".config/dict/snippets.json")
        load()
    }

    /// Check if transcribed text matches any snippet trigger.
    /// Uses case-insensitive, whitespace-normalized matching for voice input tolerance.
    /// Returns the expansion text if matched, nil otherwise.
    func match(_ transcription: String) -> String? {
        let normalized = normalize(transcription)
        for snippet in entries {
            if normalize(snippet.trigger) == normalized {
                return snippet.text
            }
        }
        return nil
    }

    private func normalize(_ text: String) -> String {
        normalizeTranscription(text)
    }

    func load() {
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            save()
            return
        }
        do {
            let data = try Data(contentsOf: filePath)
            entries = try JSONDecoder().decode([Snippet].self, from: data)
        } catch {
            Log.info("Failed to load snippets: \(error)")
            entries = []
        }
    }

    func save() {
        do {
            let dir = filePath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: filePath)
        } catch {
            Log.info("Failed to save snippets: \(error)")
        }
    }
}
