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

        // Lazy-load each section's data when it is opened
        if (section === 'speech') refreshAudioDevices();
        if (section === 'history') loadHistory();
        if (section === 'dictionary') loadDictionary();
        if (section === 'snippets') loadSnippets();
        if (section === 'commands') loadCommands();
    });
});

// Accuracy slider
document.getElementById('llmAccuracy').addEventListener('input', (e) => {
    document.getElementById('accuracyLabel').textContent = ACCURACY_LABELS[e.target.value] || 'Balanced';
});

// Provider changes
document.getElementById('llmProvider').addEventListener('change', updateProviderFields);

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
    updateProviderFields();
    // Populate the mic dropdown and select the saved device up front so the
    // selection is correct even before the Speech section is opened.
    await refreshAudioDevices();
}

function loadValues(s) {
    document.getElementById('hotkeyMode').value = s.hotkeyMode;
    document.getElementById('language').value = s.whisperLanguage;
    document.getElementById('flowMode').checked = s.flowMode;
    document.getElementById('codeMode').checked = s.codeMode;
    document.getElementById('privacyMode').checked = s.privacyMode;

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
        audioInputDevice: getSelectedAudioDevice(),
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

// Returns the value to persist for the selected mic. The backend treats both
// null and "default" as the system default, so collapse "default" to null.
function getSelectedAudioDevice() {
    const value = document.getElementById('audioDevice').value;
    return (!value || value === 'default') ? null : value;
}

async function refreshAudioDevices() {
    const select = document.getElementById('audioDevice');
    // Preserve whatever is currently selected; fall back to the saved setting
    // (null/absent => the "default" option) so re-opening Speech keeps it.
    const desired = select.value || currentSettings?.audioInputDevice || 'default';
    try {
        const devices = await invoke('list_audio_devices');
        select.innerHTML = '';
        // Always offer a system-default option (id === "default").
        const hasDefault = devices.some(d => d.id === 'default');
        if (!hasDefault) {
            const def = document.createElement('option');
            def.value = 'default';
            def.textContent = 'System Default';
            select.appendChild(def);
        }
        devices.forEach(d => {
            const opt = document.createElement('option');
            opt.value = d.id;
            opt.textContent = d.name;
            select.appendChild(opt);
        });
        // Select the desired device if it's still present, else default.
        const exists = Array.from(select.options).some(o => o.value === desired);
        select.value = exists ? desired : 'default';
    } catch (e) {
        console.error('Failed to list audio devices:', e);
    }
}

// ----- In-app editors -----------------------------------------------------

function makeRemoveButton(onClick) {
    const btn = document.createElement('button');
    btn.className = 'btn-icon';
    btn.textContent = '✕';
    btn.title = 'Remove';
    btn.addEventListener('click', onClick);
    return btn;
}

// History (read-only)
async function loadHistory() {
    const list = document.getElementById('historyList');
    const count = document.getElementById('historyCount');
    try {
        const entries = await invoke('get_history');
        list.innerHTML = '';
        count.textContent = entries.length
            ? `${entries.length} ${entries.length === 1 ? 'entry' : 'entries'}`
            : '';
        entries.forEach(entry => {
            const item = document.createElement('div');
            item.className = 'history-item';

            const meta = document.createElement('div');
            meta.className = 'history-meta';
            if (entry.app) {
                const appBadge = document.createElement('span');
                appBadge.className = 'history-badge';
                appBadge.textContent = entry.app;
                meta.appendChild(appBadge);
            }
            if (entry.engine) {
                const engBadge = document.createElement('span');
                engBadge.className = 'history-badge';
                engBadge.textContent = entry.engine;
                meta.appendChild(engBadge);
            }
            const time = document.createElement('span');
            time.className = 'history-time';
            time.textContent = formatTimestamp(entry.timestamp);
            meta.appendChild(time);
            item.appendChild(meta);

            const cleaned = document.createElement('div');
            cleaned.className = 'history-cleaned';
            cleaned.textContent = entry.cleaned || entry.raw || '';
            item.appendChild(cleaned);

            // Only show the raw line when it differs from the cleaned output.
            if (entry.raw && entry.cleaned && entry.raw !== entry.cleaned) {
                const raw = document.createElement('div');
                raw.className = 'history-raw';
                raw.textContent = entry.raw;
                item.appendChild(raw);
            }

            list.appendChild(item);
        });
    } catch (e) {
        console.error('Failed to load history:', e);
    }
}

function formatTimestamp(ts) {
    if (ts === undefined || ts === null) return '';
    // Accept epoch seconds, epoch millis, or an ISO string.
    let date;
    if (typeof ts === 'number') {
        date = new Date(ts < 1e12 ? ts * 1000 : ts);
    } else {
        date = new Date(ts);
    }
    if (isNaN(date.getTime())) return String(ts);
    return date.toLocaleString();
}

document.getElementById('clearHistoryBtn')?.addEventListener('click', async () => {
    try {
        await invoke('clear_history');
        await loadHistory();
    } catch (e) {
        console.error('Failed to clear history:', e);
    }
});

// Dictionary (list of strings)
let dictionaryEntries = [];

async function loadDictionary() {
    try {
        dictionaryEntries = (await invoke('get_dictionary')) || [];
        renderDictionary();
    } catch (e) {
        console.error('Failed to load dictionary:', e);
    }
}

function renderDictionary() {
    const list = document.getElementById('dictionaryList');
    list.innerHTML = '';
    dictionaryEntries.forEach((word, i) => {
        const item = document.createElement('div');
        item.className = 'editor-item';
        const span = document.createElement('span');
        span.className = 'word';
        span.textContent = word;
        item.appendChild(span);
        item.appendChild(makeRemoveButton(async () => {
            dictionaryEntries.splice(i, 1);
            await saveDictionary();
            renderDictionary();
        }));
        list.appendChild(item);
    });
}

async function saveDictionary() {
    try {
        await invoke('save_dictionary', { entries: dictionaryEntries });
    } catch (e) {
        console.error('Failed to save dictionary:', e);
    }
}

function addDictionaryWord() {
    const input = document.getElementById('dictionaryInput');
    const word = input.value.trim();
    if (!word) return;
    dictionaryEntries.push(word);
    input.value = '';
    saveDictionary();
    renderDictionary();
}

document.getElementById('dictionaryAddBtn')?.addEventListener('click', addDictionaryWord);
document.getElementById('dictionaryInput')?.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') addDictionaryWord();
});

