// Generates the WeChat Multi app icon — a 2×2 grid of WeChat-style speech-bubble
// tiles on a soft white background. Renders directly with Core Graphics so the
// result is crisp at any resolution; outputs the 1024×1024 master PNG which we
// then downscale with `sips` to populate an .iconset for iconutil.
//
// Usage: swift tools/make_icon.swift <output.png>
import Cocoa

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/tmp/wechat-multi-icon-1024.png"

// MARK: - Colors

extension NSColor {
    static let wechatGreen = NSColor(srgbRed: 0.027, green: 0.757, blue: 0.376, alpha: 1.0)
    static let wechatGreenDark = NSColor(srgbRed: 0.020, green: 0.580, blue: 0.290, alpha: 1.0)
    static let bgTop = NSColor(srgbRed: 0.985, green: 0.992, blue: 0.985, alpha: 1.0)
    static let bgBottom = NSColor(srgbRed: 0.890, green: 0.940, blue: 0.890, alpha: 1.0)
}

// MARK: - Drawing primitives

func drawMiniWeChat(in ctx: CGContext, frame: CGRect) {
    let s = frame.width

    // Green rounded square (the "tile")
    let tilePath = CGPath(roundedRect: frame,
                          cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
    NSColor.wechatGreen.setFill()
    ctx.addPath(tilePath); ctx.fillPath()

    // Thin highlight along the top inside edge for a subtle glossy look.
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    let highlight = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [
                                NSColor(white: 1, alpha: 0.20).cgColor,
                                NSColor(white: 1, alpha: 0.00).cgColor
                               ] as CFArray,
                               locations: [0, 1])!
    ctx.drawLinearGradient(highlight,
                           start: CGPoint(x: frame.midX, y: frame.maxY),
                           end:   CGPoint(x: frame.midX, y: frame.midY),
                           options: [])
    ctx.restoreGState()

    // Big speech bubble — rounded rectangle, white, sitting in the upper-left
    // portion of the tile. Y increases upward (AppKit), so "upper" = larger y.
    let bigW = s * 0.62
    let bigH = s * 0.50
    let bigX = frame.minX + s * 0.10
    let bigY = frame.minY + s * 0.38  // upper-ish
    let bigRect = CGRect(x: bigX, y: bigY, width: bigW, height: bigH)
    let bigPath = CGPath(roundedRect: bigRect,
                         cornerWidth: bigH * 0.50, cornerHeight: bigH * 0.50,
                         transform: nil)
    NSColor.white.setFill()
    ctx.addPath(bigPath); ctx.fillPath()

    // Two "eye" dots inside the big bubble — the iconic WeChat motif.
    let eyeR = s * 0.050
    let eyeY = bigY + bigH * 0.50
    let eye1 = CGPoint(x: bigX + bigW * 0.32, y: eyeY)
    let eye2 = CGPoint(x: bigX + bigW * 0.68, y: eyeY)
    NSColor.wechatGreenDark.setFill()
    ctx.fillEllipse(in: CGRect(x: eye1.x - eyeR, y: eye1.y - eyeR, width: eyeR * 2, height: eyeR * 2))
    ctx.fillEllipse(in: CGRect(x: eye2.x - eyeR, y: eye2.y - eyeR, width: eyeR * 2, height: eyeR * 2))

    // Small secondary bubble — overlaps the lower-right of the big one,
    // referencing WeChat's two-bubble glyph.
    let smW = s * 0.34
    let smH = s * 0.27
    let smX = frame.minX + s * 0.52
    let smY = frame.minY + s * 0.17
    let smRect = CGRect(x: smX, y: smY, width: smW, height: smH)
    let smPath = CGPath(roundedRect: smRect,
                        cornerWidth: smH * 0.50, cornerHeight: smH * 0.50, transform: nil)
    NSColor.white.setFill()
    ctx.addPath(smPath); ctx.fillPath()

    // Tail on the small bubble pointing toward bottom-right corner.
    let tailPath = CGMutablePath()
    let tailBase = CGPoint(x: smRect.maxX - smW * 0.30, y: smRect.minY + smH * 0.10)
    let tailTip  = CGPoint(x: smRect.maxX - smW * 0.05, y: smRect.minY - smH * 0.18)
    let tailSide = CGPoint(x: smRect.maxX - smW * 0.50, y: smRect.minY + smH * 0.05)
    tailPath.move(to: tailBase)
    tailPath.addLine(to: tailTip)
    tailPath.addLine(to: tailSide)
    tailPath.closeSubpath()
    NSColor.white.setFill()
    ctx.addPath(tailPath); ctx.fillPath()
}

// MARK: - Compose icon

func makeIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    // Outer macOS-style rounded square — Big Sur+ standard ~22.5%.
    let outerRect = CGRect(x: 0, y: 0, width: size, height: size)
    let outerPath = CGPath(roundedRect: outerRect,
                           cornerWidth: size * 0.225, cornerHeight: size * 0.225,
                           transform: nil)

    ctx.saveGState()
    ctx.addPath(outerPath); ctx.clip()

    // Soft top-to-bottom green-tinted gradient.
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [NSColor.bgTop.cgColor, NSColor.bgBottom.cgColor] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg,
                           start: CGPoint(x: 0, y: size),
                           end:   CGPoint(x: 0, y: 0),
                           options: [])

    // 2×2 grid of mini WeChat tiles
    let outerPad = size * 0.085
    let gap = size * 0.035
    let tileSize = (size - outerPad * 2 - gap) / 2

    let cells: [CGPoint] = [
        // (x, y) — AppKit y is up
        CGPoint(x: outerPad,                       y: outerPad + tileSize + gap), // top-L
        CGPoint(x: outerPad + tileSize + gap,      y: outerPad + tileSize + gap), // top-R
        CGPoint(x: outerPad,                       y: outerPad),                  // bot-L
        CGPoint(x: outerPad + tileSize + gap,      y: outerPad)                   // bot-R
    ]
    for c in cells {
        drawMiniWeChat(in: ctx, frame: CGRect(x: c.x, y: c.y, width: tileSize, height: tileSize))
    }
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
