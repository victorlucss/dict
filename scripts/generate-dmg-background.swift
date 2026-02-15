#!/usr/bin/swift
import AppKit

// Must match --window-size exactly (800x450)
let width: CGFloat = 800
let height: CGFloat = 450

let img = NSImage(size: NSSize(width: width, height: height))
img.lockFocus()

// --- Gradient background (light gray at top to white at bottom) ---
let topColor = NSColor(calibratedWhite: 0.85, alpha: 1.0)
let bottomColor = NSColor.white

let bgGradient = NSGradient(starting: bottomColor, ending: topColor)!
bgGradient.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 90)

// --- Drag hint: arrow between icon zones ---
// Icons at x=200 and x=600, y=200 in Finder (top-down) coords
// In image coords (bottom-up): y = 450 - 200 = 250
let arrowColor = NSColor.black.withAlphaComponent(0.15)
let arrowY: CGFloat = 250
let arrowStartX: CGFloat = 280
let arrowEndX: CGFloat = 520
let headSize: CGFloat = 10

// Curved dashed line (hand-drawn feel, slight arc upward)
let linePath = NSBezierPath()
linePath.move(to: NSPoint(x: arrowStartX, y: arrowY))
linePath.curve(
    to: NSPoint(x: arrowEndX - headSize, y: arrowY),
    controlPoint1: NSPoint(x: arrowStartX + 80, y: arrowY + 30),
    controlPoint2: NSPoint(x: arrowEndX - 80, y: arrowY + 30)
)
arrowColor.setStroke()
linePath.lineWidth = 1.5
linePath.lineCapStyle = .round
let dashPattern: [CGFloat] = [8, 5]
linePath.setLineDash(dashPattern, count: 2, phase: 0)
linePath.stroke()

// Solid filled arrowhead triangle (angled to match curve end)
let headPath = NSBezierPath()
headPath.move(to: NSPoint(x: arrowEndX, y: arrowY))
headPath.line(to: NSPoint(x: arrowEndX - headSize, y: arrowY + headSize * 0.6))
headPath.line(to: NSPoint(x: arrowEndX - headSize, y: arrowY - headSize * 0.6))
headPath.close()
arrowColor.setFill()
headPath.fill()

// --- Instruction text at the bottom ---
// "Fix Gatekeeper.command" is positioned at {400, 350} in Finder (top-down)
// In image coords (bottom-up): y = 450 - 350 = 100, but text goes above the icon
// Place instruction above the script icon, around y=350 from top → 100 from bottom
let instructionFont = NSFont.systemFont(ofSize: 11, weight: .medium)
let instructionAttrs: [NSAttributedString.Key: Any] = [
    .font: instructionFont,
    .foregroundColor: NSColor.black.withAlphaComponent(0.4),
]

let line1 = "After dragging Dict to Applications," as NSString
let line2 = "read the instructions above to finish setup." as NSString
let line1Size = line1.size(withAttributes: instructionAttrs)
let line2Size = line2.size(withAttributes: instructionAttrs)

// Position centered horizontally, below the Fix Gatekeeper icon + its label
// Script icon at y=310 from top, icon ~50px, label ~15px → bottom of label ≈375 from top
// In image coords (bottom-up): 450 - 390 = 60
line1.draw(at: NSPoint(x: (width - line1Size.width) / 2, y: 55), withAttributes: instructionAttrs)
line2.draw(at: NSPoint(x: (width - line2Size.width) / 2, y: 55 - line2Size.height - 2), withAttributes: instructionAttrs)

img.unlockFocus()

// --- Save PNG ---
guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else {
    print("Error: Failed to render image")
    exit(1)
}

let projectDir = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let outputPath = projectDir.appendingPathComponent("Resources/dmg-background.png")

try! png.write(to: outputPath)
print("Generated DMG background at: \(outputPath.path)")
