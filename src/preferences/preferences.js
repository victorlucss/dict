const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

let currentSettings = null;
let platform = 'macos';

// Tracks the provider the model list was last fetched for, so refreshModels can
// tell a provider switch (clear the old model) from a same-provider reload
// (preserve the saved model).
let lastModelProvider = null;

// Default API endpoint per LLM provider. Used both as the <input> placeholder in
// `updateProviderFields` and as the effective endpoint in `refreshModels` when the
// user hasn't overridden `#llmEndpoint`.
const PROVIDER_ENDPOINTS = {
    openai: 'https://api.openai.com/v1/chat/completions',
    anthropic: 'https://api.anthropic.com/v1/messages',
    openrouter: 'https://openrouter.ai/api/v1/chat/completions',
    ollama: 'http://localhost:11434/v1/chat/completions',
    lmstudio: 'http://localhost:1234/v1/chat/completions',
};

// ----- Custom (Codex-style) dropdowns -------------------------------------
// Progressive enhancement over the native <select> elements: the real <select>
// stays in the DOM (visually hidden) so the rest of this file keeps reading and
// writing `.value` and listening for `change`. We layer a custom trigger +
// popover on top and mirror the selection back onto the native control.

// Track the currently-open popover so only one is open at a time.
let openCustomSelect = null;

// Lists longer than this get an inline search box in their dropdown.
const SEARCHABLE_MIN = 8;

function closeOpenCustomSelect() {
    if (openCustomSelect) {
        openCustomSelect.close();
        openCustomSelect = null;
    }
}

// Global listeners (registered once): click-outside and Escape both close.
document.addEventListener('click', (e) => {
    if (openCustomSelect && !openCustomSelect.root.contains(e.target)) {
        closeOpenCustomSelect();
    }
});
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && openCustomSelect) {
        closeOpenCustomSelect();
        openCustomSelect.trigger.focus();
    }
});

