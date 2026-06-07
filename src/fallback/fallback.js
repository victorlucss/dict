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

// Restart the CSS countdown animation from the top.
function restartCountdown() {
    ringFill.classList.remove('run');
    // Force reflow so removing + re-adding the class re-triggers the animation.
    void ringFill.offsetWidth;
    ringFill.classList.add('run');
}

function render(text) {
    currentText = text || '';
    textEl.textContent = currentText;
    headerEl.textContent = "Couldn't paste. Click to copy";
    timerIcon.innerHTML = COPY_SVG;
    popup.classList.remove('copied');
    restartCountdown();
}

// The popup closes once the ring fully depletes. Hovering pauses the animation
// (CSS), so this won't fire while the user is reading/hovering.
ringFill.addEventListener('animationend', () => {
    getCurrentWindow().close().catch(() => {});
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
