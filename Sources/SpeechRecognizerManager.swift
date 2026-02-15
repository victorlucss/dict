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
    private var lastPartialText: String = ""
    private var delivered = false
    /// Monotonically increasing session counter; prevents stale callbacks
    /// from old recognition tasks or timeouts from affecting the current session.
    private var sessionID: UInt64 = 0

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
        lastPartialText = ""
        delivered = false
        sessionID &+= 1
        let currentSession = sessionID

        let localeID = Self.localeIdentifier(for: Settings.shared.whisperLanguage)
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID))
        Log.info("Apple Speech locale: \(localeID) (session \(currentSession))")

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
            guard let self = self, self.sessionID == currentSession, !self.delivered else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    self.delivered = true
                    DispatchQueue.main.async {
                        self.onResult?(text)
                    }
                } else {
                    self.lastPartialText = text
                    DispatchQueue.main.async {
                        self.onPartialResult?(text)
                    }
                }
            }

            if let error = error {
                let nsError = error as NSError
                // 216 = request was cancelled (normal on stop)
                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                    // Task ended without a final result — deliver last partial if we have one.
                    // If empty, let the 3s timeout in stopListening() handle it so we don't
                    // preempt a final result that may still arrive.
                    if !self.delivered && !self.lastPartialText.isEmpty {
                        self.delivered = true
                        DispatchQueue.main.async {
                            self.onResult?(self.lastPartialText)
                        }
                    }
                    return
                }
                DispatchQueue.main.async {
                    self.onError?(error.localizedDescription)
                }
            }
        }
    }

    func stopListening() {
        let currentSession = sessionID
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        // Don't cancel recognitionTask — let it finish processing and deliver isFinal.
        // A 3s safety timeout ensures we don't hang forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self, self.sessionID == currentSession, !self.delivered else { return }
            self.delivered = true
            // Use last partial if available, otherwise deliver empty to unblock the UI
            self.onResult?(self.lastPartialText)
            self.recognitionTask?.cancel()
            self.recognitionTask = nil
        }
    }
}