// Enhance a native <select> with a custom dropdown. The native element is kept
// (hidden via the `.has-custom-select` class on it) so existing code that does
// `getElementById(id).value` / dispatches/listens for `change` keeps working.
// Returns a controller; also stored on `selectEl._customSelect` so it can be
// rebuilt later (e.g. after the mic list is repopulated at runtime).
function enhanceSelect(selectEl) {
    if (!selectEl) return null;
    // If already enhanced, just rebuild from the current options/value.
    if (selectEl._customSelect) {
        selectEl._customSelect.rebuild();
        return selectEl._customSelect;
    }

    selectEl.classList.add('has-custom-select');

    const root = document.createElement('div');
    root.className = 'custom-select';

    const trigger = document.createElement('button');
    trigger.type = 'button';
    trigger.className = 'custom-select-trigger';
    trigger.setAttribute('aria-haspopup', 'listbox');
    trigger.setAttribute('aria-expanded', 'false');

    const labelEl = document.createElement('span');
    labelEl.className = 'custom-select-label';

    const chevron = document.createElement('span');
    chevron.className = 'custom-select-chevron';
    chevron.setAttribute('aria-hidden', 'true');
    chevron.innerHTML =
        '<svg viewBox="0 0 12 12" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 4.5 6 7.5 9 4.5"/></svg>';

    trigger.appendChild(labelEl);
    trigger.appendChild(chevron);

    const popover = document.createElement('div');
    popover.className = 'custom-select-popover';
    popover.setAttribute('role', 'listbox');

    // Search header (shown only for long lists) + scrollable list of rows.
    const searchWrap = document.createElement('div');
    searchWrap.className = 'custom-select-search';
    const searchInput = document.createElement('input');
    searchInput.type = 'text';
    searchInput.className = 'custom-select-search-input';
    searchInput.placeholder = 'Search…';
    searchInput.setAttribute('aria-label', 'Search options');
    searchWrap.appendChild(searchInput);

    const listWrap = document.createElement('div');
    listWrap.className = 'custom-select-list';

    const noResults = document.createElement('div');
    noResults.className = 'custom-select-empty';
    noResults.textContent = 'No matches';
    noResults.style.display = 'none';

    popover.appendChild(searchWrap);
    popover.appendChild(listWrap);
    popover.appendChild(noResults);

    root.appendChild(trigger);
    root.appendChild(popover);

    // Insert the custom UI right after the native select.
    selectEl.parentNode.insertBefore(root, selectEl.nextSibling);

    let optionEls = []; // custom row elements, parallel to native options
    let searchable = false; // true once the list is long enough to warrant search

    function selectByValue(value, { silent } = {}) {
        if (selectEl.value !== value) {
            selectEl.value = value;
            if (!silent) selectEl.dispatchEvent(new Event('change'));
        }
        syncFromNative();
    }

    // Update the trigger label + checkmarks to match the native select's value.
    function syncFromNative() {
        const current = selectEl.value;
        const selectedOpt = Array.from(selectEl.options).find(o => o.value === current);
        labelEl.textContent = selectedOpt ? selectedOpt.textContent : '';
        optionEls.forEach((el) => {
            const isSel = el.dataset.value === current;
            el.classList.toggle('selected', isSel);
            el.setAttribute('aria-selected', isSel ? 'true' : 'false');
        });
    }

    // (Re)build the popover rows from the native <option>s.
    function rebuild() {
        listWrap.innerHTML = '';
        optionEls = [];
        Array.from(selectEl.options).forEach((opt) => {
            const row = document.createElement('div');
            row.className = 'custom-select-option';
            row.setAttribute('role', 'option');
            row.dataset.value = opt.value;
            // Lowercased haystack for filtering (label + description).
            row.dataset.search =
                `${opt.textContent} ${opt.dataset.desc || ''}`.toLowerCase();
            row.tabIndex = -1;

            if (opt.dataset.icon) {
                const icon = document.createElement('span');
                icon.className = 'custom-select-icon';
                icon.textContent = opt.dataset.icon;
                row.appendChild(icon);
            }

            const textWrap = document.createElement('span');
            textWrap.className = 'custom-select-text';

            const label = document.createElement('span');
            label.className = 'custom-select-option-label';
            label.textContent = opt.textContent;
            textWrap.appendChild(label);

            if (opt.dataset.desc) {
                const desc = document.createElement('span');
                desc.className = 'custom-select-option-desc';
                desc.textContent = opt.dataset.desc;
                textWrap.appendChild(desc);
            }
            row.appendChild(textWrap);

            const check = document.createElement('span');
            check.className = 'custom-select-check';
            check.setAttribute('aria-hidden', 'true');
            check.textContent = '✓';
            row.appendChild(check);

            row.addEventListener('click', (e) => {
                e.stopPropagation();
                selectByValue(opt.value);
                close();
                trigger.focus();
            });

            listWrap.appendChild(row);
            optionEls.push(row);
        });
        // Only long lists get a search box; short ones stay clean.
        searchable = selectEl.options.length > SEARCHABLE_MIN;
        searchWrap.style.display = searchable ? '' : 'none';
        searchInput.value = '';
        applyFilter('');
        syncFromNative();
    }

    // Show/hide rows by a case-insensitive substring of label + description.
    function applyFilter(query) {
        const q = (query || '').trim().toLowerCase();
        let visible = 0;
        optionEls.forEach((el) => {
            const match = !q || (el.dataset.search || '').includes(q);
            el.style.display = match ? '' : 'none';
            if (match) visible++;
        });
        noResults.style.display = visible === 0 ? '' : 'none';
        activeIndex = -1;
        optionEls.forEach((el) => el.classList.remove('active'));
    }

    function visibleEls() {
        return optionEls.filter((el) => el.style.display !== 'none');
    }

    function isOpen() {
        return root.classList.contains('open');
    }

    function open() {
        if (isOpen()) return;
        closeOpenCustomSelect();
        root.classList.add('open');
        trigger.setAttribute('aria-expanded', 'true');
        openCustomSelect = controller;
        // Long lists: reset the filter and focus the search field.
        if (searchable) {
            searchInput.value = '';
            applyFilter('');
            setTimeout(() => searchInput.focus(), 0);
        }
        // Bring the selected row into view.
        const sel = listWrap.querySelector('.custom-select-option.selected');
        if (sel) sel.scrollIntoView({ block: 'nearest' });
    }

    function close() {
        if (!isOpen()) return;
        root.classList.remove('open');
        trigger.setAttribute('aria-expanded', 'false');
        if (openCustomSelect === controller) openCustomSelect = null;
    }

    function toggle() {
        isOpen() ? close() : open();
    }

    trigger.addEventListener('click', (e) => {
        e.stopPropagation();
        toggle();
    });

    // Keyboard navigation operates over the currently-visible (filtered) rows.
    let activeIndex = -1; // index into visibleEls(), or -1
    function setActive(i) {
        const vis = visibleEls();
        optionEls.forEach((el) => el.classList.remove('active'));
        if (!vis.length) { activeIndex = -1; return; }
        activeIndex = Math.max(0, Math.min(vis.length - 1, i));
        const el = vis[activeIndex];
        el.classList.add('active');
        el.scrollIntoView({ block: 'nearest' });
    }
    function commitActive() {
        const vis = visibleEls();
        const el = activeIndex >= 0 ? vis[activeIndex] : vis[0];
        if (!el) return;
        selectByValue(el.dataset.value);
        close();
        trigger.focus();
    }
    function activeForCurrentValue() {
        const vis = visibleEls();
        const idx = vis.findIndex((el) => el.dataset.value === selectEl.value);
        setActive(idx >= 0 ? idx : 0);
    }

    trigger.addEventListener('keydown', (e) => {
        if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
            e.preventDefault();
            if (!isOpen()) {
                open();
                if (!searchable) activeForCurrentValue();
            } else if (!searchable) {
                setActive(activeIndex + (e.key === 'ArrowDown' ? 1 : -1));
            }
        } else if (e.key === 'Enter' || e.key === ' ') {
            if (isOpen() && !searchable && activeIndex >= 0) {
                e.preventDefault();
                commitActive();
            } else if (!isOpen()) {
                e.preventDefault();
                open();
                if (!searchable) activeForCurrentValue();
            }
        }
    });

    // Search field: live-filter, and drive nav/commit from the input itself.
    searchInput.addEventListener('input', () => applyFilter(searchInput.value));
    searchInput.addEventListener('keydown', (e) => {
        if (e.key === 'ArrowDown') {
            e.preventDefault();
            setActive(activeIndex + 1);
        } else if (e.key === 'ArrowUp') {
            e.preventDefault();
            setActive(activeIndex <= 0 ? 0 : activeIndex - 1);
        } else if (e.key === 'Enter') {
            e.preventDefault();
            commitActive();
        }
        // Escape bubbles to the document handler, which closes + refocuses.
    });

    const controller = { root, trigger, rebuild, sync: syncFromNative, open, close };
    selectEl._customSelect = controller;

    rebuild();
    return controller;
}

// Rebuild a previously-enhanced select's custom UI from its current options and
// value (e.g. after refreshAudioDevices repopulates #audioDevice at runtime).
function rebuildCustomSelect(selectEl) {
    if (selectEl && selectEl._customSelect) {
        selectEl._customSelect.rebuild();
    } else {
        enhanceSelect(selectEl);
    }
}

// Sidebar navigation
document.querySelectorAll('.sidebar-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.sidebar-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');

        const section = btn.dataset.section;
        document.getElementById('section-title').textContent =
            btn.dataset.title || (section.charAt(0).toUpperCase() + section.slice(1));

        document.querySelectorAll('.section').forEach(s => s.classList.add('hidden'));
        document.getElementById(`section-${section}`).classList.remove('hidden');

        // Lazy-load each section's data when it is opened
        if (section === 'account') updateDictCloudAccount();
        if (section === 'speech') { refreshAudioDevices(); refreshWhisperModels(); }
        if (section === 'llm') refreshModels();
        if (section === 'history') loadHistory();
        if (section === 'dictionary') loadDictionary();
        if (section === 'snippets') loadSnippets();
        if (section === 'commands') loadCommands();
    });
});

