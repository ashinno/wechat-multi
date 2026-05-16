import SwiftUI

/// Shared design tokens — colors, typography, motion — used by the popover
/// and the Preferences window so both surfaces feel like one app.
///
/// The aesthetic direction is "crafted Mac utility" (Linear / Things 3 / Tot
/// territory): restrained native-feeling layout with the jade brand color
/// surfacing in the moments where it matters — toggles, links, active state,
/// success indicators — instead of flooding every surface with green.
enum Brand {
    // MARK: - Color

    /// Primary brand jade (lighter top of the icon gradient).
    static let jade       = Color(red: 0x1F/255, green: 0xC5/255, blue: 0x6B/255)
    /// Darker brand jade (bottom of the icon gradient). Used for hover-deep
    /// states and the wordmark in the design's wordmark lockup.
    static let jadeDeep   = Color(red: 0x07/255, green: 0xA0/255, blue: 0x50/255)
    /// Highlight tint for active rows — semantically "this is selected".
    static let jadeTint   = Color(red: 0x1F/255, green: 0xC5/255, blue: 0x6B/255).opacity(0.14)
    /// Stronger hover tint for buttons that aren't account rows.
    static let hoverTint  = Color.primary.opacity(0.06)
    /// Accent red from the design's notification badge — used only for
    /// destructive actions and overdue warnings.
    static let badgeRed   = Color(red: 0xFA/255, green: 0x3E/255, blue: 0x3E/255)
}

/// Motion constants — keep durations tight so the UI feels responsive, not
/// floaty. Mac users expect 120–200ms transitions.
enum Motion {
    static let hover  = Animation.easeOut(duration: 0.14)
    static let state  = Animation.easeInOut(duration: 0.22)
    static let entry  = Animation.spring(response: 0.42, dampingFraction: 0.86)
}

/// Reusable section header — the tracked uppercase label that visually
/// separates groups of settings. Cheap typography trick that signals
/// "this is a crafted utility, not a quick form."
struct SectionLabel: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 10.5, weight: .semibold, design: .default))
            .tracking(0.9)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

/// Card container — subtle elevation behind a group of related rows.
/// Adapts to light/dark via NSColor.controlBackgroundColor.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}

/// Themed primary button — jade fill with a darker pressed state. Used for
/// the rare "main action" inside Preferences (currently unused but available).
struct JadeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? Brand.jadeDeep : Brand.jade)
            )
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}
