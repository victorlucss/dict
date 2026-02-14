import AppKit
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotkeyManager = HotkeyManager()
    private let appleSpeech = SpeechRecognizerManager()
    private let whisperSTT = WhisperSTT()
    private let llmProcessor = LLMProcessor()
    private let textInjector = TextInjector()
    private let overlay = RecordingOverlay()
    private let settings = Settings.shared
    private var isRecording = false
    private var recordingStoppedAt: CFAbsoluteTime = 0
    private var pushToTalkMonitor: Any?

    private var preferencesWindow: PreferencesWindow?
    private var onboarding: OnboardingWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.clear()
        setupMainMenu()
        setupStatusBar()
        setupHotkey()
        setupSTTCallbacks()

        if !settings.onboardingDone {
            onboarding = OnboardingWindow()
            onboarding?.show { [weak self] in
                self?.onboarding = nil
                self?.postOnboardingSetup()
            }
        } else {
            postOnboardingSetup()
        }
    }

    private func postOnboardingSetup() {
        appleSpeech.requestAuthorization()
        TextInjector.checkAccessibility()
        UpdateChecker.checkForUpdate()
        Log.info("Dict is running. Press Option+Space to dictate.")
        Log.info("STT engine: \(settings.sttEngine.rawValue)")
        Log.info("LLM cleanup: \(settings.llmEnabled ? "on" : "off")")
    }

    // MARK: - Main Menu (enables Cmd+C/V/X/A in text fields)

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        editMenuItem.title = "Edit"
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Dict")
        }

        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Dict — Voice to Text", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let modeLabel = settings.hotkeyMode == .toggle ? "toggle" : "push to talk"
        let shortcutItem = NSMenuItem(title: "Shortcut: Option+Space (\(modeLabel))", action: nil, keyEquivalent: "")
        shortcutItem.isEnabled = false
        menu.addItem(shortcutItem)

        menu.addItem(NSMenuItem.separator())

        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        let dictItem = NSMenuItem(title: "Edit Dictionary...", action: #selector(openDictionary), keyEquivalent: "d")
        dictItem.target = self
        menu.addItem(dictItem)

        let snippetsItem = NSMenuItem(title: "Edit Snippets...", action: #selector(openSnippets), keyEquivalent: "s")
        snippetsItem.target = self
        menu.addItem(snippetsItem)

        let accessibilityLabel = AXIsProcessTrusted() ? "Accessibility: Granted" : "Grant Accessibility..."
        let accessItem = NSMenuItem(title: accessibilityLabel, action: #selector(openAccessibility), keyEquivalent: "")
        accessItem.target = self
        accessItem.isEnabled = !AXIsProcessTrusted()
        menu.addItem(accessItem)

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        hotkeyManager.onPress = { [weak self] in
            guard let self = self else { return }
            switch self.settings.hotkeyMode {
            case .toggle:
                if self.isRecording { self.stopRecording() } else { self.startRecording() }
            case .pushToTalk:
                guard !self.isRecording else { return }
                self.startRecording()
                self.startPushToTalkMonitor()
            }
        }
        hotkeyManager.onRelease = { [weak self] in
            guard let self = self else { return }
            if self.settings.hotkeyMode == .pushToTalk && self.isRecording {
                self.stopRecording()
                self.stopPushToTalkMonitor()
            }
        }
        hotkeyManager.register()
    }

    private func startPushToTalkMonitor() {
        stopPushToTalkMonitor()
        // Monitor flagsChanged globally to detect Option key release,
        // since Carbon kEventHotKeyReleased is unreliable when the
        // modifier key is released before or simultaneously with Space.
        pushToTalkMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyUp]) { [weak self] event in
            guard let self = self, self.isRecording, self.settings.hotkeyMode == .pushToTalk else { return }

            if event.type == .flagsChanged {
                // Option key released
                if !event.modifierFlags.contains(.option) {
                    DispatchQueue.main.async {
                        self.stopRecording()
                        self.stopPushToTalkMonitor()
                    }
                }
            } else if event.type == .keyUp && event.keyCode == 49 {
                // Space released (while Option may still be held)
                DispatchQueue.main.async {
                    self.stopRecording()
                    self.stopPushToTalkMonitor()
                }
            }
        }
    }

    private func stopPushToTalkMonitor() {
        if let monitor = pushToTalkMonitor {
            NSEvent.removeMonitor(monitor)
            pushToTalkMonitor = nil
        }
    }

    // MARK: - STT Callbacks

    private func setupSTTCallbacks() {
        appleSpeech.onResult = { [weak self] text in
            self?.overlay.showProcessing()
            self?.handleTranscription(text)
        }
        appleSpeech.onPartialResult = { [weak self] text in
            self?.overlay.updateText(text)
        }
        appleSpeech.onError = { [weak self] error in
            Log.error("Apple Speech error: \(error)")
            self?.overlay.hide()
            self?.stopRecording()
        }
        appleSpeech.onAudioLevel = { [weak self] level in
            self?.overlay.updateLevel(level)
        }

        whisperSTT.onResult = { [weak self] text in
            self?.handleTranscription(text)
        }
        whisperSTT.onError = { [weak self] error in
            Log.error("Whisper error: \(error)")
            self?.overlay.hide()
            self?.stopRecording()
        }
        whisperSTT.onAudioLevel = { [weak self] level in
            self?.overlay.updateLevel(level)
        }
    }

    // MARK: - Recording

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        Log.info("Recording started (engine: \(settings.sttEngine.rawValue))")

        DispatchQueue.main.async {
            self.statusItem.button?.image = NSImage(
                systemSymbolName: "mic.fill",
                accessibilityDescription: "Recording"
            )
            self.overlay.show()
        }

        switch settings.sttEngine {
        case .apple:
            appleSpeech.startListening()
        case .whisper:
            whisperSTT.startRecording()
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        recordingStoppedAt = CFAbsoluteTimeGetCurrent()
        Log.info("Recording stopped")

        DispatchQueue.main.async {
            self.statusItem.button?.image = NSImage(
                systemSymbolName: "mic",
                accessibilityDescription: "Dict"
            )
            self.overlay.showProcessing()
        }

        switch settings.sttEngine {
        case .apple:
            appleSpeech.stopListening()
        case .whisper:
            whisperSTT.stopRecording()
        }
    }

    private func handleTranscription(_ text: String) {
        guard !text.isEmpty else {
            Log.info("Empty transcription, skipping.")
            DispatchQueue.main.async { self.overlay.hide() }
            return
        }

        let sttMs = Int((CFAbsoluteTimeGetCurrent() - recordingStoppedAt) * 1000)
        Log.info("Transcribed (\(sttMs)ms): \(text)")

        // Check for snippet match before LLM processing
        if let expansion = Snippets.shared.match(text) {
            Log.info("Snippet matched: \"\(text)\" → expanding")
            DispatchQueue.main.async { self.overlay.hide() }
            textInjector.type(expansion)
            Log.info("[Perf] Total: \(sttMs)ms (snippet)")
            return
        }

        // Detect frontmost app for context-aware LLM processing
        let frontmostApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        Log.info("Frontmost app: \(frontmostApp)")

        let llmStart = CFAbsoluteTimeGetCurrent()
        let engine = settings.sttEngine.rawValue

        llmProcessor.process(text, frontmostApp: frontmostApp) { [weak self] result in
            let llmMs = Int((CFAbsoluteTimeGetCurrent() - llmStart) * 1000)
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - (self?.recordingStoppedAt ?? llmStart)) * 1000)

            DispatchQueue.main.async {
                self?.overlay.hide()
                switch result {
                case .success(let cleaned):
                    Log.info("Final text: \(cleaned)")
                    Log.info("[Perf] STT: \(sttMs)ms | LLM: \(llmMs)ms | Total: \(totalMs)ms")
                    self?.textInjector.type(cleaned)
                    TranscriptionHistory.shared.add(raw: text, cleaned: cleaned, app: frontmostApp, engine: engine)
                case .failure(let error):
                    Log.error("LLM error: \(error). Using raw transcription.")
                    Log.info("[Perf] STT: \(sttMs)ms | LLM failed after \(llmMs)ms | Total: \(totalMs)ms")
                    self?.textInjector.type(text)
                    TranscriptionHistory.shared.add(raw: text, cleaned: text, app: frontmostApp, engine: engine)
                }
            }
        }
    }

    // MARK: - Menu Actions

    @objc private func openPreferences() {
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindow()
            preferencesWindow?.onSave = { [weak self] in
                self?.rebuildMenu()
            }
        }
        preferencesWindow?.show()
    }

    @objc private func openDictionary() {
        CustomDictionary.shared.save()
        let dictPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/dict/dictionary.json").path
        NSWorkspace.shared.open(URL(fileURLWithPath: dictPath))
    }

    @objc private func openAccessibility() {
        OnboardingWindow.openAccessibilitySettings()
    }

    @objc private func openSnippets() {
        Snippets.shared.save()
        let snippetsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/dict/snippets.json").path
        NSWorkspace.shared.open(URL(fileURLWithPath: snippetsPath))
    }

    @objc private func quit() {
        hotkeyManager.unregister()
        NSApplication.shared.terminate(nil)
    }
}
