import SwiftUI

struct SetChip: View {
    let index: Int
    let reps: String
    let load: String

    var body: some View {
        HStack(spacing: 6) {
            Text("S\(index + 1)")
                .fontWeight(.medium)
            Text(reps)
            Text(load)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.08), in: .capsule)
    }
}