// ----- Correction level cards --------------------------------------------
// Five selectable cards (1–5) mapped to the `llmAccuracy` setting, mirroring the
// tone cards. The chosen level is mirrored into the hidden #llmAccuracy input
// that collectSettings reads.
function setAccuracy(level) {
    const v = String(Math.min(5, Math.max(1, parseInt(level, 10) || 3)));
    document.getElementById('llmAccuracy').value = v;
    document.querySelectorAll('#accuracyCards .tone-card').forEach(card => {
        const isSel = card.dataset.level === v;
        card.classList.toggle('selected', isSel);
        card.setAttribute('aria-checked', isSel ? 'true' : 'false');
    });
}

document.querySelectorAll('#accuracyCards .tone-card').forEach(card => {
    card.addEventListener('click', () => { setAccuracy(card.dataset.level); autoSave(); });
});

// Provider changes
document.getElementById('llmProvider').addEventListener('change', updateProviderFields);

// ----- Dict Cloud account (email one-time-code sign-in) -------------------
function dcShowError(msg) {
    const el = document.getElementById('dcError');
    el.textContent = msg || '';
    el.classList.toggle('hidden', !msg);
}

function dcShowStatus(msg) {
    const el = document.getElementById('dcStatus');
    el.textContent = msg || '';
    el.classList.toggle('hidden', !msg);
}

// Reflect signed-in vs signed-out state from currentSettings, and (when signed
// in) show whether the account has Dict Cloud cleanup access (a feature flag).
async function updateDictCloudAccount() {
    const email = currentSettings?.dictCloudEmail || '';
    const signedIn = !!email;
    document.getElementById('dcSignedIn').classList.toggle('hidden', !signedIn);
    document.getElementById('dcSignedOut').classList.toggle('hidden', signedIn);
    if (!signedIn) {
        dcShowStatus(null);
        dcShowError(null);
        return;
    }
    document.getElementById('dcEmailLabel').textContent = email;

    const accessEl = document.getElementById('dcAccess');
    accessEl.className = 'dc-access';
    accessEl.textContent = 'Checking access…';
    try {
        const flags = await invoke('dict_cloud_flags');
        if (flags && flags.cloud_cleanup) {
            accessEl.textContent = '✓ Dict Cloud cleanup is enabled for your account.';
            accessEl.classList.add('enabled');
        } else {
            accessEl.textContent = "Dict Cloud cleanup isn't enabled for your account yet — you're on the list, we'll turn it on soon.";
        }
    } catch (e) {
        accessEl.textContent = "Couldn't check access right now.";
    }
}

// Shared sign-in / sign-up handler.
async function dcAuth(command) {
    const email = document.getElementById('dcEmail').value.trim();
    const password = document.getElementById('dcPassword').value;
    if (!email || !email.includes('@')) { dcShowError('Enter a valid email address.'); return; }
    if (!password || password.length < 8) { dcShowError('Password must be at least 8 characters.'); return; }
    dcShowError(null);
    const buttons = [document.getElementById('dcSignIn'), document.getElementById('dcSignUp')];
    buttons.forEach((b) => (b.disabled = true));
    try {
        await invoke(command, { email, password });
        // Refresh settings so the signed-in email shows and auto-save preserves the token.
        currentSettings = await invoke('get_settings');
        document.getElementById('dcEmail').value = '';
        document.getElementById('dcPassword').value = '';
        updateDictCloudAccount();
    } catch (e) {
        dcShowError(typeof e === 'string' ? e : 'Sign-in failed.');
    } finally {
        buttons.forEach((b) => (b.disabled = false));
    }
}

document.getElementById('dcSignIn')?.addEventListener('click', () => dcAuth('dict_cloud_sign_in'));
document.getElementById('dcSignUp')?.addEventListener('click', () => dcAuth('dict_cloud_sign_up'));

document.getElementById('dcSignOut')?.addEventListener('click', async () => {
    try {
        await invoke('dict_cloud_sign_out');
        currentSettings = await invoke('get_settings');
        updateDictCloudAccount();
    } catch (e) {
        dcShowError(typeof e === 'string' ? e : 'Could not sign out.');
    }
});

// ----- Tone preset cards --------------------------------------------------
// Three selectable cards mapped to the `llmTone` setting. The selected value is
// mirrored into the hidden #llmTone input that collectSettings reads.
function setTone(tone) {
    const valid = ['formal', 'casual', 'veryCasual'];
    const value = valid.includes(tone) ? tone : 'formal';
    document.getElementById('llmTone').value = value;
    document.querySelectorAll('#toneCards .tone-card').forEach(card => {
        const isSel = card.dataset.tone === value;
        card.classList.toggle('selected', isSel);
        card.setAttribute('aria-checked', isSel ? 'true' : 'false');
    });
}

document.querySelectorAll('#toneCards .tone-card').forEach(card => {
    card.addEventListener('click', () => { setTone(card.dataset.tone); autoSave(); });
});

// ----- Hotkey recorder ----------------------------------------------------
// Default accelerator if the setting is missing.
let hotkeyAccelerator = 'Alt+Space';
let recordingHotkey = false;
let recordingSawKey = false;   // a non-modifier key was pressed this session
let recordingLastMod = null;   // event.code of the last modifier pressed

const MODIFIER_KEYS = new Set(['Shift', 'Control', 'Alt', 'Meta', 'CapsLock', 'AltGraph']);

// Physical modifier keys (event.code) → bare-modifier hotkey token. A lone
// press+release of one of these sets it as a single-key trigger (handled by the
// native macOS monitor). Fn is NOT here — the web can't see it (use the Fn button).
const MODIFIER_CODE_TO_TOKEN = {
    ControlLeft: 'Control', ControlRight: 'RightControl',
    AltLeft: 'Option', AltRight: 'RightOption',
    MetaLeft: 'Command', MetaRight: 'RightCommand',
    ShiftLeft: 'Shift', ShiftRight: 'RightShift',
};