// Snippets (list of { trigger, text })
let snippetEntries = [];

async function loadSnippets() {
    try {
        snippetEntries = (await invoke('get_snippets')) || [];
        renderSnippets();
    } catch (e) {
        console.error('Failed to load snippets:', e);
    }
}

function renderSnippets() {
    const list = document.getElementById('snippetsList');
    list.innerHTML = '';
    snippetEntries.forEach((entry, i) => {
        const item = document.createElement('div');
        item.className = 'editor-item';

        const trigger = document.createElement('input');
        trigger.type = 'text';
        trigger.value = entry.trigger || '';
        trigger.placeholder = 'Trigger';
        trigger.addEventListener('change', () => {
            snippetEntries[i].trigger = trigger.value;
            saveSnippets();
        });

        const text = document.createElement('input');
        text.type = 'text';
        text.value = entry.text || '';
        text.placeholder = 'Expands to...';
        text.addEventListener('change', () => {
            snippetEntries[i].text = text.value;
            saveSnippets();
        });

        item.appendChild(trigger);
        item.appendChild(text);
        item.appendChild(makeRemoveButton(async () => {
            snippetEntries.splice(i, 1);
            await saveSnippets();
            renderSnippets();
        }));
        list.appendChild(item);
    });
}

async function saveSnippets() {
    try {
        await invoke('save_snippets', { entries: snippetEntries });
    } catch (e) {
        console.error('Failed to save snippets:', e);
    }
}

function addSnippet() {
    const triggerInput = document.getElementById('snippetTriggerInput');
    const textInput = document.getElementById('snippetTextInput');
    const trigger = triggerInput.value.trim();
    const text = textInput.value;
    if (!trigger) return;
    snippetEntries.push({ trigger, text });
    triggerInput.value = '';
    textInput.value = '';
    saveSnippets();
    renderSnippets();
}

document.getElementById('snippetAddBtn')?.addEventListener('click', addSnippet);
document.getElementById('snippetTextInput')?.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') addSnippet();
});

// Voice Commands (list of { trigger, keyCombo })
let commandEntries = [];

async function loadCommands() {
    try {
        commandEntries = (await invoke('get_commands')) || [];
        renderCommands();
    } catch (e) {
        console.error('Failed to load commands:', e);
    }
}

function renderCommands() {
    const list = document.getElementById('commandsList');
    list.innerHTML = '';
    commandEntries.forEach((entry, i) => {
        const item = document.createElement('div');
        item.className = 'editor-item';

        const trigger = document.createElement('input');
        trigger.type = 'text';
        trigger.value = entry.trigger || '';
        trigger.placeholder = 'Trigger phrase';
        trigger.addEventListener('change', () => {
            commandEntries[i].trigger = trigger.value;
            saveCommands();
        });

        const combo = document.createElement('input');
        combo.type = 'text';
        combo.value = entry.keyCombo || '';
        combo.placeholder = 'Key combo (cmd+s)';
        combo.addEventListener('change', () => {
            commandEntries[i].keyCombo = combo.value;
            saveCommands();
        });

        item.appendChild(trigger);
        item.appendChild(combo);
        item.appendChild(makeRemoveButton(async () => {
            commandEntries.splice(i, 1);
            await saveCommands();
            renderCommands();
        }));
        list.appendChild(item);
    });
}

async function saveCommands() {
    try {
        await invoke('save_commands', { entries: commandEntries });
    } catch (e) {
        console.error('Failed to save commands:', e);
    }
}

function addCommand() {
    const triggerInput = document.getElementById('commandTriggerInput');
    const comboInput = document.getElementById('commandComboInput');
    const trigger = triggerInput.value.trim();
    const keyCombo = comboInput.value.trim();
    if (!trigger || !keyCombo) return;
    commandEntries.push({ trigger, keyCombo });
    triggerInput.value = '';
    comboInput.value = '';
    saveCommands();
    renderCommands();
}

document.getElementById('commandAddBtn')?.addEventListener('click', addCommand);
document.getElementById('commandComboInput')?.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') addCommand();
});

init();
