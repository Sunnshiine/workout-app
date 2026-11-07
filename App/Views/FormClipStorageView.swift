import SwiftUI

/// Settings' row for what Form Clips take on this phone.
struct FormClipStorageRow: View {
    @Environment(FormClipLibrary.self) private var library
    @Environment(WorkoutStore.self) private var workout
    @Environment(\.themePalette) private var palette

    var body: some View {
        let storage = FormClipStorage(library.clips, in: workout.block)
        NavigationLink {
            FormClipStorageList()
        } label: {
            LabeledContent {
                Text(storage.rows.isEmpty ? "None" : "\(storage.count) · \(storage.total)")
                    .foregroundStyle(palette.textSecondary)
            } label: {
                Text("Form Clips")
            }
        }
        .accessibilityIdentifier("settings-form-clips-row")
    }
}

/// Every clip on this phone, with what each takes. Settings stay native, so this is a plain list:
/// a row opens the review, and a row's own control deletes it.
struct FormClipStorageList: View {
    @Environment(FormClipLibrary.self) private var library
    @Environment(WorkoutStore.self) private var workout
    @Environment(\.themePalette) private var palette
    @State private var reviewing: ReviewedClip?
    @State private var deleting: FormClipStorage.Row?
    @State private var isDeleteFailed = false

    var body: some View {
        let storage = FormClipStorage(library.clips, in: workout.block)
        Form {
            if storage.rows.isEmpty {
                Section {
                    Text("No clips on this phone. Add one from a Logged Set's card.")
                        .foregroundStyle(palette.textSecondary)
                        .accessibilityIdentifier("form-clips-empty")
                }
                .listRowBackground(palette.surface)
            } else {
                Section {
                    ForEach(storage.rows) { row in
                        rowView(row)
                    }
                } footer: {
                    Text("\(storage.total) on this phone. Never uploaded and out of backups, so deleting one removes it for good.")
                        .foregroundStyle(palette.textSecondary)
                }
                .listRowBackground(palette.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background { palette.paperBackground.ignoresSafeArea() }
        .navigationTitle("Form Clips")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $reviewing) { clip in
            FormClipReviewView(clipID: clip.id, onAdd: nil) { reviewing = nil }
        }
        .formClipDeleteConfirmation(
            isPresented: Binding {
                deleting != nil
            } set: {
                if !$0 { deleting = nil }
            }
        ) {
            if let deleting { delete(deleting) }
        }
        .alert("Clip Not Deleted", isPresented: $isDeleteFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This clip couldn't be deleted. Try it again.")
        }
    }

    private func delete(_ row: FormClipStorage.Row) {
        do {
            try library.delete(row.id)
        } catch {
            isDeleteFailed = true
        }
    }

    private func rowView(_ row: FormClipStorage.Row) -> some View {
        HStack(spacing: 8) {
            Button {
                reviewing = ReviewedClip(id: row.id)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.rectangle")
                        .foregroundStyle(Color.blue)
                        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(row.name).foregroundStyle(palette.textPrimary)
                            Spacer(minLength: 0)
                            Text(row.size)
                                .foregroundStyle(palette.textSecondary)
                                .fixedSize()
                        }
                        Text(row.line)
                            .themeFont(.runlineSecondary)
                            .monospacedDigit()
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(Theme.TypeRole.runlineSecondary.denseFloorScale)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("form-clip-row")

            Button {
                deleting = row
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(row.name), \(row.line)")
            .accessibilityIdentifier("form-clip-row-delete")
        }
    }

    private struct ReviewedClip: Identifiable {
        let id: UUID
    }
}
