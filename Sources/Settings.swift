import DictCore
import Foundation

/// Persistent settings stored in ~/.config/dict/config.json
class Settings {
    static let shared = Settings()

    private let configDir: URL
    private let configFile: URL
    private var data: SettingsData

    static let supportedLanguages: [(code: String, name: String)] = [
        ("en", "English"),
        ("pt", "Português (Brasil)"),
    ]

    typealias STTEngine = DictCore.STTEngine
    typealias HotkeyMode = DictCore.HotkeyMode
    typealias OverlayPosition = DictCore.OverlayPosition
    typealias LLMProvider = DictCore.LLMProvider
    typealias SettingsData = DictCore.SettingsData

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        configDir = home.appendingPathComponent(".config/dict")
        configFile = configDir.appendingPathComponent("config.json")
        data = SettingsData()
        load()
    }

    // MARK: - Accessors

    var hotkeyMode: HotkeyMode {
        get { data.hotkeyMode }
        set { data.hotkeyMode = newValue; save() }
    }

    var sttEngine: STTEngine {
        get { data.sttEngine }
        set { data.sttEngine = newValue; save() }
    }

    var whisperModelPath: String {
        get { data.whisperModelPath }
        set { data.whisperModelPath = newValue; save() }
    }

    var whisperLanguage: String {
        get { data.whisperLanguage }
        set { data.whisperLanguage = newValue; save() }
    }

    var llmEnabled: Bool {
        get { data.llmEnabled }
        set { data.llmEnabled = newValue; save() }
    }

    var llmEndpoint: String {
        get { data.llmEndpoint }
        set { data.llmEndpoint = newValue; save() }
    }

    var llmModel: String {
        get { data.llmModel }
        set { data.llmModel = newValue; save() }
    }

    var llmApiKey: String {
        get { data.llmApiKey }
        set { data.llmApiKey = newValue; save() }
    }

    var llmPrompt: String {
        get { data.llmPrompt }
        set { data.llmPrompt = newValue; save() }
    }

    var llmAccuracy: Int {
        get { data.llmAccuracy }
        set { data.llmAccuracy = newValue; save() }
    }

    var llmProvider: LLMProvider {
        get { data.llmProvider }
        set { data.llmProvider = newValue; save() }
    }

    var flowMode: Bool {
        get { data.flowMode }
        set { data.flowMode = newValue; save() }
    }

    var codeMode: Bool {
        get { data.codeMode }
        set { data.codeMode = newValue; save() }
    }

    var privacyMode: Bool {
        get { data.privacyMode }
        set { data.privacyMode = newValue; save() }
    }

    var verboseOverlay: Bool {
        get { data.verboseOverlay }
        set { data.verboseOverlay = newValue; save() }
    }

    var overlayPosition: OverlayPosition {
        get { data.overlayPosition }
        set { data.overlayPosition = newValue; save() }
    }

    var selectedMicrophoneUID: String {
        get { data.selectedMicrophoneUID }
        set { data.selectedMicrophoneUID = newValue; save() }
    }

    var onboardingDone: Bool {
        get { data.onboardingDone }
        set { data.onboardingDone = newValue; save() }
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: configFile.path) else { return }
        do {
            let jsonData = try Data(contentsOf: configFile)
            data = try JSONDecoder().decode(SettingsData.self, from: jsonData)
        } catch {
            Log.info("Failed to load settings: \(error). Using defaults.")
        }
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            let jsonData = try JSONEncoder().encode(data)
            let json = try JSONSerialization.jsonObject(with: jsonData)
            let prettyData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try prettyData.write(to: configFile)
        } catch {
            Log.info("Failed to save settings: \(error)")
        }
    }
}
