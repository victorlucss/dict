import Foundation

/// Normalizes transcribed text for matching: lowercases, trims/collapses whitespace,
/// strips trailing punctuation.
public func normalizeTranscription(_ text: String) -> String {
    text.lowercased()
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .components(separatedBy: .whitespaces)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .trimmingCharacters(in: .punctuationCharacters)
}
