const { invoke } = window.__TAURI__.core;

let currentStep = 0;
let platform = 'macos';

const macSteps = [
    {
        icon: '🎙',
        title: 'Welcome to Dict',
        description: 'Dict converts your voice to text using a global hotkey.\nPress Option+Space anywhere to start dictating.',
        action: 'Get Started'
    },
    {
        icon: '🎤',
        title: 'Microphone Access',
        description: 'Dict needs microphone access to hear your voice.\nThis will prompt for permission if not already granted.',
        action: 'Grant Microphone'
    },
    {
        icon: '🔒',
        title: 'Accessibility Permission',
        description: 'Dict needs Accessibility access to paste text into apps.\nYou\'ll need to enable it manually in System Settings.',
        action: 'Open System Settings'
    },
    {
        icon: '🔊',
        title: 'Set Up Whisper',
        description: 'Dict transcribes with Whisper, running locally on your machine.\nInstall it with Homebrew: brew install whisper-cpp\nThen download a GGML model file and point Dict at it in Preferences → Speech.',
        action: 'Continue'
    },
    {
        icon: '✅',
        title: "You're All Set!",
        description: 'Press Option+Space to start dictating.\nClick the menu bar icon to adjust settings.\n\nTip: Enable LLM cleanup for grammar fixes.',
        action: 'Done'
    }
];

const otherSteps = [
    {
        icon: '🎙',
        title: 'Welcome to Dict',
        description: 'Dict converts your voice to text using a global hotkey.\nPress Ctrl+Alt+Space anywhere to start dictating.',
        action: 'Get Started'
    },
    {
        icon: '🎤',
        title: 'Microphone Access',
        description: 'Dict needs microphone access to hear your voice.\nYour system may prompt for permission.',
        action: 'Continue'
    },
    {
        icon: '🔊',
        title: 'Set Up Whisper',
        description: 'Dict transcribes with Whisper, running locally on your machine.\nInstall whisper-cpp using your package manager.\nThen download a GGML model file and point Dict at it in Preferences → Speech.',
        action: 'Continue'
    },
    {
        icon: '✅',
        title: "You're All Set!",
        description: 'Press Ctrl+Alt+Space to start dictating.\nClick the tray icon to adjust settings.\n\nTip: Enable LLM cleanup for grammar fixes.',
        action: 'Done'
    }
];

let steps = macSteps;

const titleEl = document.getElementById('stepTitle');
const descEl = document.getElementById('stepDescription');
const iconEl = document.getElementById('stepIcon');
const primaryBtn = document.getElementById('primaryBtn');
const secondaryBtn = document.getElementById('secondaryBtn');
const indicatorEl = document.getElementById('stepIndicator');

primaryBtn.addEventListener('click', handlePrimary);
secondaryBtn.addEventListener('click', handleSecondary);

async function init() {
    platform = await invoke('get_platform');
    steps = platform === 'macos' ? macSteps : otherSteps;
    renderStep();
}

function renderStep() {
    const step = steps[currentStep];
    iconEl.textContent = step.icon;
    titleEl.textContent = step.title;
    descEl.innerHTML = step.description.replace(/\n/g, '<br>');
    primaryBtn.textContent = step.action;
    secondaryBtn.style.display = step.secondary ? 'block' : 'none';
    if (step.secondary) secondaryBtn.textContent = step.secondary;
    indicatorEl.textContent = `${currentStep + 1} of ${steps.length}`;
    // Hide indicator on engine choice step
    indicatorEl.style.display = step.secondary ? 'none' : 'block';
}

async function handlePrimary() {
    const step = steps[currentStep];

    if (step.title.includes('Accessibility')) {
        // Open system settings
        invoke('open_accessibility_settings').catch(console.error);
        advance();
    } else if (step.action === 'Done') {
        await finish();
    } else {
        advance();
    }
}

async function handleSecondary() {
    advance();
}

function advance() {
    currentStep++;
    if (currentStep < steps.length) {
        renderStep();
    } else {
        finish();
    }
}

async function finish() {
    const settings = await invoke('get_settings');
    await invoke('save_settings', { data: { ...settings, onboardingDone: true } });
    const { getCurrentWindow } = window.__TAURI__.window;
    getCurrentWindow().close();
}

init();
