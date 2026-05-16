// Generates the WeChat Multi app icon — the "Stack · Jade" design from
// design/WeChat Multi Logo.html.
//
//   • Background: macOS squircle (corner radius ≈ 22.5%), vertical jade gradient
//     #1FC56B → #07A050.
//   • Three offset rounded-square cards inside (50×50% of canvas, rx ≈ 10%),
//     each progressively more opaque (back 18%, mid 42%, front 100% white).
//   • Three jade-colored chat dots on the front card.
//   • Red notification badge (#FA3E3E) on the front card's top-right edge.
//
// Renders at 2048×2048 (via NSImage backing scale) so downscales for every
// icns size look crisp. Usage: swift tools/make_icon.swift <output.png>
import Cocoa

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/tmp/wechat-multi-icon-1024.png"

// MARK: - Jade palette (matches logo.jsx)

extension NSColor {
    static let jadeTop    = NSColor(srgbRed: 0x1F/255.0, green: 0xC5/255.0, blue: 0x6B/255.0, alpha: 1.0)
    static let jadeBottom = NSColor(srgbRed: 0x07/255.0, green: 0xA0/255.0, blue: 0x50/255.0, alpha: 1.0)
    static let jadeAccent = NSColor(srgbRed: 0xFA/255.0, green: 0x3E/255.0, blue: 0x3E/255.0, alpha: 1.0)
}

// MARK: - Draw

/// Mirror an SVG-coordinate rectangle (top-left origin) into AppKit's
/// bottom-left coordinate space.
func flipY(svgX: CGFloat, svgY: CGFloat, w: CGFloat, h: CGFloat,
           canvas size: CGFloat) -> CGRect {
    CGRect(x: svgX, y: size - svgY - h, width: w, height: h)
}

func makeIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    let bgRect = CGRect(x: 0, y: 0, width: size, height: size)
    let bgPath = CGPath(roundedRect: bgRect,
                        cornerWidth: size * 0.225,
                        cornerHeight: size * 0.225,
                        transform: nil)

    // Background: vertical jade gradient inside the squircle.
    ctx.saveGState()
    ctx.addPath(bgPath); ctx.clip()

    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [NSColor.jadeTop.cgColor,
                                       NSColor.jadeBottom.cgColor] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: size),  // top (Cocoa y=size)
                           end:   CGPoint(x: 0, y: 0),
                           options: [])

    // Three stacked cards: 50×50% of canvas, corner radius 10% of canvas.
    let cardW = size * 0.50
    let cardH = size * 0.50
    let cardR = size * 0.10
    let cards: [(svgX: CGFloat, svgY: CGFloat, opacity: CGFloat)] = [
        (size * 0.18, size * 0.20, 0.18),  // back
        (size * 0.26, size * 0.28, 0.42),  // mid
        (size * 0.34, size * 0.36, 1.00),  // front
    ]
    for c in cards {
        let rect = flipY(svgX: c.svgX, svgY: c.svgY, w: cardW, h: cardH, canvas: size)
        let path = CGPath(roundedRect: rect, cornerWidth: cardR, cornerHeight: cardR,
                          transform: nil)
        NSColor.white.withAlphaComponent(c.opacity).setFill()
        ctx.addPath(path); ctx.fillPath()
    }

    // Three chat dots on the front card. SVG cy = 0.60, r = 0.028, cx = 0.46/0.56/0.66.
    let dotR = size * 0.028
    let dotY = size - size * 0.60
    NSColor.jadeTop.setFill()
    for cxFrac in [0.46, 0.56, 0.66] as [CGFloat] {
        let cx = size * cxFrac
        ctx.fillEllipse(in: CGRect(x: cx - dotR, y: dotY - dotR,
                                   width: dotR * 2, height: dotR * 2))
    }

    // Red notification badge on the front card's top-right. SVG (0.82, 0.36), r = 0.07.
    let badgeR = size * 0.07
    let badgeCX = size * 0.82
    let badgeCY = size - size * 0.36
    NSColor.jadeAccent.setFill()
    ctx.fillEllipse(in: CGRect(x: badgeCX - badgeR, y: badgeCY - badgeR,
                               width: badgeR * 2, height: badgeR * 2))

    ctx.restoreGState()
    image.unlockFocus()
    return image
}

// MARK: - Save

let img = makeIcon(size: 1024)
guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to encode PNG")
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)  (\(png.count) bytes)")
