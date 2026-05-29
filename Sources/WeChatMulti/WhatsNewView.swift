import SwiftUI
import AppKit
import WeChatMultiCore

/// "What's new" panel — auto-shown on the first launch after the bundle
/// version bumps. Same brand language as About/Onboarding (jade-tinted
/// gradient + tracked uppercase section labels + spring entry).
struct WhatsNewView: View {
    /// Entries to display, newest-first. Pre-filtered by the caller.
    let entries: [Changelog.Entry]
    let onDismiss: () -> Void

    @State private var hasMounted = false

    private var primary: Changelog.Entry? { entries.first }
    private var older: [Changelog.Entry] { Array(entries.dropFirst()) }

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                topBar
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        if let primary {
                            primarySection(primary)
                        }
                        ForEach(older) { entry in
                            olderSection(entry)
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 16)
                }
                footer
            }
            .opacity(hasMounted ? 1 : 0)
            .offset(y: hasMounted ? 0 : 6)
            .animation(.spring(response: 0.5, dampingFraction: 0.86), value: hasMounted)
        }
        .frame(width: 460, height: 540)
        .onAppear {
            DispatchQueue.main.async { hasMounted = true }
        }
    }

    // MARK: - Sections

    private var topBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.jadeDeep)
            Text("WHAT'S NEW")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 30)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    private func primarySection(_ entry: Changelog.Entry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Version \(entry.version)")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Brand.jadeDeep)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Brand.jade.opacity(0.16)))
                Text(entry.highlight)
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(entry.bullets, id: \.self) { bullet in
                    bulletRow(bullet)
                }
            }
        }
    }

    private func olderSection(_ entry: Changelog.Entry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
                .padding(.bottom, 6)
            HStack(spacing: 8) {
                Text(entry.version)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(entry.highlight)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.85))
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(entry.bullets, id: \.self) { bullet in
                    bulletRow(bullet, dim: true)
                }
            }
        }
    }

    private func bulletRow(_ text: String, dim: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(dim ? Color.secondary : Brand.jade)
                .frame(width: 14)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(dim ? .secondary : .primary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)
            HStack {
                Link("Full release notes on GitHub →",
                     destination: URL(string: "https://github.com/ashinno/wechat-multi/releases")!)
                    .font(.system(size: 11))
                    .foregroundColor(Brand.jadeDeep)
                Spacer()
                Button(action: onDismiss) {
                    Text("Got it")
                }
                .buttonStyle(JadeButtonStyle())
                .keyboardShortcut(.defaultAction)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
        }
    }

    private var backgroundGradient: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [Brand.jade.opacity(0.10), Color.clear],
                startPoint: .topLeading,
                endPoint: .center
            )
            RadialGradient(
                colors: [Brand.jade.opacity(0.16), Color.clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 360
            )
        }
    }
}
