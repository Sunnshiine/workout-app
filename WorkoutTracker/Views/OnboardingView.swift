import GoogleSignInSwift
import SwiftUI

struct OnboardingView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var urlText = ""
    @State private var urlError = false
    @State private var showsURLFallback = false
    @Namespace private var ns

    var body: some View {
        GlassEffectContainer {
            if settings.isSignedIn {
                if showsURLFallback {
                    urlEntryCard
                } else {
                    SheetPickerView {
                        withAnimation { showsURLFallback = true }
                    }
                    .glassEffectID("onboarding", in: ns)
                }
            } else {
                signInCard
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Phase 1: Sign-In Card

    private var signInCard: some View {
        VStack(spacing: 20) {
            Text("Connect your training sheet")
                .font(.title2.bold())

            GoogleSignInButton {
                Task {
                    guard let vc = topViewController() else { return }
                    do {
                        try await GoogleAuth.signIn(presenting: vc)
                        withAnimation { settings.isSignedIn = true }
                    } catch { settings.isSignedIn = false }
                }
            }
            .frame(maxWidth: 280)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
        .glassEffectID("onboarding", in: ns)
    }

    // MARK: - Phase 2: URL Entry Card

    private var urlEntryCard: some View {
        VStack(spacing: 20) {
            Text("Paste your sheet URL")
                .font(.title2.bold())

            TextField("Google Sheet URL", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if urlError {
                Text("That doesn't look like a Sheet URL")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Save") { urlError = !settings.setSheetURL(urlText) }
                .buttonStyle(.glass)
                .disabled(urlText.isEmpty)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
        .glassEffectID("onboarding", in: ns)
    }
}

private struct SheetPickerView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var store: SheetPickerStore?

    let onPasteURL: () -> Void
    private let client: any SheetsClient
    private let relativeFormatter: RelativeDateTimeFormatter

    init(client: any SheetsClient = GoogleSheetsClient(), onPasteURL: @escaping () -> Void) {
        self.client = client
        self.onPasteURL = onPasteURL
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        self.relativeFormatter = formatter
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Choose your training sheet")
                .font(.title2.bold())

            content

            Button {
                store?.cancelSelection()
                onPasteURL()
            } label: {
                Text("Paste a URL instead")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
        }
        .padding()
        .frame(maxWidth: 520)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
        .task {
            guard store == nil else { return }
            let pickerStore = SheetPickerStore(client: client, settings: settings)
            store = pickerStore
            await pickerStore.loadInitial()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let store {
            if let message = store.listErrorMessage {
                VStack(spacing: 12) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.red)

                    Button("Retry") {
                        Task { await store.loadInitial() }
                    }
                    .buttonStyle(.glass)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.spreadsheets, id: \.spreadsheetId) { spreadsheet in
                            SheetPickerRow(
                                spreadsheet: spreadsheet,
                                modifiedText: relativeFormatter.localizedString(
                                    for: spreadsheet.modifiedDate,
                                    relativeTo: Date()
                                ),
                                errorMessage: store.rowError(for: spreadsheet),
                                isValidating: store.validatingSpreadsheetId == spreadsheet.spreadsheetId
                            ) {
                                store.select(spreadsheet)
                            }
                        }

                        if store.canLoadMore {
                            Button {
                                Task { await store.loadMore() }
                            } label: {
                                if store.isLoadingList {
                                    ProgressView()
                                } else {
                                    Text("Load More")
                                }
                            }
                            .buttonStyle(.glass)
                            .disabled(store.isLoadingList)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 420)
                .overlay {
                    if store.isLoadingList && store.spreadsheets.isEmpty {
                        ProgressView()
                    }
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 180)
        }
    }
}

private struct SheetPickerRow: View {
    let spreadsheet: SpreadsheetFile
    let modifiedText: String
    let errorMessage: String?
    let isValidating: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(spreadsheet.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(modifiedText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isValidating {
                        ProgressView()
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.pillFill, in: .rect(cornerRadius: Theme.pillCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.pillCornerRadius)
                    .stroke(Theme.pillStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isValidating)
    }
}

@MainActor
func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
    var top = scene?.keyWindow?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
}