// Pretty labels for the bare-modifier / Fn trigger tokens.
const BARE_PRETTY = {
    Fn: 'fn', Control: '⌃', RightControl: '⌃ R', Option: '⌥', RightOption: '⌥ R',
    Command: '⌘', RightCommand: '⌘ R', Shift: '⇧', RightShift: '⇧ R',
};

const PRETTY_TOKENS = {
    CmdOrCtrl: '⌘',
    Command: '⌘',
    Cmd: '⌘',
    Super: '⌘',
    Meta: '⌘',
    Control: '⌃',
    Ctrl: '⌃',
    Alt: '⌥',
    Option: '⌥',
    Shift: '⇧',
};

// Render a hotkey string into pretty glyphs. Combos ("Alt+Space" → "⌥ Space")
// and bare-modifier tokens ("RightOption" → "⌥ R", "Fn" → "fn").
function prettyAccelerator(accel) {
    if (!accel) return '';
    if (BARE_PRETTY[accel]) return BARE_PRETTY[accel];
    return accel.split('+').map(t => PRETTY_TOKENS[t] || t).join(' ');
}

// Normalize a KeyboardEvent's main key into a Tauri accelerator token.
function normalizeMainKey(e) {
    let code = e.code || '';
    let key = e.key || '';

    if (code === 'Space' || key === ' ' || key === 'Spacebar') return 'Space';
    if (/^Key[A-Z]$/.test(code)) return code.slice(3); // KeyA -> A
    if (/^Digit[0-9]$/.test(code)) return code.slice(5); // Digit1 -> 1
    if (/^Numpad[0-9]$/.test(code)) return 'Num' + code.slice(6);
    if (/^F([1-9]|1[0-9]|2[0-4])$/.test(code)) return code; // F1..F24

    const named = {
        ArrowUp: 'Up', ArrowDown: 'Down', ArrowLeft: 'Left', ArrowRight: 'Right',
        Enter: 'Enter', Return: 'Enter', Tab: 'Tab', Backspace: 'Backspace',
        Delete: 'Delete', Home: 'Home', End: 'End', PageUp: 'PageUp', PageDown: 'PageDown',
        Minus: '-', Equal: '=', BracketLeft: '[', BracketRight: ']',
        Backslash: '\\', Semicolon: ';', Quote: "'", Comma: ',', Period: '.', Slash: '/', Backquote: '`',
    };
    if (named[code]) return named[code];
    if (named[key]) return named[key];

    // Single printable character -> uppercase it.
    if (key.length === 1) return key.toUpperCase();
    return '';
}

// F-keys (F1–F24) the OS can register as standalone global shortcuts. Other keys
// require a modifier (bare modifiers/Fn can't be registered by the shortcut API).
const STANDALONE_KEY = /^F([1-9]|1[0-9]|2[0-4])$/;

// Build a Tauri accelerator string from a keydown event, or null if invalid.
// Requires a modifier + key, EXCEPT a single F-key is allowed on its own.
function buildAccelerator(e) {
    if (MODIFIER_KEYS.has(e.key)) return null;
    const main = normalizeMainKey(e);
    if (!main) return null;

    const parts = [];
    if (e.metaKey || e.ctrlKey) parts.push('CmdOrCtrl');
    if (e.altKey) parts.push('Alt');
    if (e.shiftKey) parts.push('Shift');
    // Allow a lone F-key; otherwise require at least one modifier.
    if (parts.length === 0 && !STANDALONE_KEY.test(main)) return null;
    parts.push(main);
    return parts.join('+');
}

function setHotkeyDisplay() {
    document.getElementById('hotkeyDisplay').textContent =
        prettyAccelerator(hotkeyAccelerator) || 'Set shortcut…';
}

function showHotkeyError(msg) {
    const el = document.getElementById('hotkeyError');
    if (!el) return;
    if (msg) {
        el.textContent = msg;
        el.classList.remove('hidden');
    } else {
        el.textContent = '';
        el.classList.add('hidden');
    }
}

function startHotkeyRecording() {
    if (recordingHotkey) return;
    recordingHotkey = true;
    recordingSawKey = false;
    recordingLastMod = null;
    showHotkeyError('Press a key combo — or tap a single ⌃/⌥/⌘ for a one-key trigger. Esc to cancel.');
    const btn = document.getElementById('hotkeyRecorder');
    btn.classList.add('recording');
    document.getElementById('hotkeyDisplay').textContent = 'Press shortcut…';
    document.addEventListener('keydown', onHotkeyKeydown, true);
    document.addEventListener('keyup', onHotkeyKeyup, true);
}

function stopHotkeyRecording() {
    recordingHotkey = false;
    document.getElementById('hotkeyRecorder').classList.remove('recording');
    document.removeEventListener('keydown', onHotkeyKeydown, true);
    document.removeEventListener('keyup', onHotkeyKeyup, true);
    showHotkeyError(null);
    setHotkeyDisplay();
}

// Live-preview which modifiers are held so it's clear a key is still needed
// (pressing only a modifier like Control can't be a shortcut on its own).
function heldModifiersPretty(e) {
    const mods = [];
    if (e.metaKey || e.ctrlKey) mods.push('CmdOrCtrl');
    if (e.altKey) mods.push('Alt');
    if (e.shiftKey) mods.push('Shift');
    return mods.map((m) => PRETTY_TOKENS[m] || m).join(' ');
}

