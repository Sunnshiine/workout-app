import SwiftUI

struct DangerMarkedText: View {
    @Environment(\.themePalette) private var palette

    let message: String
    let role: Theme.TypeRole

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(palette.danger)
                .accessibilityHidden(true)
            Text(message)
                .foregroundStyle(palette.textPrimary)
        }
        .font(Theme.font(role))
    }
}
