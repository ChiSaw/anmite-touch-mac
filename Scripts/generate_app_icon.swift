import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    fputs("usage: generate_app_icon.swift <iconset-dir>\n", stderr)
    exit(1)
}

let iconsetURL = URL(fileURLWithPath: arguments[1], isDirectory: true)
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let iconSizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func makeImage(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.22

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.13, green: 0.43, blue: 0.49, alpha: 1.0),
        NSColor(calibratedRed: 0.08, green: 0.24, blue: 0.30, alpha: 1.0),
    ])!
    let background = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.04, dy: size * 0.04), xRadius: radius, yRadius: radius)
    gradient.draw(in: background, angle: -90)

    let trackWidth = size * 0.12
    let trackHeight = size * 0.50
    let trackRect = NSRect(
        x: size * 0.68,
        y: size * 0.25,
        width: trackWidth,
        height: trackHeight
    )
    NSColor(calibratedWhite: 1.0, alpha: 0.18).setFill()
    NSBezierPath(roundedRect: trackRect, xRadius: trackWidth / 2, yRadius: trackWidth / 2).fill()

    let thumbRect = NSRect(
        x: trackRect.minX,
        y: size * 0.47,
        width: trackWidth,
        height: size * 0.18
    )
    NSColor(calibratedWhite: 1.0, alpha: 0.92).setFill()
    NSBezierPath(roundedRect: thumbRect, xRadius: trackWidth / 2, yRadius: trackWidth / 2).fill()

    let symbolConfig = NSImage.SymbolConfiguration(pointSize: size * 0.44, weight: .bold)
    let symbol = NSImage(systemSymbolName: "hand.point.up.left.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig)

    let symbolRect = NSRect(x: size * 0.14, y: size * 0.18, width: size * 0.48, height: size * 0.48)
    NSColor.white.set()
    symbol?.draw(in: symbolRect)

    let accentRect = NSRect(x: size * 0.16, y: size * 0.70, width: size * 0.42, height: size * 0.08)
    NSColor(calibratedWhite: 1.0, alpha: 0.88).setFill()
    NSBezierPath(roundedRect: accentRect, xRadius: size * 0.04, yRadius: size * 0.04).fill()

    image.unlockFocus()
    return image
}

for (name, size) in iconSizes {
    let image = makeImage(size: size)
    guard let tiffData = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiffData),
          let png = rep.representation(using: .png, properties: [:]) else {
        continue
    }
    try png.write(to: iconsetURL.appendingPathComponent(name))
}
