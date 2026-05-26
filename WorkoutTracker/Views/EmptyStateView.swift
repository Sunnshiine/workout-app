import SwiftUI

struct EmptyStateView: View {
    let onSync: () async -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "dumbbell")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No session yet")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Pull to refresh to sync your sheet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Sync") {
                Task { await onSync() }
            }
            .buttonStyle(.glass)
            .padding(.top, 4)
        }
        .padding(Theme.cardSpacing * 2)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
    }
}
