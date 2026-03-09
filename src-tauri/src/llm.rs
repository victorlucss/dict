use crate::settings::{LLMProvider, SettingsData};
use reqwest::Client;
use serde_json::{json, Value};
use std::time::Duration;

/// Process transcribed text through an LLM API
pub async fn process(
    text: &str,
    settings: &SettingsData,
    frontmost_app: &str,
    dictionary_entries: &[String],
) -> String {
    if !settings.llm_enabled {
        return text.to_string();
    }

    let endpoint = match settings.llm_provider {
        LLMProvider::Openai => "https://api.openai.com/v1/chat/completions",
        LLMProvider::Anthropic => "https://api.anthropic.com/v1/messages",
        LLMProvider::Ollama => "http://localhost:11434/v1/chat/completions",
        LLMProvider::Lmstudio => "http://localhost:1234/v1/chat/completions",
    };

    let system_prompt = build_system_prompt(settings, frontmost_app, dictionary_entries);
    let client = Client::new();

    let result = match settings.llm_provider {
        LLMProvider::Anthropic => {
            call_anthropic(&client, endpoint, &system_prompt, text, settings).await
        }
        _ => call_openai(&client, endpoint, &system_prompt, text, settings).await,
    };

    match result {
        Ok(cleaned) if !cleaned.is_empty() => cleaned,
        Ok(_) => {
            tracing::warn!("LLM returned empty response, using raw transcription");
            text.to_string()
        }
        Err(e) => {
            tracing::warn!("LLM request failed: {}. Using raw transcription.", e);
            text.to_string()
        }
    }
}

async fn call_openai(
    client: &Client,
    endpoint: &str,
    system_prompt: &str,
    text: &str,
    settings: &SettingsData,
) -> Result<String, String> {
    let wrapped = format!("[TRANSCRIPTION TO CLEAN]: {}", text);

    let body = json!({
        "model": settings.llm_model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": wrapped},
        ],
        "temperature": 0.3,
        "max_tokens": 2048
    });

    let mut req = client
        .post(endpoint)
        .header("Content-Type", "application/json")
        .timeout(Duration::from_secs(15));

    if !settings.llm_api_key.is_empty() {
        req = req.header("Authorization", format!("Bearer {}", settings.llm_api_key));
    }

    let resp = req
        .json(&body)
        .send()
        .await
        .map_err(|e| format!("Request failed: {}", e))?;

    let status = resp.status();
    let data: Value = resp
        .json()
        .await
        .map_err(|e| format!("Failed to parse response: {}", e))?;

    if status.as_u16() >= 400 {
        tracing::error!("LLM server returned {}: {}", status, data);
        return Err(format!("HTTP {}", status));
    }

    // Parse OpenAI response format
    data["choices"][0]["message"]["content"]
        .as_str()
        .map(|s| s.trim().to_string())
        .ok_or_else(|| format!("Unexpected response format: {}", data))
}

async fn call_anthropic(
    client: &Client,
    endpoint: &str,
    system_prompt: &str,
    text: &str,
    settings: &SettingsData,
) -> Result<String, String> {
    let wrapped = format!("[TRANSCRIPTION TO CLEAN]: {}", text);

    let body = json!({
        "model": settings.llm_model,
        "system": system_prompt,
        "messages": [
            {"role": "user", "content": wrapped},
        ],
        "temperature": 0.3,
        "max_tokens": 2048
    });

    let mut req = client
        .post(endpoint)
        .header("Content-Type", "application/json")
        .header("anthropic-version", "2023-06-01")
        .timeout(Duration::from_secs(15));

    if !settings.llm_api_key.is_empty() {
        req = req.header("x-api-key", &settings.llm_api_key);
    }

    let resp = req
        .json(&body)
        .send()
        .await
        .map_err(|e| format!("Request failed: {}", e))?;

    let status = resp.status();
    let data: Value = resp
        .json()
        .await
        .map_err(|e| format!("Failed to parse response: {}", e))?;

    if status.as_u16() >= 400 {
        tracing::error!("LLM server returned {}: {}", status, data);
        return Err(format!("HTTP {}", status));
    }

    // Parse Anthropic response format
    data["content"][0]["text"]
        .as_str()
        .map(|s| s.trim().to_string())
        .ok_or_else(|| format!("Unexpected response format: {}", data))
}

