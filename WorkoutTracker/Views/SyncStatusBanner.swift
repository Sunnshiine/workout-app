import SwiftUI

struct SyncStatusBanner: View {
    let state: SyncCoordinator.State

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .syncing:
            banner(text: "Syncing", symbol: "arrow.triangle.2.circlepath")
        case .pendingWrites(let count):
            banner(text: "\(count) unsynced", symbol: "icloud.slash")
        case .offline:
            banner(text: "Offline", symbol: "wifi.slash")
        case .conflict(let messages):
            banner(text: messages.first ?? "Sheet conflict", symbol: "exclamationmark.triangle")
        }
    }

    private func banner(text: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .accessibilityHidden(true)
            Text(text)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sync status: \(text)")
    }
}
