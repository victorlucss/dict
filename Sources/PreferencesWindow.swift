import AppKit

class PreferencesWindow: NSWindow, NSTextViewDelegate, NSTextFieldDelegate {
    private let settings = Settings.shared
    var onSave: (() -> Void)?

    // Sidebar
    private var sidebarButtons: [NSButton] = []
    private var currentSection = 0
    private var contentContainer: NSView!
    private var sectionTitleLabel: NSTextField!

    // General controls
    private var hotkeyModePopUp: NSPopUpButton!
    private var languagePopUp: NSPopUpButton!
    private var flowModeSwitch: NSSwitch!
    private var codeModeSwitch: NSSwitch!
    private var privacyModeSwitch: NSSwitch!

    // Speech controls
    private var enginePopUp: NSPopUpButton!
    private var whisperModelField: NSTextField!
    private var whisperBrowseButton: NSButton!
    private var whisperModelLabel: NSTextField!

    // LLM controls
    private var llmEnabledSwitch: NSSwitch!
    private var accuracySlider: NSSlider!
    private var accuracyLabel: NSTextField!
    private var providerPopUp: NSPopUpButton!
    private var endpointField: NSTextField!
    private var endpointLabel: NSTextField!
    private var modelField: NSTextField!
    private var apiKeyField: NSSecureTextField!
    private var apiKeyLabel: NSTextField!
    private var systemPromptView: NSTextView!

    // Overlay controls
    private var verboseOverlaySwitch: NSSwitch!
    private var overlayPositionPopUp: NSPopUpButton!

    // Section views
    private var sectionViews: [NSView] = []

