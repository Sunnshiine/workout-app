import SwiftUI

struct EmptyStateView: View {
    let onSettings: () -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(spacing: 16) {
            Text("No Session yet")
                .themeFont(.sheetTitle)
            Text("Sessions appear here once your Sheet has one. The app keeps checking, and Settings can sync now.")
                .themeFont(.coachNote)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
            Button(action: onSettings) {
                Label("Open Settings", systemImage: "gearshape")
                    .labelStyle(.iconOnly)
                    .themeFont(.logCapsule)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .padding(Theme.cardSpacing * 2)
        .background(palette.surface, in: .rect(cornerRadius: Theme.Radius.card))
    }
}
