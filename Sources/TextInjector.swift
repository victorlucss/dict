import AppKit
import Carbon

/// Injects text into the currently focused application via clipboard paste.
class TextInjector {

    func type(_ text: String) {
        // Small delay to ensure the target app has focus after overlay dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.pasteViaAppleScript(text)
        }
    }

    /// Uses AppleScript to perform Cmd+V — works reliably without
    /// needing to manually post CGEvents (which can be swallowed).
    private func pasteViaAppleScript(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Use AppleScript to keystroke Cmd+V into the frontmost app
        let script = NSAppleScript(source: """
            tell application "System Events"
                keystroke "v" using command down
            end tell
            """)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)

        if let error = error {
            Log.info("AppleScript paste failed: \(error). Trying CGEvent fallback.")
            // Small delay before CGEvent to ensure frontmost app is ready
            usleep(50_000)
            simulateCmdV()
        }

        // Flow mode: press Return after pasting to send the message
        if Settings.shared.flowMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let returnScript = NSAppleScript(source: """
                    tell application "System Events"
                        keystroke return
                    end tell
                    """)
                var returnError: NSDictionary?
                returnScript?.executeAndReturnError(&returnError)
            }
        }

        // Restore clipboard after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pasteboard.clearContents()
            if let previous = previousContents {
                pasteboard.setString(previous, forType: .string)
            }
        }
    }

    /// CGEvent fallback for Cmd+V
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
