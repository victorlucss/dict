const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

// ---- Inline Lucide-style SVG icons (stroke = currentColor) ----
const ICONS = {
    mic: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="22"/></svg>`,
    shield: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10Z"/><path d="m9 12 2 2 4-4"/></svg>`,
    download: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>`,
    keyboard: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="4" width="20" height="16" rx="2"/><path d="M6 8h.01M10 8h.01M14 8h.01M18 8h.01M8 12h.01M12 12h.01M16 12h.01M7 16h10"/></svg>`,
    check: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/></svg>`
};

// ---- Model catalog presented in the picker ----
const MODEL_OPTIONS = [
    { name: 'base',   label: 'Base',   size: '~142 MB', desc: 'Fast, good for everyday use.' },
    { name: 'small',  label: 'Small',  size: '~466 MB', desc: 'Balanced accuracy and speed.', recommended: true },
    { name: 'medium', label: 'Medium', size: '~1.5 GB', desc: 'Most accurate, slower and larger.' }
];

// ---- Step definitions ----
const STEP = {
    welcome: {
        id: 'welcome',
        icon: ICONS.mic,
        title: 'Welcome to Dict',
        description: 'Talk and Dict types it out, in any app. Hold <kbd>Option</kbd> + <kbd>Space</kbd> anywhere to start dictating.',
        action: 'Get Started'
    },
    accessibility: {
        id: 'accessibility',
        icon: ICONS.shield,
        title: 'One quick permission',
        description: 'To type into other apps, Dict needs Accessibility access. Flip Dict on in System Settings, then pop back here.',
        action: 'Continue'
    },
    model: {
        id: 'model',
        icon: ICONS.download,
        title: 'Pick a voice model',
        description: 'Dict transcribes right on your Mac with Whisper. Pick a model to download. You can switch anytime in Preferences.',
        action: 'Continue'
    },
    tryit: {
        id: 'tryit',
        icon: ICONS.keyboard,
        title: 'Give it a go',
        description: 'Hold <kbd>Option</kbd> + <kbd>Space</kbd>, say a sentence, then let go. Your words show up below.',
        action: 'Done'
    }
};

// Non-macOS uses a different shortcut and skips the Accessibility step.
const OTHER_SHORTCUT = '<kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>Space</kbd>';

let platform = 'macos';
let steps = [];
let currentStep = 0;

// Model-step state
let models = [];                 // catalog from list_whisper_models()
let modelsLoaded = false;
let selectedModel = null;        // name string
let downloading = false;

// DOM refs
const iconEl = document.getElementById('stepIcon');
const titleEl = document.getElementById('stepTitle');
const descEl = document.getElementById('stepDescription');
const primaryBtn = document.getElementById('primaryBtn');
const secondaryBtn = document.getElementById('secondaryBtn');
const indicatorEl = document.getElementById('stepIndicator');
const progressEl = document.getElementById('wizardProgress');
const stepEl = document.querySelector('.wizard-step');

const modelPicker = document.getElementById('modelPicker');
const modelList = document.getElementById('modelList');
const modelAction = document.getElementById('modelAction');

const tryitBox = document.getElementById('tryitBox');
const tryitResult = document.getElementById('tryitResult');

primaryBtn.addEventListener('click', handlePrimary);
secondaryBtn.addEventListener('click', () => advance());

async function init() {
    try {
        platform = await invoke('get_platform');
    } catch (e) {
        platform = 'macos';
    }

    if (platform === 'macos') {
        steps = [STEP.welcome, STEP.accessibility, STEP.model, STEP.tryit];
    } else {
        steps = [STEP.welcome, STEP.model, STEP.tryit];
        // Swap shortcut copy for non-macOS.
        STEP.welcome.description = `Talk and Dict types it out, in any app. Hold ${OTHER_SHORTCUT} anywhere to start dictating.`;
        STEP.tryit.description = `Hold ${OTHER_SHORTCUT}, say a sentence, then let go. Your words show up below.`;
    }

    // Set up the transcription listener once — it stays live for the whole flow.
    listen('transcription-result', (e) => {
        const text = typeof e.payload === 'string' ? e.payload : String(e.payload ?? '');
        if (text.trim().length === 0) return;
        tryitResult.textContent = text;
        tryitResult.dataset.empty = 'false';
    });

    renderStep();
}

function currentStepDef() {
    return steps[currentStep];
}

function renderStep() {
    const step = currentStepDef();

    iconEl.innerHTML = step.icon;
    titleEl.textContent = step.title;
    descEl.innerHTML = step.description;
    primaryBtn.textContent = step.action;
    primaryBtn.disabled = false;
    secondaryBtn.style.display = 'none';

    // Reset interactive panels.
    modelPicker.classList.add('hidden');
    tryitBox.classList.add('hidden');

    indicatorEl.textContent = `${currentStep + 1} of ${steps.length}`;

    // Drive the top progress bar and replay the step-reveal animation.
    if (progressEl) progressEl.style.width = `${((currentStep + 1) / steps.length) * 100}%`;
    if (stepEl) {
        stepEl.classList.remove('reveal');
        void stepEl.offsetWidth; // reflow so the animation re-triggers
        stepEl.classList.add('reveal');
    }

    if (step.id === 'accessibility') {
        setupAccessibilityStep();
    } else if (step.id === 'model') {
        setupModelStep();
    } else if (step.id === 'tryit') {
        tryitBox.classList.remove('hidden');
    }
}

// ---------------- Accessibility step ----------------

function setupAccessibilityStep() {
    // Show a status line + an "Open Settings" secondary button under the description.
    // We render them into a transient container appended after the description.
    let line = document.getElementById('accStatus');
    if (!line) {
        line = document.createElement('div');
        line.id = 'accStatus';
        line.className = 'status-line pending';
        line.innerHTML = `<span class="dot"></span><span class="acc-label">Checking…</span>`;
        descEl.insertAdjacentElement('afterend', line);

        const action = document.createElement('div');
        action.className = 'status-action';
        action.id = 'accAction';
        const btn = document.createElement('button');
        btn.className = 'btn-secondary';
        btn.id = 'accOpenBtn';
        btn.textContent = 'Open Accessibility Settings';
        btn.addEventListener('click', () => {
            invoke('open_accessibility_settings').catch(console.error);
            // Re-check shortly after the user returns.
            setTimeout(refreshAccessibility, 800);
        });
        action.appendChild(btn);
        line.insertAdjacentElement('afterend', action);
    }
    document.getElementById('accStatus').style.display = '';
    document.getElementById('accAction').style.display = '';
    refreshAccessibility();
}

async function refreshAccessibility() {
    if (currentStepDef().id !== 'accessibility') return;
    const line = document.getElementById('accStatus');
    if (!line) return;
    let granted = false;
    try {
        granted = await invoke('check_accessibility');
    } catch (e) {
        granted = false;
    }
    const label = line.querySelector('.acc-label');
    if (granted) {
        line.className = 'status-line granted';
        label.textContent = 'Granted';
    } else {
        line.className = 'status-line pending';
        label.textContent = 'Not granted yet';
    }
}

function hideAccessibilityExtras() {
    const line = document.getElementById('accStatus');
    const action = document.getElementById('accAction');
    if (line) line.style.display = 'none';
    if (action) action.style.display = 'none';
}

// ---------------- Model step ----------------

async function setupModelStep() {
    modelPicker.classList.remove('hidden');
    if (!modelsLoaded) {
        modelList.innerHTML = `<div class="dl-status">Loading models…</div>`;
        modelAction.innerHTML = '';
        try {
            models = await invoke('list_whisper_models');
            modelsLoaded = true;
        } catch (e) {
            modelList.innerHTML = `<div class="dl-status">Couldn't load the models. Check your connection and try again.</div>`;
            return;
        }
    }
    // Default-select medium if already downloaded, else nothing.
    if (!selectedModel) {
        const medium = findModel('medium');
        if (medium && medium.downloaded) selectedModel = 'medium';
    }
    renderModelList();
    updateModelGate();
}

