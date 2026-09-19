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
        // No icon: the stage's icon budget is spent on the branch (ledger §10.3). One line, because
        // the capsule tucks under the status bar and a second runs behind the Dynamic Island (#599),
        // which is why `presentation.detail` reaches the athlete through the label below and the
        // Settings `Sync now` row rather than the screen.
        HStack(spacing: 8) {
            Text(presentation.text)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .font(Theme.font(.lastPerformed))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.bannerFill, in: Capsule())
        .overlay(Capsule().strokeBorder(palette.bannerStroke, lineWidth: 0.5))
        .padding(.horizontal)
        // The explicit label replaces the combined children, so it is the whole of what VoiceOver
        // reads here.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}
