import SwiftUI

struct SyncStatusBanner: View {
    let outcome: SyncOutcome
    let isSyncing: Bool
    @Environment(\.themePalette) private var palette

    var body: some View {
        if let presentation = SyncStatusBannerPresentation(outcome: outcome, isSyncing: isSyncing) {
            banner(presentation)
        } else {
            EmptyView()
        }
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

/// Fades in over the banner's ground, which never fades, so nothing behind the banner shows
/// through while it arrives.
private struct SyncStatusBannerLabel: View {
    let text: String
    @State private var isShown = false

    var body: some View {
        Text(text)
            .lineLimit(2)
            .opacity(isShown ? 1 : 0)
            .animation(.easeOut(duration: 0.18), value: isShown)
            .onAppear { isShown = true }
    }
}