fn build_system_prompt(
    settings: &SettingsData,
    frontmost_app: &str,
    dictionary_entries: &[String],
) -> String {
    let mut prompt = settings.llm_prompt.clone();

    // Correction level (1 = minimal, 5 = aggressive)
    let level = settings.llm_accuracy.clamp(1, 5);
    match level {
        1 => {
            prompt += "\n\nCORRECTION LEVEL: Minimal. Only fix obvious typos and add basic punctuation. \
                Do NOT change any words, phrasing, or sentence structure. Preserve the speaker's exact wording.";
        }
        2 => {
            prompt += "\n\nCORRECTION LEVEL: Light. Fix punctuation, capitalization, and remove filler words. \
                Do NOT rephrase, reorder, or substitute words. Keep the speaker's original wording intact.";
        }
        3 => {
            prompt += "\n\nCORRECTION LEVEL: Balanced. Fix grammar, punctuation, and remove filler words. \
                Minor rephrasing is OK for clarity, but stay close to the original wording.";
        }
        4 => {
            prompt += "\n\nCORRECTION LEVEL: Thorough. Fix all grammar and punctuation. \
                Rephrase for clarity and flow. You may change word choice to improve readability.";
        }
        _ => {
            prompt += "\n\nCORRECTION LEVEL: Aggressive. Fully rewrite for proper grammar, structure, and clarity. \
                Reorder sentences, change words, and improve flow as needed. Make it read as polished written text.";
        }
    }

    // App-aware context
    let app_context = app_context_hint(frontmost_app);
    if !app_context.is_empty() {
        prompt += &format!("\n\nThe user is typing in {}. {}", frontmost_app, app_context);
    }

    // Custom dictionary
    if !dictionary_entries.is_empty() {
        let words = dictionary_entries.join(", ");
        prompt += &format!(
            "\n\nThe user's custom dictionary (use these exact spellings for names, jargon, and acronyms): {}",
            words
        );
    }

    // Code mode
    if settings.code_mode {
        prompt += "\n\nCODE MODE is active. The user is dictating code. Format output as valid source code: \
            Use camelCase or snake_case for identifiers (match the surrounding context). \
            No prose formatting, no bullet points, no markdown. \
            Proper indentation and syntax. \
            Convert spoken words to code constructs (e.g. \"function foo takes a string\" → \"func foo(_ s: String)\"). \
            Numbers should be numeric literals, not words. \
            Spoken operators should become symbols (e.g. \"equals\" → \"=\", \"is equal to\" → \"==\").";
    }

    // Correction handling
    prompt += "\n\nIf the user corrects themselves (e.g. \"actually\", \"I mean\", \"no wait\", \
        \"scratch that\", \"correction\"), use ONLY the corrected version and discard \
        what came before the correction phrase.";

    prompt
}

fn app_context_hint(app_name: &str) -> &'static str {
    let name = app_name.to_lowercase();

    if name.contains("slack")
        || name.contains("discord")
        || name.contains("telegram")
        || name.contains("whatsapp")
        || name.contains("messages")
    {
        return "Adapt tone to be casual and conversational. Use informal language.";
    }
    if name.contains("mail") || name.contains("outlook") || name.contains("gmail") {
        return "Adapt tone to be professional and well-structured.";
    }
    if name.contains("code")
        || name.contains("cursor")
        || name.contains("xcode")
        || name.contains("terminal")
        || name.contains("iterm")
        || name.contains("vim")
        || name.contains("neovim")
    {
        return "The user is in a code editor. If they seem to be dictating code, format as code (camelCase/snake_case, no prose). If dictating comments or documentation, keep it technical.";
    }
    if name.contains("notes")
        || name.contains("notion")
        || name.contains("obsidian")
    {
        return "The user is taking notes. Keep it clear and well-organized.";
    }
    ""
}
