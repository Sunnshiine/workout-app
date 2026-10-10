import SwiftUI

struct SyncStatusBanner: View {
    let outcome: SyncOutcome
    let isSyncing: Bool
    @Environment(\.themePalette) private var palette

    var body: some View {
        Group {
            if let presentation = SyncStatusBannerPresentation(outcome: outcome, isSyncing: isSyncing) {
                banner(presentation)
            }
        }
        // The banner can sit over other text, which would show through a ground caught mid-fade.
        .transaction { $0.animation = nil }
    }

    private func banner(_ presentation: SyncStatusBannerPresentation) -> some View {
        HStack(spacing: 8) {
            SyncStatusBannerLabel(text: presentation.text)
            Spacer(minLength: 0)
        }
        .font(Theme.font(.lastPerformed))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.bannerFill, in: Capsule())
        .background(palette.paper.baseTop, in: Capsule())
        .overlay(Capsule().strokeBorder(palette.bannerStroke, lineWidth: 0.5))
        .padding(.horizontal)
        // The explicit label replaces the combined children, so it is the whole of what VoiceOver
        // reads here.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}

/// Fades in over the banner's ground, which arrives without a fade.
private struct SyncStatusBannerLabel: View {
    let text: String
    @State private var isShown = false

    var body: some View {
        Text(text)
            .lineLimit(2)
            .opacity(isShown ? 1 : 0)
            .animation(.smooth(duration: 0.18), value: isShown)
            .onAppear { isShown = true }
    }
}
