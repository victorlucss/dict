# Using Dict with Whisper

Dict supports [whisper.cpp](https://github.com/ggerganov/whisper.cpp) as an alternative speech-to-text engine. Whisper runs entirely on-device and can be more accurate than Apple Speech, especially for technical vocabulary.

## Prerequisites

- macOS 14+
- [Homebrew](https://brew.sh)

## 1. Install whisper.cpp

```bash
brew install whisper-cpp
```

This installs the `whisper-cli` binary to `/opt/homebrew/bin/whisper-cli` (Apple Silicon) or `/usr/local/bin/whisper-cli` (Intel).

## 2. Download a model

Whisper needs a GGML model file. Pick one based on your accuracy/speed needs:

| Model | Size | Speed | Accuracy | Best for |
|-------|------|-------|----------|----------|
| `ggml-tiny.en.bin` | ~75 MB | Fastest | Lower | Quick notes, informal dictation |
| `ggml-base.en.bin` | ~142 MB | Fast | Good | General use (recommended start) |
| `ggml-small.en.bin` | ~466 MB | Medium | Better | Longer dictation, mixed vocabulary |
| `ggml-medium.en.bin` | ~1.5 GB | Slow | High | Maximum accuracy |

> The `.en` variants are English-only and faster. For multilingual use (e.g. Portuguese), use the non-`.en` versions (`ggml-base.bin`, `ggml-small.bin`, etc.).

Download a model using the script bundled with whisper-cpp:

```bash
# Download the base English model (recommended starting point)
bash "$(brew --prefix whisper-cpp)/share/whisper-cpp/models/download-ggml-model.sh" base.en

# The model is saved to:
# /opt/homebrew/share/whisper-cpp/models/ggml-base.en.bin  (Apple Silicon)
# /usr/local/share/whisper-cpp/models/ggml-base.en.bin     (Intel)
```

Or download manually from [Hugging Face](https://huggingface.co/ggerganov/whisper.cpp/tree/main) and place the `.bin` file wherever you like.

## 3. Configure Dict

### Via Preferences (recommended)

1. Click the Dict menu bar icon and select **Preferences** (or press Cmd+,)
2. Go to the **Speech** section
3. Set **STT Engine** to **Whisper**
4. Click **Browse** and select your GGML model file, or paste the path directly (e.g. `/opt/homebrew/share/whisper-cpp/models/ggml-base.en.bin`)
5. Choose your **Language**
6. Click **Save**

### Via config file

Edit `~/.config/dict/config.json`:

```json
{
    "sttEngine": "whisper",
    "whisperModelPath": "/opt/homebrew/share/whisper-cpp/models/ggml-base.en.bin",
    "whisperLanguage": "en"
}
```

Set `whisperLanguage` to `"pt"` for Brazilian Portuguese. Use the non-`.en` model variants for multilingual support.

## How it works

When you press the hotkey (Option+Space):

1. Dict records audio from your microphone
2. The recording is converted to a 16kHz mono WAV file
3. Dict runs `whisper-cli -m <model> -l <language> -nt -np -f <audio.wav>` as a subprocess
4. The transcription is returned, optionally cleaned up by LLM post-processing, and pasted into the active app

Recording has a 15-second hard limit. A red border appears on the overlay 3 seconds before cutoff.

## Troubleshooting

**"whisper-cli not found"**
Make sure whisper-cpp is installed (`brew install whisper-cpp`) and `whisper-cli` is in your PATH. Dict checks `/opt/homebrew/bin` and `/usr/local/bin` automatically.

**Empty or garbage transcription**
- Try a larger model (e.g. `ggml-small.en.bin` instead of `ggml-tiny.en.bin`)
- Make sure your microphone is working and permissions are granted
- Check `/tmp/dict.log` for error details

**Slow transcription**
Larger models are more accurate but slower. If speed matters, use `ggml-tiny.en.bin` or `ggml-base.en.bin`. Whisper runs on CPU — Apple Silicon Macs will be significantly faster than Intel.

**Wrong language detected**
Make sure you're using a multilingual model (without `.en` suffix) if dictating in a non-English language, and that the language setting matches.
