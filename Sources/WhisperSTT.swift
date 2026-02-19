import AVFoundation
import Foundation

/// Speech-to-text using whisper.cpp CLI as a subprocess.
/// Records audio to a 16kHz 16-bit mono WAV file, then runs whisper-cli.
class WhisperSTT {
    private let audioEngine = AVAudioEngine()
    private var buffers: [AVAudioPCMBuffer] = []
    private var tempFileURL: URL?
    private var isRecording = false

    var onResult: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onAudioLevel: ((Float) -> Void)?

    func startRecording() {
        guard !isRecording else { return }

        buffers = []

        let selectedMic = Settings.shared.selectedMicrophoneUID
        if !selectedMic.isEmpty {
            AudioDevices.setInputDevice(uid: selectedMic, on: audioEngine)
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        Log.info("[Whisper] Mic format: \(inputFormat)")

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Collect buffers for later writing
            if let copy = buffer.copy() as? AVAudioPCMBuffer {
                self.buffers.append(copy)
            }

            // Audio level for overlay
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
                self.onAudioLevel?(normalized)
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            Log.info("[Whisper] Recording started")
        } catch {
            onError?("Audio engine failed: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        Log.info("[Whisper] Recording stopped, \(buffers.count) buffers captured")

        let capturedBuffers = buffers
        buffers = []

        guard !capturedBuffers.isEmpty else {
            onError?("No audio captured")
            return
        }

        // Write WAV file on background thread, then transcribe
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent("dict_\(UUID().uuidString).wav")
            self.tempFileURL = tempFile

            // Convert to 16kHz 16-bit mono PCM WAV (what whisper expects)
            guard let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16000,
                channels: 1,
                interleaved: true
            ) else {
                DispatchQueue.main.async { self.onError?("Failed to create target format") }
                return
            }

            let sourceFormat = capturedBuffers[0].format
            guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
                DispatchQueue.main.async { self.onError?("Failed to create audio converter") }
                return
            }

            // Calculate total frame count in target sample rate
            var totalSourceFrames: AVAudioFrameCount = 0
            for buf in capturedBuffers {
                totalSourceFrames += buf.frameLength
            }
            let totalTargetFrames = AVAudioFrameCount(
                Double(totalSourceFrames) * 16000.0 / sourceFormat.sampleRate
            )

            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: totalTargetFrames + 1024
            ) else {
                DispatchQueue.main.async { self.onError?("Failed to create output buffer") }
                return
            }

            // Feed all captured buffers through the converter
            var bufferIndex = 0

            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                if bufferIndex >= capturedBuffers.count {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                outStatus.pointee = .haveData
                let buf = capturedBuffers[bufferIndex]
                bufferIndex += 1
                return buf
            }

            var conversionError: NSError?
            _ = converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputBlock)

            if let conversionError = conversionError {
                Log.info("[Whisper] Conversion error: \(conversionError)")
                DispatchQueue.main.async { self.onError?("Audio conversion failed: \(conversionError)") }
                return
            }

            Log.info("[Whisper] Converted \(totalSourceFrames) frames → \(outputBuffer.frameLength) frames (16kHz)")

            // Write WAV file manually (AVAudioFile can crash with Int16 buffers)
            do {
                let frameCount = Int(outputBuffer.frameLength)
                guard frameCount > 0, let int16Data = outputBuffer.int16ChannelData else {
                    Log.error("[Whisper] Output buffer empty or not Int16")
                    DispatchQueue.main.async { self.onError?("Audio conversion produced empty buffer") }
                    return
                }

                let dataSize = frameCount * 2  // 16-bit = 2 bytes per sample
                let rawData = Data(bytes: int16Data[0], count: dataSize)

                // Build WAV header
                var wavData = Data()
                let headerSize = 44
                let fileSize = UInt32(headerSize + dataSize - 8)
                let sampleRate: UInt32 = 16000
                let byteRate: UInt32 = sampleRate * 2  // 16-bit mono
                let blockAlign: UInt16 = 2
                let bitsPerSample: UInt16 = 16

                wavData.append(contentsOf: "RIFF".utf8)
                wavData.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
                wavData.append(contentsOf: "WAVE".utf8)
                wavData.append(contentsOf: "fmt ".utf8)
                wavData.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })  // chunk size
                wavData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })   // PCM format
                wavData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })   // mono
                wavData.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
                wavData.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
                wavData.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
                wavData.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
                wavData.append(contentsOf: "data".utf8)
                wavData.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })
                wavData.append(rawData)

                try wavData.write(to: tempFile)
                Log.info("[Whisper] Wrote WAV: \(tempFile.path) (\(wavData.count) bytes, \(frameCount) frames)")
            } catch {
                Log.error("[Whisper] Failed to write WAV: \(error)")
                DispatchQueue.main.async { self.onError?("Failed to write audio: \(error)") }
                return
            }

            self.transcribe(audioFile: tempFile)
        }
    }

    private func transcribe(audioFile: URL) {
        let settings = Settings.shared
        let whisperPath = findWhisperBinary()

        guard let whisperPath = whisperPath else {
            DispatchQueue.main.async { self.onError?("whisper-cli not found. Install: brew install whisper-cpp") }
            return
        }

        let modelPath = settings.whisperModelPath
        guard !modelPath.isEmpty, FileManager.default.fileExists(atPath: modelPath) else {
            DispatchQueue.main.async { self.onError?("Whisper model not found at: \(modelPath)") }
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: whisperPath)
        var args = [
            "-m", modelPath,
            "-nt",         // no timestamps
            "-np",         // no prints (short flag)
            "-f", audioFile.path,
        ]
        args.insert(contentsOf: ["-l", settings.whisperLanguage], at: 2)
        process.arguments = args

        Log.info("[Whisper] Running: \(whisperPath) \(process.arguments!.joined(separator: " "))")

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stderr = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            Log.info("[Whisper] Exit: \(process.terminationStatus)")
            if !output.isEmpty { Log.info("[Whisper] Output: \(output)") }
            if !stderr.isEmpty { Log.info("[Whisper] Stderr: \(stderr.prefix(500))") }

            // Clean up
            try? FileManager.default.removeItem(at: audioFile)

            DispatchQueue.main.async { [weak self] in
                if process.terminationStatus == 0 && !output.isEmpty {
                    // Filter out whisper noise like "[BLANK_AUDIO]"
                    let cleaned = output
                        .replacingOccurrences(of: "[BLANK_AUDIO]", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty {
                        self?.onResult?(cleaned)
                    } else {
                        self?.onError?("No speech detected")
                    }
                } else {
                    self?.onError?("Whisper returned no output (exit \(process.terminationStatus))")
                }
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.onError?("Failed to run whisper: \(error)")
            }
        }
    }

    private func findWhisperBinary() -> String? {
        let candidates = [
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
            "/opt/homebrew/bin/whisper-cpp",
            "/usr/local/bin/whisper-cpp",
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        for name in ["whisper-cli", "whisper-cpp"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = [name]
            let pipe = Pipe()
            process.standardOutput = pipe
            try? process.run()
            process.waitUntilExit()

            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let path = output, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }
}
