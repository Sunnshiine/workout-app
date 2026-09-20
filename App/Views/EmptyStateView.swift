import SwiftUI

struct EmptyStateView: View {
    let onSettings: () -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "dumbbell")
                .font(Theme.font(.ceremonyTitle))
                .foregroundStyle(.secondary)
            Text("No session yet")
                .font(Theme.font(.sheetTitle))
            Text("Automatic sync keeps checking your Sheet. Use Settings for manual recovery.")
                .font(Theme.font(.coachNote))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                onSettings()
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .padding(Theme.cardSpacing * 2)
        .background(palette.surface, in: .rect(cornerRadius: Theme.Radius.card))
    }
}
