import Foundation

/// Post-processes transcribed text through an LLM API.
/// Supports OpenAI-compatible (OpenAI, Ollama, LM Studio) and Anthropic Messages API.
class LLMProcessor {

    func process(_ text: String, frontmostApp: String = "Unknown", completion: @escaping (Result<String, Error>) -> Void) {
        let settings = Settings.shared

        guard settings.llmEnabled else {
            completion(.success(text))
            return
        }

        guard let url = URL(string: settings.llmEndpoint) else {
            completion(.failure(LLMError.invalidEndpoint))
            return
        }

        let systemPrompt = buildSystemPrompt(frontmostApp: frontmostApp)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        switch settings.llmProvider {
        case .openai:
            request = buildOpenAIRequest(request, systemPrompt: systemPrompt, text: text, settings: settings)
        case .anthropic:
            request = buildAnthropicRequest(request, systemPrompt: systemPrompt, text: text, settings: settings)
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                Log.info("LLM request failed: \(error.localizedDescription). Using raw transcription.")
                completion(.success(text))
                return
            }

            guard let data = data else {
                completion(.success(text))
                return
            }

            let content: String?
            switch settings.llmProvider {
            case .openai:
                content = self?.parseOpenAIResponse(data)
            case .anthropic:
                content = self?.parseAnthropicResponse(data)
            }

            if let content = content, !content.isEmpty {
                completion(.success(content))
            } else {
                Log.info("Unexpected LLM response format. Using raw transcription.")
                completion(.success(text))
            }
        }.resume()
    }

    // MARK: - OpenAI Format (OpenAI, Ollama, LM Studio)

    private func buildOpenAIRequest(_ request: URLRequest, systemPrompt: String, text: String, settings: Settings) -> URLRequest {
        var req = request
        if !settings.llmApiKey.isEmpty {
            req.setValue("Bearer \(settings.llmApiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model": settings.llmModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text],
            ],
            "temperature": 0.3,
            "max_tokens": 2048,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }

    private func parseOpenAIResponse(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String
        else { return nil }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Anthropic Messages API

    private func buildAnthropicRequest(_ request: URLRequest, systemPrompt: String, text: String, settings: Settings) -> URLRequest {
        var req = request
        if !settings.llmApiKey.isEmpty {
            req.setValue(settings.llmApiKey, forHTTPHeaderField: "x-api-key")
        }
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": settings.llmModel,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": text],
            ],
            "temperature": 0.3,
            "max_tokens": 2048,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }

    private func parseAnthropicResponse(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String
        else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - System Prompt

    private func buildSystemPrompt(frontmostApp: String) -> String {
        let settings = Settings.shared
        var prompt = settings.llmPrompt

        // App-aware context
        let appContext = appContextHint(for: frontmostApp)
        if !appContext.isEmpty {
            prompt += "\n\nThe user is typing in \(frontmostApp). \(appContext)"
        }

        // Custom dictionary
        let dictionary = CustomDictionary.shared.entries
        if !dictionary.isEmpty {
            let words = dictionary.joined(separator: ", ")
            prompt += "\n\nThe user's custom dictionary (use these exact spellings for names, jargon, and acronyms): \(words)"
        }

        // Code mode
        if settings.codeMode {
            prompt += """


            CODE MODE is active. The user is dictating code. Format output as valid source code: \
            Use camelCase or snake_case for identifiers (match the surrounding context). \
            No prose formatting, no bullet points, no markdown. \
            Proper indentation and syntax. \
            Convert spoken words to code constructs (e.g. "function foo takes a string" → "func foo(_ s: String)"). \
            Numbers should be numeric literals, not words. \
            Spoken operators should become symbols (e.g. "equals" → "=", "is equal to" → "==").
            """
        }

        // Correction handling
        prompt += """


        If the user corrects themselves (e.g. "actually", "I mean", "no wait", \
        "scratch that", "correction"), use ONLY the corrected version and discard \
        what came before the correction phrase.
        """

        return prompt
    }

    private func appContextHint(for appName: String) -> String {
        let name = appName.lowercased()

        if name.contains("slack") || name.contains("discord") || name.contains("telegram") || name.contains("whatsapp") || name.contains("messages") {
            return "Adapt tone to be casual and conversational. Use informal language."
        }
        if name.contains("mail") || name.contains("outlook") || name.contains("gmail") {
            return "Adapt tone to be professional and well-structured."
        }
        if name.contains("code") || name.contains("cursor") || name.contains("xcode") || name.contains("terminal") || name.contains("iterm") || name.contains("vim") || name.contains("neovim") {
            return "The user is in a code editor. If they seem to be dictating code, format as code (camelCase/snake_case, no prose). If dictating comments or documentation, keep it technical."
        }
        if name.contains("notes") || name.contains("notion") || name.contains("obsidian") {
            return "The user is taking notes. Keep it clear and well-organized."
        }
        return ""
    }

    enum LLMError: LocalizedError {
        case invalidEndpoint

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint:
                return "Invalid LLM endpoint URL"
            }
        }
    }
}
