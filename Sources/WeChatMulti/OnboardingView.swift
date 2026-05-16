import SwiftUI
import AppKit

/// First-run onboarding — three panels that orient the user before they have
/// to figure the app out on their own:
///
///   1. **Concept** — what WeChat Multi is and why it exists
///   2. **Location** — where the menu bar icon lives (with a pulsing callout)
///   3. **Ready** — a stylized mini-popover preview highlighting "Add account…"
///
/// Replaces the bare NSAlert that v1.0 shipped with. Page transitions slide
/// horizontally with spring physics; the jade brand color carries through
/// indicators, the highlighted icon, and the primary action button.
struct OnboardingView: View {
    let onDismiss: () -> Void

    @State private var page: Int = 0

    private let panels: [OnboardingPanel] = [
        OnboardingPanel(
            title: "Run multiple WeChat accounts side by side",
            body: "Mac WeChat only lets one account run at a time. WeChat Multi creates isolated copies — each with its own sandbox and login — so you can sign in to as many accounts as you need.",
            illustration: .concept
        ),
        OnboardingPanel(
            title: "Look for the icon in your menu bar",
            body: "The stacked-cards icon lives next to your clock. Click it to manage accounts. Right-click any row inside the popover for advanced actions like rename and quit.",
            illustration: .location
        ),
        OnboardingPanel(
            title: "Ready when you are",
            body: "Click “Add account…” in the popover to launch your first instance. The first time you launch each slot, macOS may show a security prompt — that’s normal, we use ad-hoc signing.",
            illustration: .ready
        )
    ]

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                ZStack {
                    ForEach(panels.indices, id: \.self) { idx in
                        if idx == page {
                            PanelBody(panel: panels[idx])
                                .transition(transition(for: idx))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                Spacer().frame(height: 8)
                indicators
                Spacer().frame(height: 16)
                actions
                    .padding(.horizontal, 30)
                    .padding(.bottom, 22)
            }
        }
        .frame(width: 600, height: 480)
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack {
            Spacer()
            if page < panels.count - 1 {
                Button("Skip") { onDismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .frame(height: 36)
    }

    private var indicators: some View {
        HStack(spacing: 8) {
            ForEach(panels.indices, id: \.self) { idx in
                Capsule()
                    .fill(idx == page ? Brand.jadeDeep : Color.secondary.opacity(0.30))
                    .frame(width: idx == page ? 18 : 6, height: 6)
                    .animation(Motion.state, value: page)
                    .onTapGesture {
                        withAnimation(Motion.entry) { page = idx }
                    }
            }
        }
    }

    private var actions: some View {
        HStack {
            if page > 0 {
                Button("Back") {
                    withAnimation(Motion.entry) { page -= 1 }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .keyboardShortcut(.leftArrow, modifiers: [])
            }
            Spacer()
            Button(action: advance) {
                Text(page < panels.count - 1 ? "Continue" : "Get Started")
            }
            .buttonStyle(JadeButtonStyle())
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .keyboardShortcut(.rightArrow, modifiers: [])
        }
    }

    private func advance() {
        if page < panels.count - 1 {
            withAnimation(Motion.entry) { page += 1 }
        } else {
            onDismiss()
        }
    }

    private func transition(for index: Int) -> AnyTransition {
        // Slide-from-right on forward navigation, slide-from-left on back.
        // Pure SwiftUI transitions; no manual offset math.
        .asymmetric(
            insertion: .move(edge: index >= page ? .trailing : .leading)
                .combined(with: .opacity),
            removal: .move(edge: index >= page ? .leading : .trailing)
                .combined(with: .opacity)
        )
    }

    private var backgroundGradient: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [Brand.jade.opacity(0.10), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Brand.jade.opacity(0.16), Color.clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 420
            )
        }
    }
}

// MARK: - Panel model + body

private struct OnboardingPanel {
    enum Illustration {
        case concept, location, ready
    }
    let title: String
    let body: String
    let illustration: Illustration
}

private struct PanelBody: View {
    let panel: OnboardingPanel

    var body: some View {
        VStack(spacing: 0) {
            illustration
                .frame(height: 220)
            Spacer().frame(height: 26)
            Text(panel.title)
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
                .fixedSize(horizontal: false, vertical: true)
            Spacer().frame(height: 12)
            Text(panel.body)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 60)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private var illustration: some View {
        switch panel.illustration {
        case .concept:  ConceptIllustration()
        case .location: LocationIllustration()
        case .ready:    ReadyIllustration()
        }
    }
}

// MARK: - Illustrations

private struct ConceptIllustration: View {
    var body: some View {
        ZStack {
            // Soft jade glow behind the icon, telegraphs brand
            Circle()
                .fill(Brand.jade.opacity(0.22))
                .frame(width: 260, height: 260)
                .blur(radius: 50)
                .offset(y: -6)

            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 132, height: 132)
                    .shadow(color: Brand.jadeDeep.opacity(0.45), radius: 24, y: 14)
            } else {
                // Fallback if the bundle icon isn't accessible (dev runs)
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.jade, Brand.jadeDeep],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 132, height: 132)
                    .shadow(color: Brand.jadeDeep.opacity(0.45), radius: 24, y: 14)
            }
        }
    }
}

