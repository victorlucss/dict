const { listen } = window.__TAURI__.event;

const DOT_COUNT = 8;
const MIN_SCALE = 0.8;   // quiet → dots stay visible as a resting baseline
const MAX_SCALE = 2.4;   // loud  → dots grow well past base size (dramatic motion)

let isProcessing = false;
let processingPhase = 0;
let processingInterval = null;

// Smoothed level envelope: the raw audio level sets `targetLevel`; `displayLevel`
// eases toward it every frame (quick attack, gentle release) so the bars glide
// up and down instead of snapping. `phase` drives a subtle per-dot undulation.
let targetLevel = 0;
let displayLevel = 0;
let phase = 0;

// Create dots
const dotsContainer = document.getElementById('dots');
for (let i = 0; i < DOT_COUNT; i++) {
    const dot = document.createElement('div');
    dot.className = 'dot';
    dotsContainer.appendChild(dot);
}
const dots = dotsContainer.querySelectorAll('.dot');

const overlay = document.getElementById('overlay');

// Listen for audio level updates — just update the target; the rAF loop eases to it.
listen('audio-level', (event) => {
    if (isProcessing) return;
    targetLevel = Math.max(0, Math.min(1, event.payload));
});

// Animation loop: ease displayLevel toward targetLevel (fast up, soft down) and
// render with a gentle undulation so the bars feel alive rather than sharp.
function animate() {
    if (!isProcessing) {
        const factor = targetLevel > displayLevel ? 0.3 : 0.12;
        displayLevel += (targetLevel - displayLevel) * factor;
        phase += 0.16;
        renderDots(displayLevel, phase);
    }
    requestAnimationFrame(animate);
}
requestAnimationFrame(animate);

// Listen for state changes
listen('overlay-state', (event) => {
    const state = event.payload;

    if (state.warning !== undefined) {
        overlay.classList.toggle('warning', !!state.warning);
    }

    // A fresh recording / overlay show clears any previous warning state.
    if (state.recording) {
        overlay.classList.remove('warning');
        targetLevel = 0;
        displayLevel = 0;
        stopProcessing();
    }

    if (state.processing) {
        startProcessing();
    }
});

function renderDots(level, ph) {
    const center = (DOT_COUNT - 1) / 2;
    dots.forEach((dot, i) => {
        const distance = Math.abs(i - center) / center;
        // Lighter center-bias so the outer dots react too.
        let dotLevel = level * (1.0 - distance * 0.35);
        // Subtle per-dot undulation (scaled by level) so the bars gently move
        // up and down while active instead of sitting flat-topped.
        dotLevel += Math.sin(ph + i * 0.7) * 0.09 * level;
        dotLevel = Math.max(0, Math.min(1, dotLevel));
        const scale = MIN_SCALE + dotLevel * (MAX_SCALE - MIN_SCALE);
        const opacity = 0.35 + dotLevel * 0.65;
        dot.style.transform = `scale(${scale})`;
        dot.style.opacity = opacity;
    });
}

function startProcessing() {
    isProcessing = true;
    processingPhase = 0;
    if (processingInterval) clearInterval(processingInterval);
    processingInterval = setInterval(() => {
        processingPhase += 0.15;
        dots.forEach((dot, i) => {
            const wave = (Math.sin(processingPhase + i * 0.5) + 1) / 2;
            const scale = MIN_SCALE + wave * (MAX_SCALE - MIN_SCALE);
            const opacity = 0.4 + wave * 0.6;
            dot.style.transform = `scale(${scale})`;
            dot.style.opacity = opacity;
        });
    }, 40);
}

function stopProcessing() {
    isProcessing = false;
    if (processingInterval) {
        clearInterval(processingInterval);
        processingInterval = null;
    }
    processingPhase = 0;
}
