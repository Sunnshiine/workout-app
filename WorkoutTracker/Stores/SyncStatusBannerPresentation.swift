import Foundation

struct SyncStatusBannerPresentation: Equatable, Sendable {
    let text: String
    let symbol: String
    let accessibilityLabel: String

    init(text: String, symbol: String, accessibilityLabel: String) {
        self.text = text
        self.symbol = symbol
        self.accessibilityLabel = accessibilityLabel
    }

    init?(state: SyncCoordinator.State) {
        let text: String
        let symbol: String
        switch state {
        case .idle:
            return nil
        case .syncing:
            text = "Syncing"
            symbol = "arrow.triangle.2.circlepath"
        case .pendingWrites(let count):
            text = "\(count) unsynced"
            symbol = "icloud.slash"
        case .offline:
            text = "Offline"
            symbol = "wifi.slash"
        case .conflict(let messages):
            text = messages.first ?? "Sheet conflict"
            symbol = "exclamationmark.triangle"
        }

        self.init(
            text: text,
            symbol: symbol,
            accessibilityLabel: "Sync status: \(text)"
        )
    }
}
