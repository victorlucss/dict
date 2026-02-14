# CONFIG.md

Configuration is stored at `~/.config/dict/config.json`. It is auto-created with defaults on first launch. You can edit it by hand or use Preferences (Cmd+,) from the menu bar.

## Config Keys

| Key | Type | Default | Allowed Values | Description |
|-----|------|---------|----------------|-------------|
| `hotkeyMode` | string | `"pushToTalk"` | `"toggle"`, `"pushToTalk"` | `toggle`: press Option+Space to start, press again to stop. `pushToTalk`: hold Option+Space to record, release to stop. |
| `sttEngine` | string | `"apple"` | `"apple"`, `"whisper"` | Speech-to-text backend. `apple` uses on-device Apple Speech Recognition. `whisper` runs `whisper-cli` as a subprocess (requires `brew install whisper-cpp` + a GGML model). |
| `whisperModelPath` | string | `""` | File path | Absolute path to a Whisper GGML model file (e.g. `/opt/homebrew/share/whisper-cpp/models/ggml-base.en.bin`). Only used when `sttEngine` is `"whisper"`. |
| `whisperLanguage` | string | `"en"` | `"auto"`, `"en"`, `"es"`, `"fr"`, `"de"`, `"it"`, `"pt"`, `"ja"`, `"ko"`, `"zh"`, `"ru"`, `"ar"`, `"hi"`, `"nl"`, `"pl"`, `"sv"`, `"tr"`, `"uk"` | Language for speech recognition. `"auto"` lets the engine detect automatically. |
| `llmEnabled` | bool | `false` | `true`, `false` | Enable LLM post-processing to clean up transcriptions (fix grammar, remove filler words). |
| `llmProvider` | string | `"openai"` | `"openai"`, `"anthropic"` | LLM API provider. Both use their respective chat completions API format. |
| `llmEndpoint` | string | `"http://localhost:11434/v1/chat/completions"` | URL | API endpoint for LLM requests. Default points to a local Ollama instance. |
| `llmModel` | string | `"llama3.2"` | Model name | Model identifier sent to the LLM API. |
| `llmApiKey` | string | `""` | API key | API key for the LLM provider. Leave empty for local endpoints that don't require auth. |
| `llmPrompt` | string | *(cleanup prompt)* | Any text | System prompt sent to the LLM for post-processing transcriptions. |
| `codeMode` | bool | `false` | `true`, `false` | When enabled, adjusts LLM processing for code-related dictation (preserves technical terms, formatting). |
| `privacyMode` | bool | `false` | `true`, `false` | Forces offline operation: switches engine to `whisper` and disables LLM. |
| `verboseOverlay` | bool | `false` | `true`, `false` | `true`: show full overlay with mic, audio levels, and streaming transcription text. `false`: show a compact pill with just mic and audio levels. |
| `onboardingDone` | bool | `false` | `true`, `false` | Tracks whether the onboarding wizard has been completed. Set automatically. |
| `githubRepo` | string | `""` | `"owner/repo"` | GitHub repository for update checking. |

## Example

```json
{
  "codeMode": false,
  "hotkeyMode": "pushToTalk",
  "llmApiKey": "",
  "llmEnabled": true,
  "llmEndpoint": "https://api.openai.com/v1/chat/completions",
  "llmModel": "gpt-4o-mini",
  "llmPrompt": "Clean up the following voice transcription. Remove filler words, fix grammar and punctuation. Output ONLY the cleaned text.",
  "llmProvider": "openai",
  "onboardingDone": true,
  "privacyMode": false,
  "sttEngine": "apple",
  "verboseOverlay": false,
  "whisperLanguage": "en",
  "whisperModelPath": ""
}
```

## Related Files

| File | Description |
|------|-------------|
| `~/.config/dict/config.json` | Main configuration |
| `~/.config/dict/dictionary.json` | Custom word replacements (e.g. correct proper nouns) |
| `~/.config/dict/snippets.json` | Voice-triggered text snippets (say a phrase, expand to text) |
| `/tmp/dict.log` | Runtime log |