function findModel(name) {
    return models.find((m) => m.name === name) || null;
}

function renderModelList() {
    modelList.innerHTML = '';
    for (const opt of MODEL_OPTIONS) {
        const m = findModel(opt.name);
        const downloaded = m ? m.downloaded : false;
        const isSel = selectedModel === opt.name;

        const card = document.createElement('button');
        card.type = 'button';
        card.className = 'model-card' + (isSel ? ' selected' : '');
        card.dataset.model = opt.name;

        let badge = '';
        if (downloaded) {
            badge = `<span class="model-badge">Ready</span>`;
        } else if (opt.recommended) {
            badge = `<span class="model-badge recommended">Recommended</span>`;
        }

        card.innerHTML = `
            <span class="model-radio"></span>
            <span class="model-body">
                <span class="model-name-row">
                    <span class="model-name">${opt.label}</span>
                    <span class="model-size">${opt.size}</span>
                </span>
                <span class="model-desc">${opt.desc}</span>
            </span>
            ${badge}
        `;
        card.addEventListener('click', () => selectModel(opt.name));
        modelList.appendChild(card);
    }
}

function selectModel(name) {
    if (downloading) return;
    selectedModel = name;
    renderModelList();
    renderModelAction();
    updateModelGate();
}

// The primary "Download and Continue" / "Continue" button drives downloading now;
// this area only shows the progress bar while a download is in flight.
function renderModelAction() {
    modelAction.innerHTML = '';
}

