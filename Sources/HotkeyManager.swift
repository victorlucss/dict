import AppKit
import Carbon

/// Manages a global keyboard shortcut using Carbon RegisterEventHotKey.
/// Supports two modes:
/// - Toggle: press to start, press again to stop.
/// - Push to talk: hold to record, release to stop.
class HotkeyManager {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var hotkeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    fileprivate static var instance: HotkeyManager?

    func register() {
        HotkeyManager.instance = self

        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            ),
        ]

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotkeyCallback,
            2,
            &eventTypes,
            nil,
            &eventHandlerRef
        )

        guard status == noErr else {
            Log.info("Failed to install event handler: \(status)")
            return
        }

        // Register Option+Space
        let hotkeyID = EventHotKeyID(signature: fourCharCode("DICT"), id: 1)
        let modifiers = UInt32(optionKey)
        let keyCode: UInt32 = 49 // Space

        let regStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        guard regStatus == noErr else {
            Log.info("Failed to register hotkey: \(regStatus)")
            return
        }

        Log.info("Global hotkey registered: Option+Space")
    }

    func unregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
        HotkeyManager.instance = nil
    }

    fileprivate func handlePress() {
        DispatchQueue.main.async {
            self.onPress?()
        }
    }

    fileprivate func handleRelease() {
        DispatchQueue.main.async {
            self.onRelease?()
        }
    }
}

private func fourCharCode(_ string: String) -> FourCharCode {
    var result: FourCharCode = 0
    for char in string.utf8.prefix(4) {
        result = (result << 8) + FourCharCode(char)
    }
    return result
}

private func carbonHotkeyCallback(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event = event else { return noErr }
    let eventKind = GetEventKind(event)
    if eventKind == UInt32(kEventHotKeyPressed) {
        HotkeyManager.instance?.handlePress()
    } else if eventKind == UInt32(kEventHotKeyReleased) {
        HotkeyManager.instance?.handleRelease()
    }
    return noErr
}
