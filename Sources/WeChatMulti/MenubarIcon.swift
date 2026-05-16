import Cocoa

/// Programmatically renders the monochrome menubar glyph from
/// `design/WeChat Multi Logo.html` (`IconStackMenubar`): three offset rounded
/// squares with progressive stroke opacity, plus a filled notification dot.
///
/// Returned as a template image so macOS tints it correctly for the active
/// menubar appearance (white in dark mode, black in light mode).
enum MenubarIcon {
    static func template(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size),
                            flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: ctx, size: size)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "WeChat Multi"
        return image
    }

    private static func draw(in ctx: CGContext, size s: CGFloat) {
        // Layout matches IconStackMenubar in logo.jsx.
        let cardSide = s * 0.52
        let cardRadius = s * 0.13
        let strokeW = s * 0.07  // logo.jsx uses 0.06; we add a hair so the
                                // glyph reads at 16–22pt on dense menubars
                                // without the three cards merging into a blob
        let cards: [(svgX: CGFloat, svgY: CGFloat, opacity: CGFloat)] = [
            (s * 0.06, s * 0.08, 0.45),
            (s * 0.18, s * 0.20, 0.70),
            (s * 0.30, s * 0.32, 1.00)
        ]

        ctx.setLineWidth(strokeW)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        for c in cards {
            // Flip y from SVG (top-left origin) to AppKit (bottom-left origin).
            let rect = CGRect(x: c.svgX,
                              y: s - c.svgY - cardSide,
                              width: cardSide, height: cardSide)
            let path = CGPath(roundedRect: rect.insetBy(dx: strokeW * 0.5, dy: strokeW * 0.5),
                              cornerWidth: cardRadius, cornerHeight: cardRadius,
                              transform: nil)
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(c.opacity).cgColor)
            ctx.addPath(path)
            ctx.strokePath()
        }

        // Notification badge: filled disc at top-right.
        let badgeR = s * 0.10
        let badgeCX = s * 0.86
        let badgeCY = s - s * 0.18
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillEllipse(in: CGRect(x: badgeCX - badgeR, y: badgeCY - badgeR,
                                   width: badgeR * 2, height: badgeR * 2))
    }
}
