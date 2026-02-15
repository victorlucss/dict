import DictCore
import Foundation

/// Voice-triggered keyboard shortcuts. When transcribed speech matches a trigger phrase,
/// the corresponding key combo is simulated instead of pasting text.
/// Stored at ~/.config/dict/commands.json
class VoiceCommands {
    static let shared = VoiceCommands()

    struct VoiceCommand: Codable {
        var trigger: String
        var keyCombo: String
    }

    private let filePath: URL
    private(set) var entries: [VoiceCommand] = []

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        filePath = home.appendingPathComponent(".config/dict/commands.json")
        load()
    }

    /// Check if transcribed text matches any voice command trigger.
    /// Returns the key combo string if matched, nil otherwise.
    func match(_ transcription: String) -> String? {
        let normalized = normalize(transcription)
        for command in entries {
            if normalize(command.trigger) == normalized {
                return command.keyCombo
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
            entries = try JSONDecoder().decode([VoiceCommand].self, from: data)
        } catch {
            Log.info("Failed to load voice commands: \(error)")
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
            Log.info("Failed to save voice commands: \(error)")
        }
    }
}