private struct LocationIllustration: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 14) {
            // A stylized slice of the menu bar
            HStack(spacing: 14) {
                Spacer(minLength: 0)
                // Generic system icons (faded circles + rectangles)
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill(Color.secondary.opacity(0.30))
                        .frame(width: 16, height: 8)
                }
                Circle()
                    .fill(Color.secondary.opacity(0.30))
                    .frame(width: 10, height: 10)

                // Our icon — highlighted with an animated jade ring
                ZStack {
                    Circle()
                        .stroke(Brand.jade.opacity(pulse ? 0 : 0.7), lineWidth: 1.5)
                        .frame(width: pulse ? 38 : 22, height: pulse ? 38 : 22)
                        .animation(.easeOut(duration: 1.4)
                                    .repeatForever(autoreverses: false),
                                  value: pulse)
                    Image(nsImage: MenubarIcon.template(size: 18))
                        .renderingMode(.template)
                        .foregroundStyle(Brand.jadeDeep)
                        .frame(width: 18, height: 18)
                }

                // Clock-like time placeholder
                Text("10:42")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
            .padding(.horizontal, 60)

            // Arrow + label below the icon
            VStack(spacing: 4) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Brand.jadeDeep)
                Text("Here")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Brand.jadeDeep)
            }
        }
        .onAppear { pulse = true }
    }
}

private struct ReadyIllustration: View {
    var body: some View {
        // Stylized popover preview — abbreviated copy of the real popover so
        // the user recognizes it when they actually click.
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(nsImage: MenubarIcon.template(size: 14))
                    .renderingMode(.template)
                    .foregroundStyle(.primary)
                    .frame(width: 14, height: 14)
                Text("WeChat Multi")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("0 accounts")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Brand.jadeDeep)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Brand.jade.opacity(0.16)))
            }
            .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 7)

            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)

            // Empty state
            HStack {
                Spacer()
                Text("No accounts yet")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 18)

            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)

            // Footer with Add account… highlighted
            VStack(spacing: 2) {
                HStack(spacing: 7) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Brand.jade)
                    Text("Add account…")
                        .font(.system(size: 10.5))
                    Spacer()
                    Text("⌘N")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Brand.jade.opacity(0.22),
                                         Brand.jade.opacity(0.12)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Brand.jade.opacity(0.30), lineWidth: 0.5)
                        )
                )
                .padding(.horizontal, 3)

                HStack(spacing: 7) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Text("Preferences…")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.primary.opacity(0.7))
                    Spacer()
                }
                .padding(.horizontal, 7).padding(.vertical, 4)
                .padding(.horizontal, 3)

                HStack(spacing: 7) {
                    Image(systemName: "power")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Text("Quit WeChat Multi")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.primary.opacity(0.7))
                    Spacer()
                    Text("⌘Q")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 7).padding(.vertical, 4)
                .padding(.horizontal, 3)
            }
            .padding(.vertical, 3)
        }
        .frame(width: 220)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 22, y: 14)
        // Tiny floating speech-bubble pointing at the popover
        .overlay(alignment: .topTrailing) {
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 28))
                .foregroundStyle(Brand.jadeDeep)
                .rotationEffect(.degrees(15))
                .offset(x: 26, y: 22)
                .shadow(color: Brand.jadeDeep.opacity(0.25), radius: 6, y: 3)
        }
    }
}
