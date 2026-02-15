import Foundation

/// Extracts the assistant message content from an OpenAI-compatible chat completion response.
public func parseOpenAIResponse(_ data: Data) -> String? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = json["choices"] as? [[String: Any]],
          let first = choices.first,
          let message = first["message"] as? [String: Any],
          let content = message["content"] as? String
    else { return nil }
    return content.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Extracts the first text block from an Anthropic Messages API response.
public func parseAnthropicResponse(_ data: Data) -> String? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let content = json["content"] as? [[String: Any]],
          let first = content.first,
          let text = first["text"] as? String
    else { return nil }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}
