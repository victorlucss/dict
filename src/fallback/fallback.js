const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;
const { getCurrentWindow } = window.__TAURI__.window;

const popup = document.getElementById('popup');
const headerEl = document.getElementById('header');
const textEl = document.getElementById('text');
const ringFill = document.getElementById('ringFill');
const timerIcon = document.getElementById('timerIcon');

const CHECK_SVG =
    '<svg viewBox="0 0 24 24" width="11" height="11" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>';
const COPY_SVG = timerIcon.innerHTML;

let currentText = '';

const COUNTDOWN_MS = 5000;
let hideTimer = null;
let remainingMs = COUNTDOWN_MS;
let countdownStart = 0;

function clearHideTimer() {
    if (hideTimer !== null) {
        clearTimeout(hideTimer);
        hideTimer = null;
    }
}

function hidePopup() {
    clearHideTimer();
    // HIDE (not close) so the WKWebView is reused — closing it leaks the webview
    // in wry.
    getCurrentWindow().hide().catch(() => {});
}

function scheduleHide(ms) {
    clearHideTimer();
    countdownStart = Date.now();
    remainingMs = ms;
    hideTimer = setTimeout(hidePopup, ms);
}

// Restart the visual ring AND the (authoritative) JS hide timer. The close is
// driven by the timer rather than the CSS 'animationend' event: the popup window
// is now reused (hidden, not destroyed), and the CSS animation does not reliably
// restart across hide/show, which left the popup stuck open.
function restartCountdown() {
    ringFill.classList.remove('run');
    void ringFill.offsetWidth; // reflow so the visual ring restarts
    ringFill.classList.add('run');
    scheduleHide(COUNTDOWN_MS);
}

function render(text) {
    currentText = text || '';
    textEl.textContent = currentText;
    headerEl.textContent = "Couldn't paste. Click to copy";
    timerIcon.innerHTML = COPY_SVG;
    popup.classList.remove('copied');
    restartCountdown();
}

// Pause the countdown while the cursor is over the popup (mirrors the CSS pause),
// and resume with the time remaining once it leaves.
popup.addEventListener('mouseenter', () => {
    if (hideTimer !== null) {
        remainingMs = Math.max(0, remainingMs - (Date.now() - countdownStart));
        clearHideTimer();
    }
});
popup.addEventListener('mouseleave', () => {
    if (hideTimer === null && remainingMs > 0) {
        scheduleHide(remainingMs);
    }
});

popup.addEventListener('click', async () => {
    try {
        await navigator.clipboard.writeText(currentText);
        popup.classList.add('copied');
        headerEl.textContent = 'Copied to clipboard';
        timerIcon.innerHTML = CHECK_SVG;
    } catch (e) {
        console.error('Copy failed:', e);
    }
});

// An already-open popup gets refreshed text + a restarted countdown via this event.
listen('fallback-show', (e) => {
    const text = typeof e.payload === 'string' ? e.payload : String(e.payload ?? '');
    render(text);
});

// On first load, pull the staged transcription from the backend.
(async () => {
    let text = '';
    try {
        text = await invoke('get_fallback_text');
    } catch (e) {
        console.error('Failed to fetch fallback text:', e);
    }
    render(text);
})();
