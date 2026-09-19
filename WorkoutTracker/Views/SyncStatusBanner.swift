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
        // The banner drops its SF-symbol icon (ledger §10.3): the stage's icon budget is spent on the
        // branch. Sync / pending-write honesty is unchanged — it now speaks in words alone.
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.text)
                    .font(Theme.font(.lastPerformed))
                    .lineLimit(2)
                if let detail = presentation.detail {
                    Text(detail)
                        .font(Theme.font(.runlineSecondary))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.bannerFill, in: Capsule())
        .overlay(Capsule().strokeBorder(palette.bannerStroke, lineWidth: 0.5))
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}
