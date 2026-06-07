# CONFIG.md

Configuration is stored at `~/.config/dict/config.json` (macOS/Linux) or
`%APPDATA%\dict\config.json` (Windows). It is auto-created with defaults on first
launch. Edit it by hand, or just use Preferences from the menu bar / tray.

Sibling files in the same folder hold list data: `dictionary.json`,
`snippets.json`, `commands.json`, and `history.json`.

## Config Keys

| Key | Type | Default | Allowed Values | Description |
|-----|------|---------|----------------|-------------|
| `hotkey` | string | `"Alt+Space"` (macOS) / `"Ctrl+Alt+Space"` (else) | accelerator or a bare modifier | The dictation trigger. Accelerators go through the global-shortcut plugin; a bare modifier (e.g. `Control`) is handled by a native key monitor on macOS. |
| `hotkeyMode` | string | `"pushToTalk"` | `"toggle"`, `"pushToTalk"` | `toggle`: press the hotkey to start, press again to stop. `pushToTalk`: hold to record, release to stop. |
| `whisperModelPath` | string | `""` | file path | Absolute path to a Whisper GGML model (e.g. `/opt/homebrew/share/whisper-cpp/models/ggml-base.en.bin`). Managed by the in-app model manager (Preferences → Speech). |
| `whisperLanguage` | string | `"en"` | `"en"`, `"pt"`, `"auto"` | Language passed to Whisper's `-l` flag. `auto` lets Whisper detect it. |
| `llmEnabled` | bool | `false` | `true`, `false` | Run each transcription through an LLM to fix grammar and remove fillers. |
| `llmProvider` | string | `"ollama"` | `"dictcloud"`, `"openai"`, `"anthropic"`, `"openrouter"`, `"ollama"`, `"lmstudio"` | Cleanup backend. `dictcloud` is managed (sign in, no key). `openai`/`anthropic`/`openrouter` are cloud (need an API key). `ollama`/`lmstudio` are local (localhost). |
| `llmEndpoint` | string | `"http://localhost:11434/v1/chat/completions"` | URL | Request endpoint. Auto-filled per provider; only edit for custom setups. |
| `llmModel` | string | `"llama3.2"` | model name | Model identifier sent to the LLM API (ignored for Dict Cloud). |
| `llmApiKey` | string | `""` | API key | Key for `openai`/`anthropic`/`openrouter`. Stored locally; unused for local providers and Dict Cloud. |
| `llmTone` | string | `"formal"` | `"formal"`, `"casual"`, `"veryCasual"` | How polished the output reads: full punctuation/caps, lighter, or mostly lowercase. |
| `llmAccuracy` | int | `3` | `1`–`5` | Correction level. **1** minimal (typos/punctuation only). **2** light (fix punctuation, remove fillers). **3** balanced (grammar + minor rephrasing). **4** thorough (rephrase for clarity). **5** aggressive (full rewrite). |
| `flowMode` | bool | `false` | `true`, `false` | Auto-press Return after pasting. Handy for chat apps and terminals. |
| `codeMode` | bool | `false` | `true`, `false` | Bias cleanup toward code (preserve camelCase/snake_case, format as source). |
| `privacyMode` | bool | `false` | `true`, `false` | Skip cloud LLM providers (Dict Cloud / OpenAI / Anthropic / OpenRouter) and stop saving history. Local providers still run. |
| `overlayPosition` | string | `"top"` | `"top"`, `"bottom"` | Where the recording overlay pill sits. |
| `audioInputDevice` | string \| null | `null` | device name | Microphone to record from. `null` uses the system default. |
| `onboardingDone` | bool | `false` | `true`, `false` | Whether the first-run wizard has completed. Set automatically. |
| `dictCloudEmail` | string | `""` | email | The signed-in Dict Cloud account. Set by signing in under the Account tab; don't edit by hand. |
| `dictCloudToken` | string | `""` | token | Dict Cloud session token. Managed by sign-in; don't edit by hand. |

The cleanup system prompt is built from the tone + correction level (see
`src-tauri/src/llm.rs`); there is no user-editable prompt key.

## Example

```json
{
    "hotkey": "Alt+Space",
    "hotkeyMode": "pushToTalk",
    "whisperModelPath": "/opt/homebrew/share/whisper-cpp/models/ggml-base.en.bin",
    "whisperLanguage": "en",
    "llmEnabled": true,
    "llmProvider": "ollama",
    "llmEndpoint": "",
    "llmModel": "llama3.2",
    "llmApiKey": "",
    "llmTone": "formal",
    "llmAccuracy": 3,
    "flowMode": false,
    "codeMode": false,
    "privacyMode": false,
    "overlayPosition": "top",
    "audioInputDevice": null,
    "onboardingDone": true,
    "dictCloudEmail": "",
    "dictCloudToken": ""
}
```

Missing keys fall back to their defaults (serde `#[serde(default)]`), so a partial
config file is fine.
