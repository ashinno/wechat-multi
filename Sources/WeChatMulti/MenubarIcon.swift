import Cocoa

/// Programmatically renders the monochrome menubar glyph from
/// `design/WeChat Multi Logo.html` (`IconStackMenubar`): three offset rounded
/// squares with progressive stroke opacity, plus a filled notification dot.
///
/// Two modes:
///   • `template()` — idle state, NSImage marked `.isTemplate = true` so
///     macOS auto-tints it for the active menubar appearance.
///   • `withRunningBadge()` — when an instance is running. Same glyph plus a
///     tiny jade dot in the top-right corner. NOT a template (the badge must
///     keep its color) — instead we draw the glyph in `NSColor.labelColor`
///     which adapts to the active appearance on its own.
enum MenubarIcon {

    static func template(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size),
                            flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawGlyph(in: ctx, size: size, color: .black, runningBadge: false)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "WeChat Multi"
        return image
    }

    static func withRunningBadge(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size),
                            flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // labelColor reflects the menubar's effective appearance at draw
            // time — white in dark menubars, black in light ones — so the
            // glyph remains legible without us being marked as a template.
            drawGlyph(in: ctx, size: size, color: NSColor.labelColor, runningBadge: true)
            return true
        }
        image.accessibilityDescription = "WeChat Multi — instances running"
        return image
    }

    // MARK: - Drawing

    private static func drawGlyph(in ctx: CGContext,
                                  size s: CGFloat,
                                  color base: NSColor,
                                  runningBadge: Bool) {
        let cardSide = s * 0.52
        let cardRadius = s * 0.13
        let strokeW = s * 0.07
        let cards: [(svgX: CGFloat, svgY: CGFloat, opacity: CGFloat)] = [
            (s * 0.06, s * 0.08, 0.45),
            (s * 0.18, s * 0.20, 0.70),
            (s * 0.30, s * 0.32, 1.00)
        ]

        ctx.setLineWidth(strokeW)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        for c in cards {
            let rect = CGRect(x: c.svgX,
                              y: s - c.svgY - cardSide,
                              width: cardSide, height: cardSide)
            let path = CGPath(roundedRect: rect.insetBy(dx: strokeW * 0.5, dy: strokeW * 0.5),
                              cornerWidth: cardRadius, cornerHeight: cardRadius,
                              transform: nil)
            ctx.setStrokeColor(base.withAlphaComponent(c.opacity).cgColor)
            ctx.addPath(path)
            ctx.strokePath()
        }

        // Notification badge at the top-right of the glyph. In template mode
        // it gets tinted with the rest of the icon; in running-badge mode we
        // override with jade so the running state pops.
        let badgeR = s * 0.10
        let badgeCX = s * 0.86
        let badgeCY = s - s * 0.18
        let badgeColor: NSColor = runningBadge
            ? NSColor(srgbRed: 0x07/255.0, green: 0xA0/255.0, blue: 0x50/255.0, alpha: 1.0)
            : base
        ctx.setFillColor(badgeColor.cgColor)
        ctx.fillEllipse(in: CGRect(x: badgeCX - badgeR, y: badgeCY - badgeR,
                                   width: badgeR * 2, height: badgeR * 2))

        // Subtle outer halo around the jade badge when running — sells the
        // "active" reading at 18pt without bumping the badge size.
        if runningBadge {
            ctx.setStrokeColor(badgeColor.withAlphaComponent(0.35).cgColor)
            ctx.setLineWidth(s * 0.04)
            ctx.strokeEllipse(in: CGRect(x: badgeCX - badgeR - s * 0.04,
                                         y: badgeCY - badgeR - s * 0.04,
                                         width: (badgeR + s * 0.04) * 2,
                                         height: (badgeR + s * 0.04) * 2))
        }
    }
}
