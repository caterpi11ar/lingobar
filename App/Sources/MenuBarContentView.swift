import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: LingobarAppModel
    let onOpenSettings: () -> Void
    let onQuit: () -> Void
    @State private var headerIcon: NSImage?
    private let contentWidth: CGFloat = 360
    private let maxPopoverHeight: CGFloat = 340
    private let maxScrollableContentHeight: CGFloat = 190

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    if let source = model.menuBarSourcePreview {
                        InfoCard(title: "剪贴板原文", content: source)
                            .accessibilityIdentifier("menu.sourcePreview")
                    }

                    if let translated = model.menuBarTranslatedPreview {
                        InfoCard(
                            title: model.translationRuntimeState.writeBackApplied ? "译文（已回写剪贴板）" : "译文",
                            content: translated,
                            emphasized: true
                        )
                        .accessibilityIdentifier("menu.translationPreview")
                    }

                    if let providerName = model.translationRuntimeState.providerName {
                        HStack(spacing: 8) {
                            Text("翻译服务")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(providerName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("menu.provider")
                        }
                        .padding(.horizontal, 2)
                    }
                }
                .padding(.trailing, 4)
            }
            .frame(maxHeight: maxScrollableContentHeight)

            Divider()
            HStack(spacing: 10) {
                Button(action: onOpenSettings) {
                    Label("打开设置", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .accessibilityIdentifier("menu.openSettings")

                Button(role: .destructive, action: onQuit) {
                    Label("退出", systemImage: "power")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .accessibilityIdentifier("menu.quit")
            }
        }
        .padding(16)
        .frame(width: contentWidth)
        .frame(maxHeight: maxPopoverHeight)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
        )
        .preferredColorScheme(model.preferredColorScheme)
        .task {
            guard headerIcon == nil else { return }
            MenuBarIconLoader.load(targetSize: NSSize(width: 18, height: 18)) { image in
                headerIcon = image
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusAccent.opacity(0.14))
                    .frame(width: 34, height: 34)
                if let headerIcon {
                    Image(nsImage: headerIcon)
                        .interpolation(.high)
                        .resizable()
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: model.menuBarSymbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(statusAccent)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(model.menuBarTitle)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(2)
                    .accessibilityIdentifier("menu.title")

                Text(model.translationRuntimeState.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityIdentifier("menu.preview")
            }

            Spacer(minLength: 0)

            if model.translationRuntimeState.phase.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 4)
                    .accessibilityIdentifier("menu.loading")
            }
        }
    }

    private var statusAccent: Color {
        switch model.translationRuntimeState.phase {
        case .idle:
            return .secondary
        case .debouncing:
            return .orange
        case .translating:
            return .blue
        case .succeeded:
            return .green
        case .failed:
            return .red
        }
    }
}

private struct InfoCard: View {
    let title: String
    let content: String
    var emphasized: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            Text(content)
                .font(emphasized ? .system(size: 14, weight: .medium) : .system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(emphasized ? 5 : 4)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }

    private var cardBackground: some ShapeStyle {
        emphasized ? AnyShapeStyle(Color.accentColor.opacity(0.08)) : AnyShapeStyle(Color.primary.opacity(0.035))
    }
}
