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
        HStack(spacing: 8) {
            Image(systemName: presentation.symbol)
                .accessibilityHidden(true)
            Text(presentation.text)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.bannerFill, in: Capsule())
        .overlay(Capsule().strokeBorder(palette.bannerStroke, lineWidth: 0.5))
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}
