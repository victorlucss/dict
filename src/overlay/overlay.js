const { listen } = window.__TAURI__.event;

const DOT_COUNT = 10;
const MIN_SCALE = 0.57;  // minRadius/maxRadius = 2/3.5
const MAX_SCALE = 1.0;

let isProcessing = false;
let processingPhase = 0;
let processingInterval = null;
let verbose = false;

// Create dots
const dotsContainer = document.getElementById('dots');
for (let i = 0; i < DOT_COUNT; i++) {
    const dot = document.createElement('div');
    dot.className = 'dot';
    dotsContainer.appendChild(dot);
}
const dots = dotsContainer.querySelectorAll('.dot');

const overlay = document.getElementById('overlay');
const label = document.getElementById('label');

// Listen for audio level updates
listen('audio-level', (event) => {
    if (isProcessing) return;
    const level = Math.max(0, Math.min(1, event.payload));
    updateDots(level);
});

// Listen for state changes
listen('overlay-state', (event) => {
    const state = event.payload;

    if (state.verbose !== undefined) {
        verbose = state.verbose;
        overlay.classList.toggle('verbose', verbose);
        label.style.display = verbose ? 'block' : 'none';
    }

    if (state.warning) {
        overlay.classList.add('warning');
    }

    if (state.processing) {
        startProcessing();
        if (verbose) label.textContent = 'Processing...';
    }

    if (state.text && verbose) {
        label.textContent = state.text;
    }
});

function updateDots(level) {
    const center = DOT_COUNT / 2;
    dots.forEach((dot, i) => {
        const distance = Math.abs(i - center) / center;
        const dotLevel = level * (1.0 - distance * 0.6);
        const scale = MIN_SCALE + dotLevel * (MAX_SCALE - MIN_SCALE);
        const opacity = 0.3 + dotLevel * 0.7;
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
