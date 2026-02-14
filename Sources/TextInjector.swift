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
