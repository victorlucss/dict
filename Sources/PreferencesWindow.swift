import AppKit

class PreferencesWindow: NSWindow, NSTextViewDelegate, NSTextFieldDelegate {
    private let settings = Settings.shared
    var onSave: (() -> Void)?

    // General controls
    private var hotkeyModePopUp: NSPopUpButton!
    private var enginePopUp: NSPopUpButton!
    private var languagePopUp: NSPopUpButton!
    private var whisperModelField: NSTextField!
    private var flowModeSwitch: NSSwitch!
    private var codeModeSwitch: NSSwitch!
    private var privacyModeSwitch: NSSwitch!
    private var verboseOverlaySwitch: NSSwitch!
    private var overlayPositionPopUp: NSPopUpButton!

    // LLM controls
    private var llmEnabledSwitch: NSSwitch!
    private var providerPopUp: NSPopUpButton!
    private var endpointField: NSTextField!
    private var modelField: NSTextField!
    private var apiKeyField: NSSecureTextField!
    private var systemPromptView: NSTextView!

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 832),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "Dict Preferences"
        isReleasedWhenClosed = false
        center()
        buildUI()
        loadValues()
    }

    func show() {
        loadValues()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - UI Construction

    private func buildUI() {
        let contentView = NSView(frame: contentRect(forFrameRect: frame))
        self.contentView = contentView

        var y = contentView.bounds.height - 40
        let labelX: CGFloat = 20
        let controlX: CGFloat = 170
        let controlWidth: CGFloat = 310
        let rowHeight: CGFloat = 32

        // --- General Section ---
        y = addSectionHeader("General", at: y, in: contentView)

        // Hotkey Mode
        y -= rowHeight
        addLabel("Hotkey Mode:", at: NSPoint(x: labelX, y: y + 2), in: contentView)
        hotkeyModePopUp = NSPopUpButton(frame: NSRect(x: controlX, y: y, width: controlWidth, height: 26))
        hotkeyModePopUp.addItems(withTitles: ["Toggle (press to start/stop)", "Push to Talk (hold to record)"])
        contentView.addSubview(hotkeyModePopUp)

        // STT Engine
        y -= rowHeight
        addLabel("STT Engine:", at: NSPoint(x: labelX, y: y + 2), in: contentView)
        enginePopUp = NSPopUpButton(frame: NSRect(x: controlX, y: y, width: controlWidth, height: 26))
        enginePopUp.addItems(withTitles: ["Apple Speech", "Whisper"])
        contentView.addSubview(enginePopUp)

        // Language
        y -= rowHeight
        addLabel("Language:", at: NSPoint(x: labelX, y: y + 2), in: contentView)
        languagePopUp = NSPopUpButton(frame: NSRect(x: controlX, y: y, width: controlWidth, height: 26))
        for lang in Settings.supportedLanguages {
            languagePopUp.addItem(withTitle: lang.name)
            languagePopUp.lastItem?.representedObject = lang.code
        }
        contentView.addSubview(languagePopUp)

        // Whisper Model Path
        y -= rowHeight
        addLabel("Whisper Model:", at: NSPoint(x: labelX, y: y + 2), in: contentView)
        whisperModelField = NSTextField(frame: NSRect(x: controlX, y: y, width: controlWidth - 80, height: 24))
        whisperModelField.placeholderString = "/path/to/ggml-model.bin"
        contentView.addSubview(whisperModelField)

        let browseButton = NSButton(title: "Browse...", target: self, action: #selector(browseWhisperModel))
        browseButton.frame = NSRect(x: controlX + controlWidth - 74, y: y, width: 80, height: 24)
        browseButton.bezelStyle = .rounded
        contentView.addSubview(browseButton)

        // Flow Mode
        y -= rowHeight
        addLabel("Flow Mode:", at: NSPoint(x: labelX, y: y + 2), in: contentView)
        flowModeSwitch = NSSwitch(frame: NSRect(x: controlX, y: y, width: 40, height: 24))
        contentView.addSubview(flowModeSwitch)
        let flowHint = NSTextField(labelWithString: "Auto-press Return after pasting")
        flowHint.frame = NSRect(x: controlX + 52, y: y + 4, width: 250, height: 16)
        flowHint.font = .systemFont(ofSize: 11)
        flowHint.textColor = .secondaryLabelColor
        contentView.addSubview(flowHint)

        // Code Mode
        y -= rowHeight
        addLabel("Code Mode:", at: NSPoint(x: labelX, y: y + 2), in: contentView)
        codeModeSwitch = NSSwitch(frame: NSRect(x: controlX, y: y, width: 40, height: 24))
        contentView.addSubview(codeModeSwitch)

        // Privacy Mode
        y -= rowHeight
        addLabel("Privacy Mode:", at: NSPoint(x: labelX, y: y + 2), in: contentView)
        privacyModeSwitch = NSSwitch(frame: NSRect(x: controlX, y: y, width: 40, height: 24))
        contentView.addSubview(privacyModeSwitch)

        // Verbose Overlay
        y -= rowHeight
        addLabel("Verbose Overlay:", at: NSPoint(x: labelX, y: y + 2), in: contentView)
        verboseOverlaySwitch = NSSwitch(frame: NSRect(x: controlX, y: y, width: 40, height: 24))
        contentView.addSubview(verboseOverlaySwitch)

        // Overlay Position
        y -= rowHeight
        addLabel("Overlay Position:", at: NSPoint(x: labelX, y: y + 2), in: contentView)
        overlayPositionPopUp = NSPopUpButton(frame: NSRect(x: controlX, y: y, width: controlWidth, height: 26))
        overlayPositionPopUp.addItems(withTitles: ["Top", "Bottom"])
        contentView.addSubview(overlayPositionPopUp)

        // --- LLM Section ---
        y -= 16
        y = addSectionHeader("LLM", at: y, in: contentView)

        // LLM Enabled
        y -= rowHeight
        addLabel("LLM Enabled:", at: NSPoint(x: labelX, y: y + 2), in: contentView)
        llmEnabledSwitch = NSSwitch(frame: NSRect(x: controlX, y: y, width: 40, height: 24))
        contentView.addSubview(llmEnabledSwitch)

        // Provider
        y -= rowHeight
        addLabel("Provider:", at: NSPoint(x: labelX, y: y + 2), in: contentView)
        providerPopUp = NSPopUpButton(frame: NSRect(x: controlX, y: y, width: controlWidth, height: 26))
        providerPopUp.addItems(withTitles: ["OpenAI", "Anthropic", "Ollama", "LM Studio"])
        providerPopUp.target = self
        providerPopUp.action = #selector(providerChanged)
        contentView.addSubview(providerPopUp)

        // Endpoint
        y -= rowHeight
        addLabel("Endpoint:", at: NSPoint(x: labelX, y: y + 2), in: contentView)
        endpointField = NSTextField(frame: NSRect(x: controlX, y: y, width: controlWidth, height: 24))
        endpointField.placeholderString = "Ollama :11434 / LM Studio :1234 — must end with /v1/chat/completions"
        contentView.addSubview(endpointField)

        // Model
        y -= rowHeight
        addLabel("Model:", at: NSPoint(x: labelX, y: y + 2), in: contentView)
        modelField = NSTextField(frame: NSRect(x: controlX, y: y, width: controlWidth, height: 24))
        modelField.placeholderString = "llama3.2"
        contentView.addSubview(modelField)

        // API Key
        y -= rowHeight
        addLabel("API Key:", at: NSPoint(x: labelX, y: y + 2), in: contentView)
        apiKeyField = NSSecureTextField(frame: NSRect(x: controlX, y: y, width: controlWidth, height: 24))
        apiKeyField.placeholderString = "sk-..."
        contentView.addSubview(apiKeyField)

        // System Prompt
        y -= rowHeight
        addLabel("System Prompt:", at: NSPoint(x: labelX, y: y + 2), in: contentView)

        let promptHeight: CGFloat = 100
        y -= promptHeight - rowHeight + 8
        let scrollView = NSScrollView(frame: NSRect(x: controlX, y: y, width: controlWidth, height: promptHeight))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        systemPromptView = NSTextView(frame: NSRect(x: 0, y: 0, width: controlWidth - 2, height: promptHeight))
        systemPromptView.isEditable = true
        systemPromptView.isRichText = false
        systemPromptView.font = .systemFont(ofSize: 12)
        systemPromptView.isAutomaticQuoteSubstitutionEnabled = false
        systemPromptView.isAutomaticDashSubstitutionEnabled = false
        systemPromptView.textContainerInset = NSSize(width: 4, height: 4)
        systemPromptView.minSize = NSSize(width: 0, height: promptHeight)
        systemPromptView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        systemPromptView.isVerticallyResizable = true
        systemPromptView.textContainer?.widthTracksTextView = true
        scrollView.documentView = systemPromptView
        contentView.addSubview(scrollView)

        // --- Files Section ---
        y -= 16
        y = addSectionHeader("Files", at: y, in: contentView)

        y -= rowHeight
        let dictButton = NSButton(title: "Edit Dictionary...", target: self, action: #selector(openDictionary))
        dictButton.frame = NSRect(x: controlX, y: y, width: 140, height: 24)
        dictButton.bezelStyle = .rounded
        contentView.addSubview(dictButton)

        let snippetsButton = NSButton(title: "Edit Snippets...", target: self, action: #selector(openSnippets))
        snippetsButton.frame = NSRect(x: controlX + 150, y: y, width: 140, height: 24)
        snippetsButton.bezelStyle = .rounded
        contentView.addSubview(snippetsButton)

        // --- Save Button ---
        y -= 48
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveClicked))
        saveButton.frame = NSRect(x: contentView.bounds.width - 100, y: y, width: 80, height: 32)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)
    }

    private func addLabel(_ text: String, at origin: NSPoint, in view: NSView) {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: origin.x, y: origin.y, width: 140, height: 20)
        label.alignment = .right
        label.font = .systemFont(ofSize: 13)
        view.addSubview(label)
    }

    private func addSectionHeader(_ text: String, at y: CGFloat, in view: NSView) -> CGFloat {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: 20, y: y - 24, width: 460, height: 20)
        label.font = .boldSystemFont(ofSize: 13)
        view.addSubview(label)

        let separator = NSBox(frame: NSRect(x: 20, y: y - 28, width: 480, height: 1))
        separator.boxType = .separator
        view.addSubview(separator)

        return y - 32
    }

    // MARK: - Load/Save

    private func loadValues() {
        hotkeyModePopUp.selectItem(at: settings.hotkeyMode == .toggle ? 0 : 1)
        enginePopUp.selectItem(at: settings.sttEngine == .apple ? 0 : 1)

        if let idx = Settings.supportedLanguages.firstIndex(where: { $0.code == settings.whisperLanguage }) {
            languagePopUp.selectItem(at: idx)
        }

        whisperModelField.stringValue = settings.whisperModelPath
        flowModeSwitch.state = settings.flowMode ? .on : .off
        codeModeSwitch.state = settings.codeMode ? .on : .off
        privacyModeSwitch.state = settings.privacyMode ? .on : .off
        verboseOverlaySwitch.state = settings.verboseOverlay ? .on : .off
        overlayPositionPopUp.selectItem(at: settings.overlayPosition == .top ? 0 : 1)

        llmEnabledSwitch.state = settings.llmEnabled ? .on : .off
        switch settings.llmProvider {
        case .openai: providerPopUp.selectItem(at: 0)
        case .anthropic: providerPopUp.selectItem(at: 1)
        case .ollama: providerPopUp.selectItem(at: 2)
        case .lmstudio: providerPopUp.selectItem(at: 3)
        }
        endpointField.stringValue = settings.llmEndpoint
        modelField.stringValue = settings.llmModel
        apiKeyField.stringValue = settings.llmApiKey
        systemPromptView.string = settings.llmPrompt
        updateFieldStates()
    }

    private func selectedProvider() -> Settings.LLMProvider {
        switch providerPopUp.indexOfSelectedItem {
        case 0: return .openai
        case 1: return .anthropic
        case 2: return .ollama
        default: return .lmstudio
        }
    }

    private func updateFieldStates() {
        let provider = selectedProvider()
        let isCloud = provider == .openai || provider == .anthropic
        endpointField.isEnabled = false
        apiKeyField.isEnabled = isCloud
        switch provider {
        case .openai:
            endpointField.stringValue = ""
            endpointField.placeholderString = "https://api.openai.com/v1/chat/completions"
        case .anthropic:
            endpointField.stringValue = ""
            endpointField.placeholderString = "https://api.anthropic.com/v1/messages"
        case .ollama:
            endpointField.stringValue = ""
            endpointField.placeholderString = "http://localhost:11434/v1/chat/completions"
            apiKeyField.stringValue = ""
        case .lmstudio:
            endpointField.stringValue = ""
            endpointField.placeholderString = "http://localhost:1234/v1/chat/completions"
            apiKeyField.stringValue = ""
        }
    }

    @objc private func saveClicked() {
        settings.hotkeyMode = hotkeyModePopUp.indexOfSelectedItem == 0 ? .toggle : .pushToTalk
        settings.sttEngine = enginePopUp.indexOfSelectedItem == 0 ? .apple : .whisper
        if let code = languagePopUp.selectedItem?.representedObject as? String {
            settings.whisperLanguage = code
        }
        settings.whisperModelPath = whisperModelField.stringValue
        settings.flowMode = flowModeSwitch.state == .on
        settings.codeMode = codeModeSwitch.state == .on
        settings.privacyMode = privacyModeSwitch.state == .on
        settings.verboseOverlay = verboseOverlaySwitch.state == .on
        settings.overlayPosition = overlayPositionPopUp.indexOfSelectedItem == 0 ? .top : .bottom
        settings.llmEnabled = llmEnabledSwitch.state == .on
        settings.llmProvider = selectedProvider()
        settings.llmEndpoint = endpointField.stringValue
        settings.llmModel = modelField.stringValue
        settings.llmApiKey = apiKeyField.stringValue
        settings.llmPrompt = systemPromptView.string

        Log.info("Settings saved.")
        onSave?()
        close()
    }

    // MARK: - Actions

    @objc private func providerChanged() {
        updateFieldStates()
    }

    @objc private func browseWhisperModel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.data]
        panel.message = "Select a Whisper GGML model file"

        if panel.runModal() == .OK, let url = panel.url {
            whisperModelField.stringValue = url.path
        }
    }

    @objc private func openDictionary() {
        CustomDictionary.shared.save()
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/dict/dictionary.json").path
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func openSnippets() {
        Snippets.shared.save()
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/dict/snippets.json").path
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
