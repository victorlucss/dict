import AppKit
import AVFoundation

/// A small floating overlay window that appears when recording.
/// Shows a pulsing mic icon, audio level bars, and streaming transcription text.
class RecordingOverlay {
    private var window: NSPanel?
    private var levelView: AudioLevelView?
    private var textField: NSTextField?
    private var timer: Timer?
    private var micIcon: NSImageView?

    private var verbose: Bool { Settings.shared.verboseOverlay }

    private var currentWidth: CGFloat { verbose ? 340 : 140 }
    private var currentHeight: CGFloat { verbose ? 60 : 36 }

    func show() {
        guard window == nil else { return }

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let w = currentWidth
        let h = currentHeight
        let x = screenFrame.midX - w / 2
        let y: CGFloat
        switch Settings.shared.overlayPosition {
        case .top:
            y = screenFrame.maxY - h - 8
        case .bottom:
            y = screenFrame.minY + 8
        }

        let frame = NSRect(x: x, y: y, width: w, height: h)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true

        let container = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))

        let background = NSVisualEffectView(frame: container.bounds)
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = verbose ? 12 : 18
        background.layer?.masksToBounds = true
        container.addSubview(background)

        if verbose {
            // Mic icon
            let mic = NSImageView(frame: NSRect(x: 12, y: 20, width: 24, height: 24))
            mic.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording")
            mic.contentTintColor = .systemRed
            container.addSubview(mic)
            self.micIcon = mic

            // Audio level bars
            let level = AudioLevelView(frame: NSRect(x: 44, y: 20, width: 84, height: 24))
            container.addSubview(level)
            self.levelView = level

            // Streaming text label
            let text = NSTextField(labelWithString: "Listening...")
            text.frame = NSRect(x: 12, y: 4, width: w - 24, height: 16)
            text.font = .systemFont(ofSize: 11, weight: .medium)
            text.textColor = .secondaryLabelColor
            text.lineBreakMode = .byTruncatingTail
            text.maximumNumberOfLines = 1
            container.addSubview(text)
            self.textField = text
        } else {
            // Minimal: mic icon + level bars, vertically centered
            let mic = NSImageView(frame: NSRect(x: 12, y: 6, width: 20, height: 20))
            mic.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording")
            mic.contentTintColor = .systemRed
            container.addSubview(mic)
            self.micIcon = mic

            let level = AudioLevelView(frame: NSRect(x: 40, y: 6, width: 84, height: 20))
            container.addSubview(level)
            self.levelView = level
        }

        panel.contentView = container
        panel.orderFrontRegardless()
        window = panel

        startPulse(micIcon!)
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        window = nil
        levelView = nil
        textField = nil
        micIcon = nil
    }

    func updateLevel(_ level: Float) {
        levelView?.level = level
    }

    func updateText(_ text: String) {
        guard verbose else { return }
        DispatchQueue.main.async {
            self.textField?.stringValue = text
        }
    }

    func showProcessing() {
        DispatchQueue.main.async {
            if self.verbose {
                self.textField?.stringValue = "Processing..."
            }
            self.micIcon?.image = NSImage(systemSymbolName: "brain", accessibilityDescription: "Processing")
            self.micIcon?.contentTintColor = .systemBlue
        }
    }

    private func startPulse(_ view: NSView) {
        var growing = false
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            let current = view.alphaValue
            if current <= 0.4 { growing = true }
            if current >= 1.0 { growing = false }
            view.alphaValue = growing ? current + 0.03 : current - 0.03
        }
    }
}

/// Draws audio level as animated bars.
class AudioLevelView: NSView {
    var level: Float = 0 {
        didSet { needsDisplay = true }
    }

    private let barCount = 12
    private let barSpacing: CGFloat = 2
    private let barWidth: CGFloat = 4
    private let cornerRadius: CGFloat = 1.5

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let totalWidth = CGFloat(barCount) * (barWidth + barSpacing) - barSpacing
        let startX = (bounds.width - totalWidth) / 2

        for i in 0..<barCount {
            let x = startX + CGFloat(i) * (barWidth + barSpacing)

            let normalizedLevel = CGFloat(max(0, min(1, level)))
            let distance = abs(CGFloat(i) - CGFloat(barCount) / 2) / CGFloat(barCount / 2)
            let barLevel = normalizedLevel * (1.0 - distance * 0.5)
            let minHeight: CGFloat = 3
            let maxHeight: CGFloat = bounds.height - 2
            let barHeight = minHeight + barLevel * (maxHeight - minHeight)

            let y = (bounds.height - barHeight) / 2
            let rect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

            let alpha = 0.5 + normalizedLevel * 0.5
            NSColor.systemRed.withAlphaComponent(alpha).setFill()
            path.fill()
        }
    }
}
