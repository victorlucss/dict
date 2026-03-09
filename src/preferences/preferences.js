const { invoke } = window.__TAURI__.core;

let currentSettings = null;
let platform = 'macos';

const ACCURACY_LABELS = { 1: 'Minimal', 2: 'Light', 3: 'Balanced', 4: 'Thorough', 5: 'Aggressive' };

// Sidebar navigation
document.querySelectorAll('.sidebar-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.sidebar-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');

        const section = btn.dataset.section;
        document.getElementById('section-title').textContent =
            section.charAt(0).toUpperCase() + section.slice(1);

        document.querySelectorAll('.section').forEach(s => s.classList.add('hidden'));
        document.getElementById(`section-${section}`).classList.remove('hidden');

        // Refresh audio devices when speech section is opened
        if (section === 'speech') refreshAudioDevices();
    });
});

// Accuracy slider
document.getElementById('llmAccuracy').addEventListener('input', (e) => {
    document.getElementById('accuracyLabel').textContent = ACCURACY_LABELS[e.target.value] || 'Balanced';
});

// Provider changes
document.getElementById('llmProvider').addEventListener('change', updateProviderFields);

// STT engine changes
document.getElementById('sttEngine').addEventListener('change', updateEngineFields);

// Save
document.getElementById('saveBtn').addEventListener('click', saveSettings);

// File edit buttons
document.getElementById('editDictionary')?.addEventListener('click', () => {
    invoke('open_config_file', { name: 'dictionary.json' }).catch(console.error);
});
document.getElementById('editSnippets')?.addEventListener('click', () => {
    invoke('open_config_file', { name: 'snippets.json' }).catch(console.error);
});
document.getElementById('editCommands')?.addEventListener('click', () => {
    invoke('open_config_file', { name: 'commands.json' }).catch(console.error);
});

async function init() {
    platform = await invoke('get_platform');
    currentSettings = await invoke('get_settings');
    loadValues(currentSettings);
    updateEngineFields();
    updateProviderFields();
}

function loadValues(s) {
    document.getElementById('hotkeyMode').value = s.hotkeyMode;
    document.getElementById('language').value = s.whisperLanguage;
    document.getElementById('flowMode').checked = s.flowMode;
    document.getElementById('codeMode').checked = s.codeMode;
    document.getElementById('privacyMode').checked = s.privacyMode;

    document.getElementById('sttEngine').value = s.sttEngine;
    document.getElementById('whisperModelPath').value = s.whisperModelPath;

    document.getElementById('llmEnabled').checked = s.llmEnabled;
    document.getElementById('llmAccuracy').value = s.llmAccuracy;
    document.getElementById('accuracyLabel').textContent = ACCURACY_LABELS[s.llmAccuracy] || 'Balanced';
    document.getElementById('llmProvider').value = s.llmProvider;
    document.getElementById('llmModel').value = s.llmModel;
    document.getElementById('llmEndpoint').value = s.llmEndpoint;
    document.getElementById('llmApiKey').value = s.llmApiKey;
    document.getElementById('llmPrompt').value = s.llmPrompt;

    document.getElementById('verboseOverlay').checked = s.verboseOverlay;
    document.getElementById('overlayPosition').value = s.overlayPosition;

    // Hide Apple Speech on non-macOS
    if (platform !== 'macos') {
        const appleOption = document.querySelector('#sttEngine option[value="apple"]');
        if (appleOption) appleOption.remove();
    }
}

function updateEngineFields() {
    const engine = document.getElementById('sttEngine').value;
    const whisperRow = document.getElementById('whisperModelRow');
    whisperRow.style.display = engine === 'whisper' ? 'flex' : 'none';
}

function updateProviderFields() {
    const provider = document.getElementById('llmProvider').value;
    const isCloud = provider === 'openai' || provider === 'anthropic';

    document.getElementById('llmEndpoint').disabled = true;
    document.getElementById('apiKeyRow').style.display = isCloud ? 'flex' : 'none';

    const placeholders = {
        openai: 'https://api.openai.com/v1/chat/completions',
        anthropic: 'https://api.anthropic.com/v1/messages',
        ollama: 'http://localhost:11434/v1/chat/completions',
        lmstudio: 'http://localhost:1234/v1/chat/completions'
    };
    document.getElementById('llmEndpoint').placeholder = placeholders[provider] || '';
}

async function saveSettings() {
    const data = {
        hotkeyMode: document.getElementById('hotkeyMode').value,
        sttEngine: document.getElementById('sttEngine').value,
        whisperModelPath: document.getElementById('whisperModelPath').value,
        whisperLanguage: document.getElementById('language').value,
        llmEnabled: document.getElementById('llmEnabled').checked,
        llmEndpoint: document.getElementById('llmEndpoint').value,
        llmModel: document.getElementById('llmModel').value,
        llmApiKey: document.getElementById('llmApiKey').value,
        llmProvider: document.getElementById('llmProvider').value,
        llmPrompt: document.getElementById('llmPrompt').value,
        llmAccuracy: parseInt(document.getElementById('llmAccuracy').value),
        flowMode: document.getElementById('flowMode').checked,
        codeMode: document.getElementById('codeMode').checked,
        privacyMode: document.getElementById('privacyMode').checked,
        verboseOverlay: document.getElementById('verboseOverlay').checked,
        overlayPosition: document.getElementById('overlayPosition').value,
        onboardingDone: currentSettings?.onboardingDone ?? true,
        audioInputDevice: null,
    };

    try {
        await invoke('save_settings', { data });
        // Close the window
        const { getCurrentWindow } = window.__TAURI__.window;
        getCurrentWindow().close();
    } catch (e) {
        console.error('Failed to save settings:', e);
    }
}

async function refreshAudioDevices() {
    try {
        const devices = await invoke('list_audio_devices');
        const select = document.getElementById('audioDevice');
        select.innerHTML = '';
        devices.forEach(d => {
            const opt = document.createElement('option');
            opt.value = d.id;
            opt.textContent = d.name;
            select.appendChild(opt);
        });
    } catch (e) {
        console.error('Failed to list audio devices:', e);
    }
}

init();
