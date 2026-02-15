import Foundation

/// A simple word list with add/remove logic, used by CustomDictionary.
public struct WordList {
    public private(set) var entries: [String]

    public init(entries: [String] = []) {
        self.entries = entries
    }

    /// Adds a word if non-empty and not already present (after trimming whitespace).
    public mutating func add(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !entries.contains(trimmed) else { return }
        entries.append(trimmed)
    }

    /// Removes all occurrences of the exact word.
    public mutating func remove(_ word: String) {
        entries.removeAll { $0 == word }
    }
}
