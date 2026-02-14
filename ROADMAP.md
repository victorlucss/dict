# Dict Roadmap

## Completed

### Phase 0 — Foundation
- [x] Project scaffolding (Swift SPM, menu bar app, build script)
- [x] Global keyboard shortcut (Option+Space, Carbon hotkey, toggle mode)
- [x] Microphone capture (AVAudioEngine)
- [x] Speech-to-text with Apple Speech (on-device SFSpeechRecognizer)
- [x] Text injection into focused app (AppleScript + CGEvent fallback)

### Phase 1 — Usable MVP
- [x] Recording overlay UI (floating HUD with pulsing mic + audio level bars)
- [x] Whisper integration (whisper-cli subprocess, records WAV, parses output)
- [x] LLM post-processing (OpenAI-compatible API for filler removal, grammar fix)
- [x] Settings and configuration (~/.config/dict/config.json, menu toggles)

### Phase 2 — Smart Features
- [x] **App-aware context** — Detect frontmost app via NSWorkspace, pass app name to LLM so it adapts tone (casual for Slack, formal for Mail, code-aware for VS Code/Cursor)
- [x] **Custom dictionary** — User-editable word list for jargon, names, acronyms. Injected into LLM prompt as context. Stored in `~/.config/dict/dictionary.json`
- [x] **Multi-language support** — Auto-detect spoken language or let user pin a language. Whisper handles 99 languages natively
- [x] **Snippets / voice commands** — "Insert my email signature" expands predefined text. Simple command parser before LLM step
- [x] **Correction handling** — Detect phrases like "actually", "I mean", "scratch that" and have the LLM use only the corrected version

### Phase 3 — Power User
- [x] **Streaming transcription** — Show real-time partial transcription in the overlay as user speaks, then replace with LLM-cleaned version
- [x] **Code mode** — When in a code editor, output valid syntax: camelCase/snake_case identifiers, proper indentation, no prose formatting
- [x] **Privacy mode** — Fully offline pipeline: Whisper.cpp + local LLM (llama.cpp / MLX). Zero network calls. Toggle in settings
- [x] **History log** — Local log of transcriptions with timestamps. Searchable. Useful for meeting notes
- [x] **Configurable LLM providers** — Support OpenAI, Anthropic, Ollama, LM Studio, or any OpenAI-compatible endpoint. User brings their own key

### Phase 4 — Polish
- [x] **Onboarding flow** — First-launch wizard: grant mic permission, grant accessibility permission, set shortcut, pick STT engine
- [x] **Auto-update** — GitHub releases version check on launch, notification with download link
- [x] **Accessibility permissions helper** — Guide user through System Settings with direct link to Accessibility pane
- [x] **Performance profiling** — Pipeline timing instrumentation (STT/LLM/total latency logged per transcription)
- [x] **Homebrew & DMG distribution** — `./scripts/build.sh --dmg` creates DMG, Homebrew cask formula template included