    private let sidebarWidth: CGFloat = 160
    private let sections: [(title: String, icon: String)] = [
        ("General", "gearshape"),
        ("Speech", "waveform"),
        ("LLM", "brain"),
        ("Overlay", "rectangle.inset.filled"),
        ("Files", "folder"),
    ]

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 480),
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
        selectSection(0)
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - UI Construction

    private func buildUI() {
        let root = NSView()
        root.wantsLayer = true
        self.contentView = root

        // Sidebar
        let sidebar = NSView()
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidebar)

        let sidebarStack = NSStackView()
        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .leading
        sidebarStack.spacing = 2
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarStack)

        for (i, section) in sections.enumerated() {
            let button = createSidebarButton(title: section.title, icon: section.icon, tag: i)
            sidebarButtons.append(button)
            sidebarStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: sidebarWidth - 16).isActive = true
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        }

        // Separator line between sidebar and content
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(divider)

        // Content pane
        let contentPane = NSView()
        contentPane.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(contentPane)

        // Section title
        sectionTitleLabel = NSTextField(labelWithString: "General")
        sectionTitleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        sectionTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentPane.addSubview(sectionTitleLabel)

        // Scrollable content container (swapped per section)
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        contentContainer = FlippedView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = contentContainer
        contentPane.addSubview(scrollView)

        // Save button
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveClicked))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        contentPane.addSubview(saveButton)

        // Layout
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: sidebarWidth),

            sidebarStack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 12),
            sidebarStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -8),

            divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            divider.topAnchor.constraint(equalTo: root.topAnchor),
            divider.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            contentPane.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            contentPane.topAnchor.constraint(equalTo: root.topAnchor),
            contentPane.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            contentPane.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            sectionTitleLabel.topAnchor.constraint(equalTo: contentPane.topAnchor, constant: 20),
            sectionTitleLabel.leadingAnchor.constraint(equalTo: contentPane.leadingAnchor, constant: 24),

            scrollView.topAnchor.constraint(equalTo: sectionTitleLabel.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: contentPane.leadingAnchor, constant: 24),
            scrollView.trailingAnchor.constraint(equalTo: contentPane.trailingAnchor, constant: -24),
            scrollView.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -16),

            saveButton.trailingAnchor.constraint(equalTo: contentPane.trailingAnchor, constant: -24),
            saveButton.bottomAnchor.constraint(equalTo: contentPane.bottomAnchor, constant: -16),
            saveButton.widthAnchor.constraint(equalToConstant: 80),
        ])

        // Build section content views
        sectionViews = [
            buildGeneralSection(),
            buildSpeechSection(),
            buildLLMSection(),
            buildOverlaySection(),
            buildFilesSection(),
        ]

        selectSection(0)
    }

    // MARK: - Sidebar

    private func createSidebarButton(title: String, icon: String, tag: Int) -> NSButton {
        let button = NSButton()
        button.tag = tag
        button.target = self
        button.action = #selector(sidebarClicked(_:))
        button.bezelStyle = .recessed
        button.isBordered = false
        button.imagePosition = .imageLeading
        button.alignment = .left
        button.font = .systemFont(ofSize: 13)
        button.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)
        button.title = " \(title)"
        button.contentTintColor = .labelColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        return button
    }

    @objc private func sidebarClicked(_ sender: NSButton) {
        selectSection(sender.tag)
    }

    private func selectSection(_ index: Int) {
        currentSection = index

        // Update sidebar highlight
        for (i, button) in sidebarButtons.enumerated() {
            if i == index {
                button.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
                button.contentTintColor = .controlAccentColor
            } else {
                button.layer?.backgroundColor = nil
                button.contentTintColor = .labelColor
            }
        }

        // Update title
        sectionTitleLabel.stringValue = sections[index].title

        // Swap content
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        let sectionView = sectionViews[index]
        sectionView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(sectionView)

        guard let scrollView = contentContainer.enclosingScrollView else { return }
        NSLayoutConstraint.activate([
            sectionView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            sectionView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            sectionView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            sectionView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            contentContainer.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
        contentContainer.layoutSubtreeIfNeeded()
        scrollView.documentView = contentContainer
    }

    // MARK: - Section Builders

    private func buildGeneralSection() -> NSView {
        let card = createCard()
        let stack = cardStack()

        hotkeyModePopUp = NSPopUpButton()
        hotkeyModePopUp.addItems(withTitles: ["Toggle (press to start/stop)", "Push to Talk (hold to record)"])
        stack.addArrangedSubview(settingRow(label: "Hotkey Mode", control: hotkeyModePopUp))

        languagePopUp = NSPopUpButton()
        for lang in Settings.supportedLanguages {
            languagePopUp.addItem(withTitle: lang.name)
            languagePopUp.lastItem?.representedObject = lang.code
        }
        stack.addArrangedSubview(settingRow(label: "Language", control: languagePopUp))

        flowModeSwitch = NSSwitch()
        let flowRow = settingRow(label: "Flow Mode", control: flowModeSwitch,
                                  hint: "Auto-press Return after pasting")
        stack.addArrangedSubview(flowRow)

        codeModeSwitch = NSSwitch()
        stack.addArrangedSubview(settingRow(label: "Code Mode", control: codeModeSwitch))

        privacyModeSwitch = NSSwitch()
        stack.addArrangedSubview(settingRow(label: "Privacy Mode", control: privacyModeSwitch))

        card.addSubview(stack)
        pinInside(stack, to: card, padding: 16)
        return card
    }

    private func buildSpeechSection() -> NSView {
        let card = createCard()
        let stack = cardStack()

        enginePopUp = NSPopUpButton()
        enginePopUp.addItems(withTitles: ["Apple Speech", "Whisper"])
        enginePopUp.target = self
        enginePopUp.action = #selector(engineChanged)
        stack.addArrangedSubview(settingRow(label: "STT Engine", control: enginePopUp))

        whisperModelField = NSTextField()
        whisperModelField.placeholderString = "/path/to/ggml-model.bin"
        whisperBrowseButton = NSButton(title: "Browse...", target: self, action: #selector(browseWhisperModel))
        whisperBrowseButton.bezelStyle = .rounded

        let modelRow = NSStackView()
        modelRow.orientation = .horizontal
        modelRow.spacing = 8
        whisperModelField.translatesAutoresizingMaskIntoConstraints = false
        modelRow.addArrangedSubview(whisperModelField)
        modelRow.addArrangedSubview(whisperBrowseButton)
        whisperModelField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        whisperModelLabel = NSTextField(labelWithString: "Whisper Model")
        let whisperRow = settingRow(labelView: whisperModelLabel, control: modelRow)
        stack.addArrangedSubview(whisperRow)

        card.addSubview(stack)
        pinInside(stack, to: card, padding: 16)
        return card
    }

    private func buildLLMSection() -> NSView {
        let card = createCard()
        let stack = cardStack()

        llmEnabledSwitch = NSSwitch()
        stack.addArrangedSubview(settingRow(label: "LLM Enabled", control: llmEnabledSwitch))

        // Accuracy slider: 1 (minimal cleanup) to 5 (aggressive rewriting)
        accuracySlider = NSSlider(value: 3, minValue: 1, maxValue: 5, target: self, action: #selector(accuracyChanged))
        accuracySlider.numberOfTickMarks = 5
        accuracySlider.allowsTickMarkValuesOnly = true
        accuracySlider.translatesAutoresizingMaskIntoConstraints = false
        accuracySlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        accuracyLabel = NSTextField(labelWithString: "Balanced")
        accuracyLabel.font = .systemFont(ofSize: 11)
        accuracyLabel.textColor = .secondaryLabelColor
        accuracyLabel.translatesAutoresizingMaskIntoConstraints = false
        accuracyLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 70).isActive = true

        let sliderRow = NSStackView(views: [accuracySlider, accuracyLabel])
        sliderRow.orientation = .horizontal
        sliderRow.spacing = 8
        sliderRow.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(settingRow(label: "Correction Level", control: sliderRow))

        providerPopUp = NSPopUpButton()
        providerPopUp.addItems(withTitles: ["OpenAI", "Anthropic", "Ollama", "LM Studio"])
        providerPopUp.target = self
        providerPopUp.action = #selector(providerChanged)
        stack.addArrangedSubview(settingRow(label: "Provider", control: providerPopUp))

        modelField = NSTextField()
        modelField.placeholderString = "llama3.2"
        stack.addArrangedSubview(settingRow(label: "Model", control: modelField))

        endpointField = NSTextField()
        endpointField.placeholderString = "http://localhost:11434/v1/chat/completions"
        endpointLabel = NSTextField(labelWithString: "Endpoint")
        stack.addArrangedSubview(settingRow(labelView: endpointLabel, control: endpointField))

        apiKeyField = NSSecureTextField()
        apiKeyField.placeholderString = "sk-..."
        apiKeyLabel = NSTextField(labelWithString: "API Key")
        stack.addArrangedSubview(settingRow(labelView: apiKeyLabel, control: apiKeyField))

        // System prompt
        let promptLabel = NSTextField(labelWithString: "System Prompt")
        promptLabel.font = .systemFont(ofSize: 13)
        promptLabel.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 100).isActive = true

        systemPromptView = NSTextView()
        systemPromptView.isEditable = true
        systemPromptView.isRichText = false
        systemPromptView.font = .systemFont(ofSize: 12)
        systemPromptView.isAutomaticQuoteSubstitutionEnabled = false
        systemPromptView.isAutomaticDashSubstitutionEnabled = false
        systemPromptView.textContainerInset = NSSize(width: 4, height: 4)
        systemPromptView.minSize = NSSize(width: 0, height: 100)
        systemPromptView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        systemPromptView.isVerticallyResizable = true
        systemPromptView.textContainer?.widthTracksTextView = true
        systemPromptView.autoresizingMask = [.width]
        scrollView.documentView = systemPromptView

        let promptRow = NSStackView()
        promptRow.orientation = .vertical
        promptRow.alignment = .width
        promptRow.spacing = 6
        promptRow.addArrangedSubview(promptLabel)
        promptRow.addArrangedSubview(scrollView)

        stack.addArrangedSubview(promptRow)
        promptRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        card.addSubview(stack)
        pinInside(stack, to: card, padding: 16)
        return card
    }

    private func buildOverlaySection() -> NSView {
        let card = createCard()
        let stack = cardStack()

        verboseOverlaySwitch = NSSwitch()
        stack.addArrangedSubview(settingRow(label: "Verbose Overlay", control: verboseOverlaySwitch))

        overlayPositionPopUp = NSPopUpButton()
        overlayPositionPopUp.addItems(withTitles: ["Top", "Bottom"])
        stack.addArrangedSubview(settingRow(label: "Overlay Position", control: overlayPositionPopUp))

        card.addSubview(stack)
        pinInside(stack, to: card, padding: 16)
        return card
    }

    private func buildFilesSection() -> NSView {
        let card = createCard()
        let stack = cardStack()

        let dictButton = NSButton(title: "Edit Dictionary...", target: self, action: #selector(openDictionary))
        dictButton.bezelStyle = .rounded
        stack.addArrangedSubview(dictButton)

        let snippetsButton = NSButton(title: "Edit Snippets...", target: self, action: #selector(openSnippets))
        snippetsButton.bezelStyle = .rounded
        stack.addArrangedSubview(snippetsButton)

        let commandsButton = NSButton(title: "Edit Commands...", target: self, action: #selector(openCommands))
        commandsButton.bezelStyle = .rounded
        stack.addArrangedSubview(commandsButton)

        card.addSubview(stack)
        pinInside(stack, to: card, padding: 16)
        return card
    }

    // MARK: - Card & Row Helpers

    private func createCard() -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        box.layer?.cornerRadius = 10
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }

    private func cardStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func settingRow(label: String, control: NSView, hint: String? = nil) -> NSView {
        let labelView = NSTextField(labelWithString: label)
        return settingRow(labelView: labelView, control: control, hint: hint)
    }

    private func settingRow(labelView: NSTextField, control: NSView, hint: String? = nil) -> NSView {
        labelView.font = .systemFont(ofSize: 13)
        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        labelView.setContentCompressionResistancePriority(.required, for: .horizontal)
        labelView.widthAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true

        control.translatesAutoresizingMaskIntoConstraints = false

        if let hint = hint {
            let hintLabel = NSTextField(labelWithString: hint)
            hintLabel.font = .systemFont(ofSize: 11)
            hintLabel.textColor = .secondaryLabelColor
            hintLabel.translatesAutoresizingMaskIntoConstraints = false

            let rightStack = NSStackView(views: [control, hintLabel])
            rightStack.orientation = .horizontal
            rightStack.spacing = 8
            rightStack.translatesAutoresizingMaskIntoConstraints = false

            let row = NSStackView(views: [labelView, rightStack])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 12
            row.translatesAutoresizingMaskIntoConstraints = false
            rightStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
            return row
        }

        let row = NSStackView(views: [labelView, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        if control is NSPopUpButton || control is NSTextField || control is NSSecureTextField || control is NSStackView {
            control.setContentHuggingPriority(.defaultLow, for: .horizontal)
            row.distribution = .fill
        }

        return row
    }

    private func pinInside(_ child: NSView, to parent: NSView, padding: CGFloat) {
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor, constant: padding),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: padding),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -padding),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -padding),
        ])
    }

    // MARK: - Load/Save

    private func loadValues() {
        hotkeyModePopUp.selectItem(at: settings.hotkeyMode == .toggle ? 0 : 1)
        languagePopUp.selectItem(at:
            Settings.supportedLanguages.firstIndex(where: { $0.code == settings.whisperLanguage }) ?? 0)

        enginePopUp.selectItem(at: settings.sttEngine == .apple ? 0 : 1)
        whisperModelField.stringValue = settings.whisperModelPath
        updateWhisperVisibility()

        flowModeSwitch.state = settings.flowMode ? .on : .off
        codeModeSwitch.state = settings.codeMode ? .on : .off
        privacyModeSwitch.state = settings.privacyMode ? .on : .off

        verboseOverlaySwitch.state = settings.verboseOverlay ? .on : .off
        overlayPositionPopUp.selectItem(at: settings.overlayPosition == .top ? 0 : 1)

        llmEnabledSwitch.state = settings.llmEnabled ? .on : .off
        accuracySlider.doubleValue = Double(settings.llmAccuracy)
        accuracyLabel.stringValue = accuracyLabelText(for: settings.llmAccuracy)
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

        // Show/hide endpoint and API key rows
        endpointLabel.superview?.isHidden = false
        apiKeyLabel.superview?.isHidden = !isCloud

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

    private func updateWhisperVisibility() {
        let isWhisper = enginePopUp.indexOfSelectedItem == 1
        whisperModelLabel.superview?.isHidden = !isWhisper
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
        settings.llmAccuracy = Int(accuracySlider.doubleValue)
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

    @objc private func accuracyChanged() {
        accuracyLabel.stringValue = accuracyLabelText(for: Int(accuracySlider.doubleValue))
    }

    private func accuracyLabelText(for value: Int) -> String {
        switch value {
        case 1: return "Minimal"
        case 2: return "Light"
        case 3: return "Balanced"
        case 4: return "Thorough"
        default: return "Aggressive"
        }
    }

    @objc private func engineChanged() {
        updateWhisperVisibility()
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

    @objc private func openCommands() {
        VoiceCommands.shared.save()
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/dict/commands.json").path
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

/// NSView subclass that flips the coordinate system so content lays out from the top.
private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