function onHotkeyKeydown(e) {
    if (!recordingHotkey) return;
    e.preventDefault();
    e.stopPropagation();

    if (e.key === 'Escape') {
        stopHotkeyRecording();
        return;
    }
    if (MODIFIER_KEYS.has(e.key)) {
        // Remember the physical modifier; a clean tap of it = a one-key trigger.
        if (MODIFIER_CODE_TO_TOKEN[e.code]) recordingLastMod = e.code;
        const pretty = heldModifiersPretty(e);
        document.getElementById('hotkeyDisplay').textContent = pretty ? `${pretty} …` : 'Press shortcut…';
        return; // wait for a key, or a clean release (handled in keyup)
    }

    recordingSawKey = true;
    const accel = buildAccelerator(e);
    if (!accel) {
        showHotkeyError('Add a modifier (⌘/⌥/⌃/⇧) and a key, use a single F-key, or tap one modifier on its own.');
        return;
    }
    hotkeyAccelerator = accel;
    stopHotkeyRecording();
    autoSave();
}

function onHotkeyKeyup(e) {
    if (!recordingHotkey) return;
    // Only act once every modifier is released.
    if (e.metaKey || e.ctrlKey || e.altKey || e.shiftKey) return;

    // A clean tap of a single modifier (no other key pressed) → one-key trigger.
    if (!recordingSawKey && recordingLastMod && MODIFIER_CODE_TO_TOKEN[recordingLastMod]) {
        hotkeyAccelerator = MODIFIER_CODE_TO_TOKEN[recordingLastMod];
        stopHotkeyRecording();
        autoSave();
        return;
    }
    // Otherwise reset the prompt (not stuck).
    document.getElementById('hotkeyDisplay').textContent = 'Press shortcut…';
    recordingLastMod = null;
}

document.getElementById('hotkeyRecorder').addEventListener('click', () => {
    if (recordingHotkey) {
        stopHotkeyRecording();
    } else {
        startHotkeyRecording();
    }
});

// The Fn key can't be detected via the web recorder, so set it explicitly.
document.getElementById('hotkeyFnBtn')?.addEventListener('click', () => {
    if (recordingHotkey) stopHotkeyRecording();
    hotkeyAccelerator = 'Fn';
    setHotkeyDisplay();
    showHotkeyError(null);
    autoSave();
});

// ----- Auto-save ----------------------------------------------------------
// Settings persist the moment they change — there is no Save button. A
// `settingsReady` gate suppresses the flurry of programmatic value-setting that
// happens during init() (loadValues, refreshModels, refreshAudioDevices, …) so
// we only persist genuine user edits.
let settingsReady = false;
let autoSaveTimer = null;

// IDs whose `change` event maps directly to a setting. (llmProvider is handled
// via refreshModels, which fires after the new model list is in place.)
const AUTO_SAVE_CHANGE_IDS = [
    'hotkeyMode', 'language', 'flowMode', 'codeMode', 'privacyMode',
    'llmEnabled', 'llmModel', 'overlayPosition', 'audioDevice',
];
// Text/range inputs: debounce so we don't write on every keystroke / drag tick.
const AUTO_SAVE_INPUT_IDS = ['llmEndpoint', 'llmApiKey'];

function collectSettings() {
    return {
        hotkey: hotkeyAccelerator,
        hotkeyMode: document.getElementById('hotkeyMode').value,
        whisperModelPath: document.getElementById('whisperModelPath').value,
        whisperLanguage: document.getElementById('language').value,
        llmEnabled: document.getElementById('llmEnabled').checked,
        llmEndpoint: document.getElementById('llmEndpoint').value,
        llmModel: document.getElementById('llmModel').value,
        llmApiKey: document.getElementById('llmApiKey').value,
        llmProvider: document.getElementById('llmProvider').value,
        llmTone: document.getElementById('llmTone').value,
        llmAccuracy: parseInt(document.getElementById('llmAccuracy').value),
        flowMode: document.getElementById('flowMode').checked,
        codeMode: document.getElementById('codeMode').checked,
        privacyMode: document.getElementById('privacyMode').checked,
        overlayPosition: document.getElementById('overlayPosition').value,
        onboardingDone: currentSettings?.onboardingDone ?? true,
        audioInputDevice: getSelectedAudioDevice(),
    };
}

// Persist the current form state immediately. Keeps the window open; surfaces a
// rejected (e.g. invalid hotkey) save inline near the hotkey recorder.
async function autoSave() {
    if (!settingsReady) return;
    const data = collectSettings();
    try {
        showHotkeyError(null);
        await invoke('save_settings', { data });
        currentSettings = data;
    } catch (e) {
        console.error('Failed to save settings:', e);
        showHotkeyError("Couldn't save — " + (typeof e === 'string' ? e : (e?.message || 'those settings look invalid.')));
    }
}

function autoSaveDebounced() {
    clearTimeout(autoSaveTimer);
    autoSaveTimer = setTimeout(autoSave, 350);
}

function wireAutoSave() {
    AUTO_SAVE_CHANGE_IDS.forEach(id => {
        document.getElementById(id)?.addEventListener('change', autoSave);
    });
    AUTO_SAVE_INPUT_IDS.forEach(id => {
        document.getElementById(id)?.addEventListener('input', autoSaveDebounced);
    });
}

async function init() {
    platform = await invoke('get_platform');
    currentSettings = await invoke('get_settings');
    loadValues(currentSettings);
    // Enhance the native selects with custom Codex-style dropdowns. Done after
    // loadValues so each select already reflects the saved value when built.
    ['hotkeyMode', 'language', 'llmProvider', 'llmModel', 'overlayPosition', 'audioDevice', 'whisperModelSelect']
        .forEach(id => enhanceSelect(document.getElementById(id)));
    updateProviderFields();
    updateDictCloudAccount();
    // Fetch the available models for the current endpoint. The saved model is
    // already present as an option (added in loadValues), so it stays selectable
    // even before/if the fetch returns.
    refreshModels();
    // Wire up the Whisper model manager (dropdown change, download, progress).
    setupWhisperModelManager();
    // Populate the Whisper catalog and preselect the saved model.
    refreshWhisperModels();
    // Populate the mic dropdown and select the saved device up front so the
    // selection is correct even before the Speech section is opened.
    await refreshAudioDevices();
    // All controls now reflect saved state; arm auto-save for real user edits.
    wireAutoSave();
    settingsReady = true;
}

