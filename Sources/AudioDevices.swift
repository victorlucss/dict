import AVFoundation
import CoreAudio

/// CoreAudio helper for enumerating input devices and routing AVAudioEngine to a specific mic.
enum AudioDevices {

    /// Returns all audio input devices as (uid, name) pairs.
    static func listInputDevices() -> [(uid: String, name: String)] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        guard status == noErr, dataSize > 0 else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return [] }

        var results: [(uid: String, name: String)] = []

        for deviceID in deviceIDs {
            // Check if the device has input streams
            var inputStreamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            let streamStatus = AudioObjectGetPropertyDataSize(deviceID, &inputStreamAddress, 0, nil, &streamSize)
            guard streamStatus == noErr, streamSize > 0 else { continue }

            guard let uid = stringProperty(kAudioDevicePropertyDeviceUID, of: deviceID),
                  let name = stringProperty(kAudioDevicePropertyDeviceNameCFString, of: deviceID) else {
                continue
            }

            results.append((uid: uid, name: name))
        }

        return results
    }

    /// Sets the input device on an AVAudioEngine's input node audio unit.
    /// Must be called **before** `audioEngine.start()`.
    /// If `uid` is empty, does nothing (uses system default).
    static func setInputDevice(uid: String, on engine: AVAudioEngine) {
        guard !uid.isEmpty else { return }
        guard let deviceID = deviceID(forUID: uid) else {
            Log.info("Audio device with UID '\(uid)' not found, using system default")
            return
        }

        let inputNode = engine.inputNode
        guard let audioUnit = inputNode.audioUnit else {
            Log.info("Could not get audio unit from input node")
            return
        }

        var deviceIDVar = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceIDVar,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status == noErr {
            Log.info("Set input device to '\(uid)' (ID \(deviceID))")
        } else {
            Log.info("Failed to set input device (status \(status)), using system default")
        }
    }

    // MARK: - Private helpers

    /// Reads a CFString property from a CoreAudio device without triggering UnsafeMutableRawPointer warnings.
    private static func stringProperty(_ selector: AudioObjectPropertySelector, of deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var ref = Unmanaged<CFString>.passUnretained("" as CFString)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
        let status = withUnsafeMutablePointer(to: &ref) { ptr in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, ptr)
        }
        guard status == noErr else { return nil }
        return ref.takeUnretainedValue() as String
    }

    /// Finds the AudioDeviceID matching a given UID string.
    private static func deviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &dataSize
        ) == noErr else { return nil }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &dataSize, &deviceIDs
        ) == noErr else { return nil }

        for deviceID in deviceIDs {
            guard let deviceUID = stringProperty(kAudioDevicePropertyDeviceUID, of: deviceID) else { continue }
            if deviceUID == uid {
                return deviceID
            }
        }

        return nil
    }
}
