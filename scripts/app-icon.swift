// Renders the 1024x1024 app icon master.
// Usage: swift scripts/app-icon.swift <out.png>
import AppKit

let outPath = CommandLine.arguments[1]
let side: CGFloat = 1024

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = CGSize(width: side, height: side)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824pt rounded square centred in 1024, with a soft drop shadow
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.3)
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 28
shadow.set()
NSColor.black.setFill()
tilePath.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
tilePath.addClip()
NSGradient(colors: [
    NSColor(calibratedRed: 0.36, green: 0.27, blue: 0.86, alpha: 1),
    NSColor(calibratedRed: 0.62, green: 0.30, blue: 0.86, alpha: 1),
    NSColor(calibratedRed: 0.93, green: 0.40, blue: 0.62, alpha: 1),
])!.draw(in: tile, angle: -60)

// Subtle top sheen
NSGradient(colors: [
    NSColor(calibratedWhite: 1, alpha: 0.18),
    NSColor(calibratedWhite: 1, alpha: 0),
])!.draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)

// Floating lyric lines: dim, highlighted current line, dim
func pill(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ alpha: CGFloat) {
    NSColor(calibratedWhite: 1, alpha: alpha).setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: h / 2, yRadius: h / 2).fill()
}
pill(232, 560, 420, 44, 0.38)

NSGraphicsContext.saveGraphicsState()
let glow = NSShadow()
glow.shadowColor = NSColor(calibratedWhite: 1, alpha: 0.7)
glow.shadowBlurRadius = 30
glow.set()
pill(232, 440, 560, 72, 1.0)
NSGraphicsContext.restoreGraphicsState()

pill(232, 350, 340, 44, 0.38)
pill(232, 270, 230, 44, 0.22)

// Music note in the top-left
if let note = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
    .withSymbolConfiguration(.init(pointSize: 190, weight: .bold)) {
    let tinted = NSImage(size: note.size, flipped: false) { r in
        note.draw(in: r)
        NSColor.white.set()
        r.fill(using: .sourceAtop)
        return true
    }
    tinted.draw(in: NSRect(x: 218, y: 640, width: note.size.width, height: note.size.height))
}
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
