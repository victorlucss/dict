import AppKit
import Carbon

/// Injects text into the currently focused application via clipboard paste.
class TextInjector {

    func type(_ text: String) {
        // Small delay to ensure the target app has focus after overlay dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.pasteText(text)
        }
    }

    private func pasteText(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)
        let flowMode = Settings.shared.flowMode

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        Log.info("Pasting text (flow mode: \(flowMode))")

        // Use CGEvent for Cmd+V (primary — doesn't require Automation permission)
        simulateCmdV()

        // Flow mode: press Return after pasting to send the message
        if flowMode {
            DispatchQueue.global(qos: .userInteractive).async {
                Thread.sleep(forTimeInterval: 0.3)
                self.simulateReturn()
            }
        }

        // Restore clipboard after a delay
        let restoreDelay: TimeInterval = flowMode ? 1.0 : 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
            pasteboard.clearContents()
            if let previous = previousContents {
                pasteboard.setString(previous, forType: .string)
            }
        }
    }

    /// Simulate Cmd+V via CGEvent
    private func simulateCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }

    /// Simulate Return key press via CGEvent
    private func simulateReturn() {
        let source = CGEventSource(stateID: .privateState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)
        else {
            Log.info("Flow mode: failed to create CGEvent for Return")
            return
        }

        keyDown.flags = []
        keyUp.flags = []

        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        Log.info("Flow mode: Return sent")
    }

    /// Simulate a keyboard shortcut from a combo string like "cmd+shift+3".
    func simulateKeyCombo(_ combo: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.postKeyCombo(combo)
        }
    }

    private func postKeyCombo(_ combo: String) {
        let parts = combo.lowercased().split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }
        guard let keyName = parts.last else {
            Log.info("Invalid key combo: \(combo)")
            return
        }

        var flags = CGEventFlags()
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "opt", "option", "alt": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            default: Log.info("Unknown modifier: \(part)")
            }
        }

        guard let keyCode = Self.virtualKeyCode(for: keyName) else {
            Log.info("Unknown key name: \(keyName)")
            return
        }

        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            Log.info("Failed to create CGEvent for key combo: \(combo)")
            return
        }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        Log.info("Simulated key combo: \(combo)")
    }

    private static func virtualKeyCode(for name: String) -> CGKeyCode? {
        let map: [String: CGKeyCode] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
            "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
            "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
            "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
            "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53,
            "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
            "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
            "up": 126, "down": 125, "left": 123, "right": 124,
        ]
        return map[name]
    }

    /// Check Accessibility permission status (no prompt).
    static func checkAccessibility() {
        let trusted = AXIsProcessTrusted()
        if trusted {
            Log.info("Accessibility: granted")
        } else {
            Log.info("Accessibility: not granted — text pasting may not work.")
            Log.info("Go to System Settings > Privacy & Security > Accessibility and enable Dict.")
        }
    }
}
