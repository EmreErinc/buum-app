import AppKit
import CoreGraphics

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let iconsetPath = "/Users/emreerinc/projects/buum-app/Buum.iconset"

try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for size in sizes {
    let imageSize = NSSize(width: size, height: size)
    let image = NSImage(size: imageSize)

    image.lockFocus()

    // Brown/orange background circle (Homebrew-like color)
    let bgColor = NSColor(red: 0.85, green: 0.45, blue: 0.10, alpha: 1.0)
    bgColor.setFill()
    let bgPath = NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: size, height: size))
    bgPath.fill()

    // Draw SF Symbol centered
    let padding = Double(size) * 0.2
    let symbolRect = NSRect(x: padding, y: padding, width: Double(size) - padding * 2, height: Double(size) - padding * 2)
    let config = NSImage.SymbolConfiguration(pointSize: CGFloat(size) * 0.55, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        symbol.isTemplate = false
        // Tint white
        let tinted = NSImage(size: symbolRect.size)
        tinted.lockFocus()
        NSColor.white.setFill()
        let rect = NSRect(origin: .zero, size: symbolRect.size)
        symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSColor.white.setFill()
        rect.fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    image.unlockFocus()

    // Save as PNG
    if let tiffData = image.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiffData),
       let pngData = bitmap.representation(using: .png, properties: [:]) {
        let filename = size <= 512
            ? "\(iconsetPath)/icon_\(size)x\(size).png"
            : "\(iconsetPath)/icon_512x512@2x.png"
        try? pngData.write(to: URL(fileURLWithPath: filename))

        // Also write @2x for 32 and 256
        if size == 32 {
            try? pngData.write(to: URL(fileURLWithPath: "\(iconsetPath)/icon_16x16@2x.png"))
        } else if size == 64 {
            try? pngData.write(to: URL(fileURLWithPath: "\(iconsetPath)/icon_32x32@2x.png"))
        } else if size == 256 {
            try? pngData.write(to: URL(fileURLWithPath: "\(iconsetPath)/icon_128x128@2x.png"))
        } else if size == 512 {
            try? pngData.write(to: URL(fileURLWithPath: "\(iconsetPath)/icon_256x256@2x.png"))
        }
    }
}

print("Iconset generated!")