function loadValues(s) {
    hotkeyAccelerator = s.hotkey || 'Alt+Space';
    setHotkeyDisplay();

    document.getElementById('hotkeyMode').value = s.hotkeyMode;
    document.getElementById('language').value = s.whisperLanguage;
    document.getElementById('flowMode').checked = s.flowMode;
    document.getElementById('codeMode').checked = s.codeMode;
    document.getElementById('privacyMode').checked = s.privacyMode;

    // Hidden field; refreshWhisperModels() preselects by matching this path.
    document.getElementById('whisperModelPath').value = s.whisperModelPath || '';

    document.getElementById('llmEnabled').checked = s.llmEnabled;
    setAccuracy(s.llmAccuracy);
    document.getElementById('llmProvider').value = s.llmProvider;
    // #llmModel is now a <select>; ensure the saved model exists as an option so
    // it displays before refreshModels() repopulates the list from the endpoint.
    const modelSelect = document.getElementById('llmModel');
    if (s.llmModel && !Array.from(modelSelect.options).some(o => o.value === s.llmModel)) {
        const opt = document.createElement('option');
        opt.value = s.llmModel;
        opt.textContent = s.llmModel;
        modelSelect.appendChild(opt);
    }
    modelSelect.value = s.llmModel;
    document.getElementById('llmEndpoint').value = s.llmEndpoint;
    document.getElementById('llmApiKey').value = s.llmApiKey;
    setTone(s.llmTone || 'formal');

    document.getElementById('overlayPosition').value = s.overlayPosition;
}

function updateProviderFields() {
    const provider = document.getElementById('llmProvider').value;
    const isDictCloud = provider === 'dictcloud';
    const isCloud = provider === 'openai' || provider === 'anthropic' || provider === 'openrouter';

    document.getElementById('llmEndpoint').disabled = true;
    document.getElementById('llmEndpoint').placeholder = PROVIDER_ENDPOINTS[provider] || '';

    // Dict Cloud is fully managed: no key, endpoint, or model to configure.
    document.getElementById('apiKeyRow').style.display = isCloud ? 'flex' : 'none';
    document.getElementById('endpointRow').style.display = isDictCloud ? 'none' : 'flex';
    document.getElementById('modelRow').style.display = isDictCloud ? 'none' : 'flex';
    document.getElementById('dictCloudNote').style.display = isDictCloud ? 'flex' : 'none';

    // No model list to fetch for Dict Cloud; refreshModels persists for the
    // others, so persist here when switching to Dict Cloud. (No-op during init.)
    if (isDictCloud) {
        autoSave();
    } else {
        refreshModels();
    }
}

// Fetch the available models for the SELECTED provider and rebuild the #llmModel
// dropdown. Behavior depends on whether the provider just changed:
//   - same provider (e.g. initial load / endpoint or key edit): preserve the
//     saved/selected model as a fallback option so the user's choice survives a
//     failed/empty fetch.
//   - provider changed: do NOT keep the previous provider's model — clear the
//     selection first so e.g. switching to Anthropic doesn't keep showing an
//     LM Studio model. After fetching, select the first returned model (or none).
async function refreshModels() {
    const select = document.getElementById('llmModel');
    if (!select) return;

    const provider = document.getElementById('llmProvider').value;
    const providerChanged = lastModelProvider !== null && lastModelProvider !== provider;

    // On a provider switch, drop the previous provider's model entirely.
    if (providerChanged) select.value = '';

    // Only preserve a selection when the provider hasn't changed.
    const current = providerChanged
        ? ''
        : (select.value || currentSettings?.llmModel || '');

    const endpointInput = document.getElementById('llmEndpoint').value.trim();
    const endpoint = endpointInput || PROVIDER_ENDPOINTS[provider] || '';
    const apiKey = document.getElementById('llmApiKey').value;

    let models = [];
    try {
        models = (await invoke('list_llm_models', { provider, endpoint, apiKey })) || [];
    } catch (e) {
        console.error('Failed to list LLM models:', e);
        models = [];
    }

    // On a same-provider reload, guarantee the current model stays available so
    // the saved value survives an empty/failed fetch.
    const ids = [...models];
    if (current && !ids.includes(current)) ids.unshift(current);

    select.innerHTML = '';
    ids.forEach(id => {
        const opt = document.createElement('option');
        opt.value = id;
        opt.textContent = id;
        select.appendChild(opt);
    });

    // Same provider: restore the selection. Provider changed: pick the first
    // returned model (or leave empty when none came back).
    if (current) {
        select.value = current;
    } else {
        select.value = ids.length ? ids[0] : '';
    }

    lastModelProvider = provider;
    rebuildCustomSelect(select);
    // A provider switch lands here with the new model already selected; persist it.
    autoSave();
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
        // Rebuild the custom dropdown so it reflects the new options + value.
        rebuildCustomSelect(select);
    } catch (e) {
        console.error('Failed to list audio devices:', e);
    }
}

// ----- Whisper model manager ----------------------------------------------
// Backed by `list_whisper_models` (a fixed catalog with download status) and
// `download_whisper_model` (resolves to the local path; emits
// `whisper-download-progress` events while running). The custom dropdown lists
// every catalog model; the selected model is either Ready (downloaded — its
// `path` is mirrored into the hidden #whisperModelPath that collectSettings reads)
// or offers a Download button + progress bar.

let whisperModels = [];      // [{ name, filename, size, downloaded, path }]
let downloadingModel = null; // name of the model currently downloading, or null

// Human-readable size for a catalog entry. `size` may already be a string
// ("1.5 GB") or a byte count; format bytes, pass strings through.
function whisperModelSizeLabel(m) {
    if (m == null) return '';
    const s = m.size;
    if (s == null) return '';
    if (typeof s === 'string') return s;
    return formatBytes(s);
}