async function downloadSelected() {
    if (downloading || !selectedModel) return;
    const name = selectedModel;
    downloading = true;
    updateModelGate();

    // Render progress UI.
    modelAction.innerHTML = `
        <div class="dl-row">
            <div class="dl-progress indeterminate" id="dlBar"><div class="dl-progress-fill" id="dlFill"></div></div>
            <div class="dl-status" id="dlStatus">Starting download…</div>
        </div>
    `;
    const bar = document.getElementById('dlBar');
    const fill = document.getElementById('dlFill');
    const status = document.getElementById('dlStatus');

    const unlisten = await listen('whisper-download-progress', (e) => {
        const p = e.payload || {};
        if (p.name && p.name !== name) return;
        const total = Number(p.total) || 0;
        const done = Number(p.downloaded) || 0;
        if (total > 0) {
            const pct = Math.min(100, Math.round((done / total) * 100));
            bar.classList.remove('indeterminate');
            fill.style.width = pct + '%';
            status.textContent = `Downloading… ${pct}% (${fmtMB(done)} / ${fmtMB(total)})`;
        } else {
            status.textContent = `Downloading… ${fmtMB(done)}`;
        }
    });

    try {
        const path = await invoke('download_whisper_model', { name });
        // Mark downloaded + store its path in the catalog.
        const m = findModel(name);
        if (m) {
            m.downloaded = true;
            if (path) m.path = path;
        }
        await applyActiveModel(name, path);
        downloading = false;
        renderModelList();
        modelAction.innerHTML = '';
        updateModelGate();
        return true;
    } catch (err) {
        status.textContent = "Download didn't finish. Give it another try.";
        bar.classList.remove('indeterminate');
        fill.style.width = '0%';
        downloading = false;
        renderModelAction();
        updateModelGate();
        return false;
    } finally {
        unlisten();
    }
}

// Persist whisperModelPath = chosen model's local path.
async function applyActiveModel(name, pathFromDownload) {
    const m = findModel(name);
    const path = pathFromDownload || (m && m.path);
    if (!path) return;
    try {
        const settings = await invoke('get_settings');
        settings.whisperModelPath = path;
        await invoke('save_settings', { data: settings });
    } catch (e) {
        console.error('Failed to persist whisperModelPath', e);
    }
}

// The primary button reflects whether the selected model still needs downloading.
function updateModelGate() {
    if (currentStepDef().id !== 'model') return;
    const m = selectedModel ? findModel(selectedModel) : null;
    if (downloading) {
        primaryBtn.textContent = 'Downloading…';
        primaryBtn.disabled = true;
    } else if (!selectedModel) {
        primaryBtn.textContent = 'Continue';
        primaryBtn.disabled = true;
    } else if (m && m.downloaded) {
        primaryBtn.textContent = 'Continue';
        primaryBtn.disabled = false;
    } else {
        primaryBtn.textContent = 'Download and Continue';
        primaryBtn.disabled = false;
    }
}

function fmtMB(bytes) {
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
}

// ---------------- Navigation ----------------

async function handlePrimary() {
    const step = currentStepDef();

    if (step.id === 'model') {
        if (!selectedModel) return;
        const m = findModel(selectedModel);
        if (m && m.downloaded) {
            await applyActiveModel(selectedModel);
            advance();
        } else {
            // "Download and Continue": download first, then move on if it worked.
            const ok = await downloadSelected();
            if (ok) advance();
        }
        return;
    }

    if (step.action === 'Done') {
        await finish();
        return;
    }

    advance();
}

function advance() {
    if (currentStepDef().id === 'accessibility') hideAccessibilityExtras();
    currentStep++;
    if (currentStep < steps.length) {
        renderStep();
    } else {
        finish();
    }
}

async function finish() {
    try {
        const settings = await invoke('get_settings');
        settings.onboardingDone = true;
        await invoke('save_settings', { data: settings });
    } catch (e) {
        console.error('Failed to persist onboardingDone', e);
    }
    try {
        window.__TAURI__.window.getCurrentWindow().close();
    } catch (e) {
        console.error('Failed to close window', e);
    }
}

init();
