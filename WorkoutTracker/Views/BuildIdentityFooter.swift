import SwiftUI
import UIKit

/// A quiet, caption-sized line of build identity centered under the settings
/// card. Tapping copies the full multi-line identity to the clipboard and
/// briefly swaps the line for a "Copied" confirmation.
struct BuildIdentityFooter: View {
    let identity: BuildIdentity
    @State private var didCopy = false

    init(identity: BuildIdentity = .current) {
        self.identity = identity
    }

    var body: some View {
        Button(action: copy) {
            Text(didCopy ? "Copied" : identity.compactLine)
                .font(.caption2)
                .monospaced()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Copies the full build identity")
        .accessibilityIdentifier("settings-build-identity-footer")
    }

    private func copy() {
        UIPasteboard.general.string = identity.copyText
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            didCopy = false
        }
    }
}
