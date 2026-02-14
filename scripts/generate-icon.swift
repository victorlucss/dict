#!/usr/bin/swift
import AppKit

let sizes: [(Int, String)] = [
    (16, "icon_16x16"),
    (32, "icon_16x16@2x"),
    (32, "icon_32x32"),
    (64, "icon_32x32@2x"),
    (128, "icon_128x128"),
    (256, "icon_128x128@2x"),
    (256, "icon_256x256"),
    (512, "icon_256x256@2x"),
    (512, "icon_512x512"),
    (1024, "icon_512x512@2x"),
]

func renderIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()

    // Rounded rect clip
    let cornerRadius = s * 0.22
    let rect = NSRect(x: 0, y: 0, width: s, height: s)
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    path.addClip()

    // Flat background
    NSColor(calibratedRed: 0.18, green: 0.18, blue: 0.22, alpha: 1.0).setFill()
    rect.fill()

    // Waveform bars — symmetric, centered
    let barColor = NSColor.white.withAlphaComponent(0.9)
    barColor.setFill()

    let centerX = s * 0.5
    let centerY = s * 0.5
    let barWidth = s * 0.045
    let gap = s * 0.075
    let barRadius = barWidth * 0.4

    // Heights for 9 bars (center is tallest)
    let heights: [CGFloat] = [0.10, 0.18, 0.28, 0.40, 0.55, 0.40, 0.28, 0.18, 0.10]
    let barCount = heights.count
    let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * (gap - barWidth)

    for (i, h) in heights.enumerated() {
        let barHeight = s * h
        let x = centerX - totalWidth / 2 + CGFloat(i) * gap
        let y = centerY - barHeight / 2
        let barRect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
        NSBezierPath(roundedRect: barRect, xRadius: barRadius, yRadius: barRadius).fill()
    }

    img.unlockFocus()
    return img
}

let projectDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconsetDir = projectDir.appendingPathComponent("Resources/AppIcon.iconset")

try? FileManager.default.removeItem(at: iconsetDir)
try! FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

for (size, name) in sizes {
    let img = renderIcon(size: size)
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else { continue }
    let path = iconsetDir.appendingPathComponent("\(name).png")
    try! png.write(to: path)
    print("Generated \(name).png (\(size)x\(size))")
}

print("Done. Converting to icns...")
