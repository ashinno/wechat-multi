import SwiftUI
import AppKit

/// Dedicated About window — opened from the popover's "About WeChat Multi"
/// footer item. Same "crafted Mac utility" aesthetic as Preferences: hero
/// app icon under a jade glow, version pill, link rows that hover-tint, and
/// a credits footer. Spring-physics entry animation on appear.
struct AboutView: View {
    @State private var hasMounted = false
    @State private var iconHovered = false

    private var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 38)

                appIcon
                    .scaleEffect(iconHovered ? 1.05 : 1)
                    .animation(Motion.entry, value: iconHovered)
                    .onHover { iconHovered = $0 }

                Spacer().frame(height: 16)

                Text("WeChat Multi")
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(-0.4)

                Spacer().frame(height: 8)

                versionPill

                Spacer().frame(height: 14)

                Text("Run multiple WeChat accounts\nside by side on your Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)

                Spacer().frame(height: 22)

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 0.5)
                    .padding(.horizontal, 56)

                Spacer().frame(height: 12)

                VStack(spacing: 1) {
                    AboutLink(icon: "link.circle.fill",
                              label: "GitHub Repository",
                              url: "https://github.com/ashinno/wechat-multi")
                    AboutLink(icon: "sparkles",
                              label: "What's New (Changelog)",
                              url: "https://github.com/ashinno/wechat-multi/releases")
                    AboutLink(icon: "doc.text.fill",
                              label: "License (MIT)",
                              url: "https://github.com/ashinno/wechat-multi/blob/main/LICENSE")
                    AboutLink(icon: "exclamationmark.bubble.fill",
                              label: "Report an Issue",
                              url: "https://github.com/ashinno/wechat-multi/issues/new")
                }
                .padding(.horizontal, 22)

                Spacer()

                VStack(spacing: 3) {
                    Text("Built with Swift & SwiftUI · Crafted for macOS")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    Text("© 2026 ashinno · MIT License")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text("WeChat is a trademark of Tencent. This project is unaffiliated.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(1)
                        .padding(.top, 2)
                }
                .padding(.bottom, 18)
                .padding(.horizontal, 20)
            }
            .opacity(hasMounted ? 1 : 0)
            .offset(y: hasMounted ? 0 : 8)
            .animation(.spring(response: 0.5, dampingFraction: 0.86), value: hasMounted)
        }
        .frame(width: 360, height: 560)
        .onAppear {
            DispatchQueue.main.async { hasMounted = true }
        }
    }

    // MARK: - Pieces

    private var versionPill: some View {
        HStack(spacing: 6) {
            Text("Version \(bundleVersion)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Brand.jadeDeep)
            Text("·")
                .foregroundStyle(Brand.jadeDeep.opacity(0.5))
            Text("build \(buildNumber)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Brand.jadeDeep.opacity(0.78))
        }
        .padding(.horizontal, 10).padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Brand.jade.opacity(0.16))
                .overlay(Capsule().strokeBorder(Brand.jade.opacity(0.18), lineWidth: 0.5))
        )
    }

    private var appIcon: some View {
        ZStack {
            // Soft jade halo behind the icon
            Circle()
                .fill(Brand.jade.opacity(0.30))
                .frame(width: 170, height: 170)
                .blur(radius: 38)
                .offset(y: 6)

            // The actual bundle icon (Stack/Jade), or fallback during dev runs
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 104, height: 104)
                    .shadow(color: Brand.jadeDeep.opacity(0.40), radius: 20, y: 12)
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.jade, Brand.jadeDeep],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 104, height: 104)
                    .shadow(color: Brand.jadeDeep.opacity(0.40), radius: 20, y: 12)
            }
        }
        .frame(height: 120)
    }

    private var backgroundGradient: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [Brand.jade.opacity(0.12), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
            RadialGradient(
                colors: [Brand.jade.opacity(0.20), Color.clear],
                center: .top,
                startRadius: 0,
                endRadius: 260
            )
        }
    }
}

// MARK: - Link row

private struct AboutLink: View {
    let icon: String
    let label: String
    let url: String

    @State private var hovered = false

    var body: some View {
        Button(action: openURL) { rowBody }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Motion.hover) { hovered = hovering }
        }
        .help("Open \(url) in your browser")
    }

    private var rowBody: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Brand.jade)
                .frame(width: 18, alignment: .center)
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .opacity(hovered ? 1 : 0.35)
                .offset(x: hovered ? 2 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hovered ? Brand.jade.opacity(0.12) : .clear)
        )
    }

    private func openURL() {
        guard let u = URL(string: url) else { return }
        NSWorkspace.shared.open(u)
    }
}