function formatBytes(bytes) {
    if (!bytes || bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    let v = bytes;
    let i = 0;
    while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
    return `${v >= 100 || i === 0 ? Math.round(v) : v.toFixed(1)} ${units[i]}`;
}

// Build the dropdown <option>s from the catalog. Each option's label is the
// model name; data-desc carries "<size> · <status>".
function rebuildWhisperOptions(selectedName) {
    const select = document.getElementById('whisperModelSelect');
    if (!select) return;
    select.innerHTML = '';
    whisperModels.forEach(m => {
        const opt = document.createElement('option');
        opt.value = m.name;
        opt.textContent = m.name;
        const size = whisperModelSizeLabel(m);
        const status = m.downloaded ? 'Ready' : 'Not downloaded';
        opt.dataset.desc = size ? `${size} · ${status}` : status;
        opt.dataset.icon = m.downloaded ? '●' : '○';
        select.appendChild(opt);
    });
    if (selectedName != null) {
        const exists = whisperModels.some(m => m.name === selectedName);
        if (exists) select.value = selectedName;
    }
    rebuildCustomSelect(select);
}

// Decide which model to preselect: the saved path's model, else the first
// downloaded model, else the first catalog entry.
function pickInitialWhisperModel() {
    const savedPath = document.getElementById('whisperModelPath').value
        || currentSettings?.whisperModelPath || '';
    if (savedPath) {
        const byPath = whisperModels.find(m => m.path && m.path === savedPath);
        if (byPath) return byPath;
    }
    const firstDownloaded = whisperModels.find(m => m.downloaded);
    if (firstDownloaded) return firstDownloaded;
    return whisperModels[0] || null;
}

function selectedWhisperModel() {
    const name = document.getElementById('whisperModelSelect').value;
    return whisperModels.find(m => m.name === name) || null;
}

// Reflect the selected model's state into the status UI + hidden path field.
// Downloaded => mirror its path into #whisperModelPath (what collectSettings sends)
// and show "Ready". Not downloaded => show the Download button with its size.
function updateWhisperModelUI() {
    const ready = document.getElementById('whisperReady');
    const dlBtn = document.getElementById('whisperDownloadBtn');
    const dlLabel = document.getElementById('whisperDownloadLabel');
    const delBtn = document.getElementById('whisperDeleteBtn');
    const pathInput = document.getElementById('whisperModelPath');
    const model = selectedWhisperModel();

    // The in-button ring is only shown while this exact model is downloading.
    const isDownloadingThis = model && downloadingModel === model.name;

    if (!model) {
        ready.classList.add('hidden');
        dlBtn.classList.add('hidden');
        resetWhisperDownloadButton();
        delBtn.classList.add('hidden');
        return;
    }

    if (model.downloaded) {
        if (model.path) pathInput.value = model.path;
        ready.classList.remove('hidden');
        resetWhisperDownloadButton();
        dlBtn.classList.add('hidden');
        // Offer deletion for downloaded models (but not mid-download).
        delBtn.disabled = false;
        delBtn.classList.toggle('hidden', isDownloadingThis);
    } else {
        ready.classList.add('hidden');
        delBtn.classList.add('hidden');
        if (isDownloadingThis) {
            // Keep the button visible in its downloading state (driven by
            // setWhisperProgress); don't reset it here.
            dlBtn.classList.remove('hidden');
        } else {
            resetWhisperDownloadButton();
            const size = whisperModelSizeLabel(model);
            dlLabel.textContent = size ? `Download (${size})` : 'Download';
            dlBtn.disabled = false;
            dlBtn.classList.remove('hidden');
        }
    }
}

function showWhisperError(msg) {
    const el = document.getElementById('whisperError');
    if (!el) return;
    if (msg) {
        el.textContent = msg;
        el.classList.remove('hidden');
    } else {
        el.textContent = '';
        el.classList.add('hidden');
    }
}

// Circumference of the in-button progress ring (r=8 in the SVG => 2πr).
const RING_CIRCUMFERENCE = 2 * Math.PI * 8;

// Put the Download button into its "downloading" state: show the inline ring +
// percent and disable it. Determinate when total is known, otherwise a spinning
// indeterminate ring with a "Downloading…" label.
function setWhisperProgress(downloaded, total) {
    const btn = document.getElementById('whisperDownloadBtn');
    const ring = document.getElementById('whisperDownloadRing');
    const fill = document.getElementById('whisperDownloadRingFill');
    const label = document.getElementById('whisperDownloadLabel');
    if (!btn) return;

    btn.classList.add('downloading');
    btn.disabled = true;
    btn.classList.remove('hidden');
    ring.classList.remove('hidden');
    fill.style.strokeDasharray = RING_CIRCUMFERENCE;

    if (total && total > 0) {
        const pct = Math.max(0, Math.min(100, Math.round((downloaded / total) * 100)));
        ring.classList.remove('indeterminate');
        fill.style.strokeDashoffset = RING_CIRCUMFERENCE * (1 - pct / 100);
        label.textContent = pct + '%';
    } else {
        // Unknown total: indeterminate spinning ring with a "Downloading…" hint.
        ring.classList.add('indeterminate');
        fill.style.strokeDashoffset = RING_CIRCUMFERENCE * 0.75;
        label.textContent = 'Downloading…';
    }
}

// Reset the Download button out of its downloading state back to a normal,
// clickable button (label restored by updateWhisperModelUI).
function resetWhisperDownloadButton() {
    const btn = document.getElementById('whisperDownloadBtn');
    const ring = document.getElementById('whisperDownloadRing');
    if (!btn) return;
    btn.classList.remove('downloading');
    ring.classList.add('hidden', 'indeterminate');
    ring.classList.remove('indeterminate');
}

// Fetch the catalog, rebuild the dropdown, preserve/restore the selection, and
// refresh the status UI. Called on init, when Speech opens, and after a download.
async function refreshWhisperModels() {
    const select = document.getElementById('whisperModelSelect');
    if (!select) return;
    const prev = select.value;
    try {
        whisperModels = (await invoke('list_whisper_models')) || [];
    } catch (e) {
        console.error('Failed to list Whisper models:', e);
        whisperModels = [];
    }
    // Keep the current selection if still present; otherwise pick a sensible default.
    let selectName = prev && whisperModels.some(m => m.name === prev) ? prev : null;
    if (!selectName) {
        const initial = pickInitialWhisperModel();
        selectName = initial ? initial.name : null;
    }
    rebuildWhisperOptions(selectName);
    updateWhisperModelUI();
}

async function downloadSelectedWhisperModel() {
    const model = selectedWhisperModel();
    if (!model || model.downloaded || downloadingModel) return;

    showWhisperError(null);
    downloadingModel = model.name;
    // Put the Download button into its in-button progress (indeterminate) state.
    setWhisperProgress(0, 0);

    try {
        const path = await invoke('download_whisper_model', { name: model.name });
        // Mark downloaded locally and adopt it as the active model.
        model.downloaded = true;
        if (path) {
            model.path = path;
            document.getElementById('whisperModelPath').value = path;
        }
        downloadingModel = null;
        // Re-fetch the catalog so statuses are authoritative, keeping selection.
        await refreshWhisperModels();
        // The freshly downloaded model is now active — persist its path.
        autoSave();
    } catch (e) {
        console.error('Failed to download Whisper model:', e);
        downloadingModel = null;
        showWhisperError("Download didn't finish — " + (typeof e === 'string' ? e : (e?.message || 'something went wrong. Try again.')));
        resetWhisperDownloadButton();
        updateWhisperModelUI();
    }
}

// Delete the selected downloaded model's file. After deletion, prefer keeping a
// still-downloaded model active so #whisperModelPath never points at a missing file.
async function deleteSelectedWhisperModel() {
    const model = selectedWhisperModel();
    if (!model || !model.downloaded || downloadingModel) return;

    showWhisperError(null);
    const delBtn = document.getElementById('whisperDeleteBtn');
    delBtn.disabled = true;
    try {
        await invoke('delete_whisper_model', { name: model.name });
        const pathInput = document.getElementById('whisperModelPath');
        // Drop the saved path if it pointed at the model we just deleted.
        if (pathInput.value === model.path) pathInput.value = '';
        // Re-fetch authoritative statuses, then bias selection to a model that's
        // still downloaded (falling back to the just-deleted one as "downloadable").
        whisperModels = (await invoke('list_whisper_models')) || [];
        const stillDownloaded = whisperModels.find(m => m.downloaded);
        rebuildWhisperOptions(stillDownloaded ? stillDownloaded.name : model.name);
        updateWhisperModelUI();
        // Active model/path may have changed (cleared or moved); persist it.
        autoSave();
    } catch (e) {
        console.error('Failed to delete Whisper model:', e);
        showWhisperError("Couldn't delete that model — " + (typeof e === 'string' ? e : (e?.message || 'something went wrong. Try again.')));
        delBtn.disabled = false;
        updateWhisperModelUI();
    }
}

// One-time wiring: dropdown change, download button, and the single progress
// event listener. Events for a model other than the one downloading are ignored.
function setupWhisperModelManager() {
    document.getElementById('whisperModelSelect')?.addEventListener('change', () => {
        showWhisperError(null);
        updateWhisperModelUI();
        // Selecting a downloaded model switches the active model path; persist it.
        autoSave();
    });
    document.getElementById('whisperDownloadBtn')?.addEventListener('click', downloadSelectedWhisperModel);
    document.getElementById('whisperDeleteBtn')?.addEventListener('click', deleteSelectedWhisperModel);

    listen('whisper-download-progress', (event) => {
        const p = event.payload || {};
        if (!downloadingModel || p.name !== downloadingModel) return;
        setWhisperProgress(p.downloaded || 0, p.total || 0);
    }).catch(console.error);
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

// Icon-only "copy to clipboard" button for a history entry. On success it briefly
// swaps to a checkmark and shows a "Copied" tooltip. Marked no-drag so it stays
// clickable inside the draggable window chrome.
const COPY_ICON_SVG =
    '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="11" height="11" rx="2.5"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>';
const CHECK_ICON_SVG =
    '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>';

function makeCopyButton(text) {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'history-copy';
    btn.title = 'Copy';
    btn.setAttribute('aria-label', 'Copy transcription');
    btn.innerHTML = COPY_ICON_SVG;

    let resetTimer = null;
    btn.addEventListener('click', async (e) => {
        e.stopPropagation();
        try {
            await navigator.clipboard.writeText(text);
            btn.innerHTML = CHECK_ICON_SVG;
            btn.classList.add('copied');
            btn.title = 'Copied';
            clearTimeout(resetTimer);
            resetTimer = setTimeout(() => {
                btn.innerHTML = COPY_ICON_SVG;
                btn.classList.remove('copied');
                btn.title = 'Copy';
            }, 1000);
        } catch (err) {
            console.error('Failed to copy to clipboard:', err);
        }
    });
    return btn;
}

// History (read-only)
async function loadHistory() {
    const list = document.getElementById('historyList');
    try {
        const entries = await invoke('get_history');
        list.innerHTML = '';
        // Show only the transcription text + a copy button. App/engine/timestamp
        // are still persisted by the backend, just not displayed here.
        // Stored oldest-first; render newest-first so the latest is on top.
        entries.slice().reverse().forEach(entry => {
            const item = document.createElement('div');
            item.className = 'history-item';

            const text = entry.cleaned || entry.raw || '';

            // Copy button, pinned to the top-right of the item.
            const right = document.createElement('div');
            right.className = 'history-actions';
            right.appendChild(makeCopyButton(text));
            item.appendChild(right);

            const cleaned = document.createElement('div');
            cleaned.className = 'history-cleaned';
            cleaned.textContent = text;
            item.appendChild(cleaned);

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
