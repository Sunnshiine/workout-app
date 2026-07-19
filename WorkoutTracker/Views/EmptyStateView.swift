import SwiftUI

struct EmptyStateView: View {
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "dumbbell")
                .font(Theme.glyphFont(size: 48))
                .foregroundStyle(.secondary)
            Text("No session yet")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Automatic sync keeps checking your Sheet. Use Settings for manual recovery.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                onSettings()
            }
            .buttonStyle(.workoutGlass)
            .padding(.top, 4)
        }
        .padding(Theme.cardSpacing * 2)
        .workoutGlass(.card)
    }
}
