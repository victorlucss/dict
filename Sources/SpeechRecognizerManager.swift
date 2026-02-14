import AVFoundation
import Speech

/// Manages microphone capture + Apple Speech recognition in a streaming fashion.
class SpeechRecognizerManager {
    var onResult: ((String) -> Void)?
    var onPartialResult: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onAudioLevel: ((Float) -> Void)?

    private var speechRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private static func localeIdentifier(for code: String) -> String {
        switch code {
        case "pt": return "pt-BR"
        default: return "en-US"
        }
    }

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { status in
            switch status {
            case .authorized:
                Log.info("Speech recognition authorized.")
            case .denied:
                Log.info("Speech recognition denied. Enable in System Settings > Privacy > Speech Recognition.")
            case .restricted:
                Log.info("Speech recognition restricted on this device.")
            case .notDetermined:
                Log.info("Speech recognition not yet determined.")
            @unknown default:
                break
            }
        }

        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                Log.info("Microphone access denied. Enable in System Settings > Privacy > Microphone.")
            }
        }
    }

    func startListening() {
        recognitionTask?.cancel()
        recognitionTask = nil

        let localeID = Self.localeIdentifier(for: Settings.shared.whisperLanguage)
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID))
        Log.info("Apple Speech locale: \(localeID)")

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            onError?("Speech recognizer not available for \(localeID).")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)

            // Calculate audio level from buffer
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frames {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrt(sum / Float(max(frames, 1)))
            // Normalize to 0-1 range; use sqrt curve so quiet speech is visible
            let normalized = min(1.0, sqrt(min(1.0, rms * 20.0)))
            DispatchQueue.main.async {
                self?.onAudioLevel?(normalized)
            }
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            onError?("Audio engine failed to start: \(error.localizedDescription)")
            return
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    DispatchQueue.main.async {
                        self.onResult?(text)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.onPartialResult?(text)
                    }
                }
            }

            if let error = error {
                let nsError = error as NSError
                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                    return
                }
                DispatchQueue.main.async {
                    self.onError?(error.localizedDescription)
                }
            }
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
    }
}
