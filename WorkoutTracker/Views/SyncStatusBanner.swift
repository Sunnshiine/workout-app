import SwiftUI

struct SyncStatusBanner: View {
    let state: SyncCoordinator.State
    @Environment(\.themePalette) private var palette

    var body: some View {
        if let presentation = SyncStatusBannerPresentation(state: state) {
            banner(presentation)
        } else {
            EmptyView()
        }
    }

    private func banner(_ presentation: SyncStatusBannerPresentation) -> some View {
        // Greenhouse restyle: sync state reads honestly in the room's own voice — a calm capsule on
        // the soft surface, direct tabular type (The Numbers Stay Plain Rule) so an "N unsynced" count
        // never implies a Set Log landed when it hasn't. Behavior is unchanged; only the skin re-lights.
        HStack(spacing: 8) {
            Image(systemName: presentation.symbol)
                .foregroundStyle(palette.textSecondary)
                .accessibilityHidden(true)
            Text(presentation.text)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .font(Theme.font(.runline))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(palette.queueStroke, lineWidth: 0.5))
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}
