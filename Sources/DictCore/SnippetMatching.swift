import Foundation

/// Matches normalized input against a list of trigger/value pairs.
/// Returns the value of the first matching trigger, or nil.
public func matchSnippet(_ input: String, against entries: [(trigger: String, value: String)]) -> String? {
    let normalized = normalizeTranscription(input)
    for (trigger, value) in entries {
        if normalizeTranscription(trigger) == normalized {
            return value
        }
    }
    return nil
}
