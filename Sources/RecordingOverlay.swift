import AppKit
import AVFoundation

/// A minimal floating pill overlay that appears when recording.
/// Shows dot-style audio level indicators, no mic icon.
class RecordingOverlay {
    private var window: NSPanel?
    private var levelView: DotLevelView?
    private var textField: NSTextField?

    private var verbose: Bool { Settings.shared.verboseOverlay }

    private var currentWidth: CGFloat { verbose ? 200 : 100 }
    private var currentHeight: CGFloat { verbose ? 44 : 28 }

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
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        container.layer?.cornerRadius = h / 2

        if verbose {
            let level = DotLevelView(frame: NSRect(x: 12, y: 16, width: w - 24, height: 16))
            container.addSubview(level)
            self.levelView = level

            let text = NSTextField(labelWithString: "Listening...")
            text.frame = NSRect(x: 12, y: 2, width: w - 24, height: 12)
            text.font = .systemFont(ofSize: 9, weight: .medium)
            text.textColor = NSColor.white.withAlphaComponent(0.5)
            text.alignment = .center
            text.lineBreakMode = .byTruncatingTail
            text.maximumNumberOfLines = 1
            container.addSubview(text)
            self.textField = text
        } else {
            let level = DotLevelView(frame: NSRect(x: 12, y: 6, width: w - 24, height: 16))
            container.addSubview(level)
            self.levelView = level
        }

        panel.contentView = container
        panel.orderFrontRegardless()
        window = panel
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
        levelView = nil
        textField = nil
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
            if self.window == nil {
                self.show()
            }
            self.levelView?.isProcessing = true
            if self.verbose {
                self.textField?.stringValue = "Processing..."
            }
        }
    }
}

/// Draws audio level as a row of dots that grow/shrink with volume.
class DotLevelView: NSView {
    var level: Float = 0 {
        didSet { needsDisplay = true }
    }

    var isProcessing = false {
        didSet {
            if isProcessing { startProcessingAnimation() }
            else { stopProcessingAnimation() }
        }
    }

    private let dotCount = 10
    private let dotSpacing: CGFloat = 1.5
    private let minRadius: CGFloat = 2
    private let maxRadius: CGFloat = 3.5
    private var processingTimer: Timer?
    private var processingPhase: CGFloat = 0

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let totalWidth = CGFloat(dotCount) * (maxRadius * 2 + dotSpacing) - dotSpacing
        let startX = (bounds.width - totalWidth) / 2

        for i in 0..<dotCount {
            let centerX = startX + CGFloat(i) * (maxRadius * 2 + dotSpacing) + maxRadius
            let centerY = bounds.midY

            let radius: CGFloat
            let alpha: CGFloat

            if isProcessing {
                let wave = (sin(processingPhase + CGFloat(i) * 0.5) + 1) / 2
                radius = minRadius + wave * (maxRadius - minRadius)
                alpha = 0.4 + wave * 0.6
            } else {
                let normalizedLevel = CGFloat(max(0, min(1, level)))
                let center = CGFloat(dotCount) / 2
                let distance = abs(CGFloat(i) - center) / center
                let dotLevel = normalizedLevel * (1.0 - distance * 0.6)
                radius = minRadius + dotLevel * (maxRadius - minRadius)
                alpha = 0.3 + dotLevel * 0.7
            }

            let rect = NSRect(x: centerX - radius, y: centerY - radius, width: radius * 2, height: radius * 2)
            let path = NSBezierPath(ovalIn: rect)
            NSColor.white.withAlphaComponent(alpha).setFill()
            path.fill()
        }
    }

    private func startProcessingAnimation() {
        stopProcessingAnimation()
        processingTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.processingPhase += 0.15
            self.needsDisplay = true
        }
    }

    private func stopProcessingAnimation() {
        processingTimer?.invalidate()
        processingTimer = nil
        processingPhase = 0
    }
}
