import AppKit
import AVFoundation
import Speech

/// First-launch wizard that guides the user through permissions and setup.
class OnboardingWindow {
    private var window: NSWindow?
    private var currentStep = 0
    private var contentView: NSView!
    private var onComplete: (() -> Void)?

    private let windowWidth: CGFloat = 480
    private let windowHeight: CGFloat = 340

    private let steps: [(title: String, description: String, action: String)] = [
        (
            "Welcome to Dict",
            "Dict converts your voice to text using a global hotkey.\nPress Option+Space anywhere to start dictating.",
            "Get Started"
        ),
        (
            "Microphone Access",
            "Dict needs microphone access to hear your voice.\nThis will prompt for permission if not already granted.",
            "Grant Microphone"
        ),
        (
            "Accessibility Permission",
            "Dict needs Accessibility access to paste text into apps.\nYou'll need to enable it manually in System Settings.",
            "Open System Settings"
        ),
        (
            "Choose STT Engine",
            "Apple Speech: Built-in, no setup needed.\nWhisper: More accurate, requires Homebrew install.",
            "Use Apple Speech"
        ),
        (
            "You're All Set!",
            "Press Option+Space to start dictating.\nClick the menu bar icon to adjust settings.\n\nTip: Enable LLM cleanup for grammar fixes.",
            "Done"
        ),
    ]

    func show(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        currentStep = 0

        let frame = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)
        let win = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Dict Setup"
        win.center()
        win.isReleasedWhenClosed = false
        win.level = .floating

        contentView = NSView(frame: frame)
        win.contentView = contentView
        window = win

        renderStep()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func renderStep() {
        contentView.subviews.forEach { $0.removeFromSuperview() }

        let step = steps[currentStep]

        // Icon
        let iconName: String
        switch currentStep {
        case 0: iconName = "mic.badge.plus"
        case 1: iconName = "mic"
        case 2: iconName = "lock.shield"
        case 3: iconName = "waveform"
        case 4: iconName = "checkmark.circle"
        default: iconName = "mic"
        }

        let icon = NSImageView(frame: NSRect(x: (windowWidth - 48) / 2, y: windowHeight - 90, width: 48, height: 48))
        icon.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
        icon.contentTintColor = .controlAccentColor
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 36, weight: .light)
        contentView.addSubview(icon)

        // Title
        let title = NSTextField(labelWithString: step.title)
        title.frame = NSRect(x: 40, y: windowHeight - 140, width: windowWidth - 80, height: 30)
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.alignment = .center
        contentView.addSubview(title)

        // Description
        let desc = NSTextField(wrappingLabelWithString: step.description)
        desc.frame = NSRect(x: 40, y: windowHeight - 230, width: windowWidth - 80, height: 80)
        desc.font = .systemFont(ofSize: 14)
        desc.alignment = .center
        desc.textColor = .secondaryLabelColor
        contentView.addSubview(desc)

        // Primary button
        let button = NSButton(title: step.action, target: self, action: #selector(primaryAction))
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.frame = NSRect(x: (windowWidth - 200) / 2, y: 50, width: 200, height: 36)
        button.keyEquivalent = "\r"
        contentView.addSubview(button)

        // Engine choice: add "Use Whisper" as secondary button
        if currentStep == 3 {
            let whisperButton = NSButton(title: "Use Whisper", target: self, action: #selector(chooseWhisper))
            whisperButton.bezelStyle = .rounded
            whisperButton.controlSize = .large
            whisperButton.frame = NSRect(x: (windowWidth - 200) / 2, y: 16, width: 200, height: 36)
            contentView.addSubview(whisperButton)
        }

        // Step indicator
        let stepLabel = NSTextField(labelWithString: "\(currentStep + 1) of \(steps.count)")
        stepLabel.frame = NSRect(x: (windowWidth - 100) / 2, y: 10, width: 100, height: 16)
        stepLabel.font = .systemFont(ofSize: 11)
        stepLabel.alignment = .center
        stepLabel.textColor = .tertiaryLabelColor
        if currentStep != 3 {
            contentView.addSubview(stepLabel)
        }
    }

    @objc private func primaryAction() {
        switch currentStep {
        case 0:
            advance()
        case 1:
            requestMicrophoneAndSpeech()
        case 2:
            openAccessibilitySettings()
            advance()
        case 3:
            Settings.shared.sttEngine = .apple
            advance()
        case 4:
            finish()
        default:
            advance()
        }
    }

    @objc private func chooseWhisper() {
        Settings.shared.sttEngine = .whisper
        advance()
    }

    private func requestMicrophoneAndSpeech() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            if granted {
                Log.info("[Onboarding] Microphone granted")
            } else {
                Log.info("[Onboarding] Microphone denied")
            }
            SFSpeechRecognizer.requestAuthorization { status in
                Log.info("[Onboarding] Speech recognition: \(status.rawValue)")
                DispatchQueue.main.async {
                    self?.advance()
                }
            }
        }
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func openAccessibilitySettings() {
        Self.openAccessibilitySettings()
    }

    private func advance() {
        currentStep += 1
        if currentStep < steps.count {
            renderStep()
        } else {
            finish()
        }
    }

    private func finish() {
        Settings.shared.onboardingDone = true
        window?.close()
        window = nil
        onComplete?()
    }
}
