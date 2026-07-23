import SwiftUI

struct OnboardingView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(SyncCoordinator.self) private var sync
    @Environment(WorkoutStore.self) private var workout
    @Environment(\.themePalette) private var palette
    @State private var urlText = ""
    @State private var urlError = false
    @State private var showsURLFallback = false
    @State private var switchStore: SettingsSheetSwitchStore?
    @State private var selectionErrorMessage: String?

    var body: some View {
        Group {
            switch destination {
            case .signIn:
                // The flat-calm connect screen renders full-bleed on living paper —
                // no glass card in the flow (DESIGN.md §5.8).
                connectScreen
            case .sheetPicker, .urlEntry, .session:
                VStack(spacing: 0) {
                    switch destination {
                    case .sheetPicker:
                        SheetPickerView(
                            client: GoogleSheetsClient.forCurrentEnvironment(),
                            onValidatedSelection: { spreadsheet in
                                await commitSelection(SheetSelection(spreadsheet))
                            },
                            onPasteURL: {
                                withAnimation { showsURLFallback = true }
                            }
                        )
                    case .urlEntry:
                        urlEntryCard
                    default:
                        EmptyView()
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear(perform: ensureSwitchStore)
        .alert("Couldn't load sheet", isPresented: selectionErrorPresented) {
            Button("OK", role: .cancel) { selectionErrorMessage = nil }
        } message: {
            Text(selectionErrorMessage ?? "Something went wrong.")
        }
    }

    private var destination: AppEntryDestination {
        AppEntryDestination(
            isSignedIn: settings.isSignedIn,
            hasSpreadsheet: settings.spreadsheetId != nil,
            showsURLFallback: showsURLFallback
        )
    }

    // MARK: - Phase 1: Connect screen (flat calm)

    private var connectScreen: some View {
        let copy = OnboardingConnectPresentation()
        return ZStack {
            palette.paperBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                ConnectPerch(width: 240)
                    .accessibilityHidden(true)

                Text(copy.title)
                    .font(Theme.font(.connectTitle))
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)
                    .accessibilityIdentifier("onboarding-title")

                Text(copy.subtitle)
                    .font(Theme.font(.coachNote))
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .padding(.top, 14)
                    .accessibilityIdentifier("onboarding-subtitle")

                Spacer(minLength: 24)

                // The quiet colophon sits above the ≥28pt floor (DESIGN.md §5.8),
                // near the foot of the composition.
                SunbirdColophon(diameter: 40)
                    .padding(.bottom, 28)

                Button(action: signIn) {
                    Text(copy.connectButtonTitle)
                        .font(Theme.font(.logCapsule))
                        .foregroundStyle(palette.actionText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(palette.action, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding-connect-button")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(palette.preferredColorScheme)
    }

    private func signIn() {
        Task {
            guard let vc = topViewController() else { return }
            do {
                try await GoogleAuth.signIn(presenting: vc)
                withAnimation { settings.isSignedIn = true }
            } catch { settings.isSignedIn = false }
        }
    }

    // MARK: - Phase 2: URL Entry Card

    private var urlEntryCard: some View {
        VStack(spacing: 20) {
            HStack {
                Button {
                    urlError = false
                    withAnimation { showsURLFallback = false }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("onboarding-url-back-button")

                Spacer()
            }

            Text("Paste your sheet URL")
                .font(Theme.font(.sheetTitle))

            TextField("Google Sheet URL", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if urlError {
                Text("That doesn't look like a Sheet URL")
                    .font(Theme.font(.historyChip))
                    .foregroundStyle(.red)
            }

            Button("Save") { saveURL() }
                .buttonStyle(.bordered)
                .disabled(urlText.isEmpty)
        }
        .padding()
        .background(palette.surface, in: .rect(cornerRadius: Theme.Radius.card))
    }

    // MARK: - Safe selection

    private var selectionErrorPresented: Binding<Bool> {
        Binding {
            selectionErrorMessage != nil
        } set: { isPresented in
            if !isPresented { selectionErrorMessage = nil }
        }
    }

    private func ensureSwitchStore() {
        guard switchStore == nil else { return }
        switchStore = SettingsSheetSwitchStore(settings: settings, sync: sync) {
            workout.reload()
        }
    }

    private func saveURL() {
        guard let id = extractSpreadsheetId(from: urlText) else {
            urlError = true
            return
        }
        urlError = false
        Task { await commitSelection(SheetSelection(spreadsheetId: id, title: nil)) }
    }

    /// Runs every onboarding selection through the same safe switch transaction as Settings:
    /// sync the newly selected sheet first, then commit the selection. A failed sync leaves the
    /// app on onboarding (no selection committed) rather than presenting a stale cached Block.
    private func commitSelection(_ selection: SheetSelection) async {
        ensureSwitchStore()
        guard let switchStore else { return }
        switch await switchStore.requestSwitch(to: selection) {
        case .switched, .unchanged:
            // Committing the selection flips `destination` away from the picker; nothing else to do.
            break
        case .failed:
            // The store sets a specific message for every failure path; the generic fallback only
            // guards the invariant that a `.failed` switch always surfaces an alert (matching the
            // alert body's own fallback), rather than restating the store's wording and drifting.
            selectionErrorMessage = switchStore.errorMessage ?? "Something went wrong."
        case .requiresConfirmation:
            // Onboarding starts with no committed sheet, so a prior sheet's unsynced writes shouldn't
            // normally reach here. Surface it rather than leaving the picker silently unresponsive;
            // the full discard-and-confirm flow for pending writes lives in Settings.
            selectionErrorMessage =
                "You have unsynced changes from a previous sheet. Review them in Settings before switching."
        }
    }
}

struct SheetPickerView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.themePalette) private var palette
    @State private var store: SheetPickerStore?

    let onPasteURL: (() -> Void)?
    private let client: any SheetsClient
    private let onValidatedSelection: ((SpreadsheetFile) async -> Void)?
    private let onDone: (() -> Void)?
    private let isSelectionDisabled: Bool
    private let relativeFormatter: RelativeDateTimeFormatter

    init(
        client: any SheetsClient = GoogleSheetsClient(),
        onValidatedSelection: ((SpreadsheetFile) async -> Void)? = nil,
        onPasteURL: (() -> Void)? = nil,
        onDone: (() -> Void)? = nil,
        isSelectionDisabled: Bool = false
    ) {
        self.client = client
        self.onValidatedSelection = onValidatedSelection
        self.onPasteURL = onPasteURL
        self.onDone = onDone
        self.isSelectionDisabled = isSelectionDisabled
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        self.relativeFormatter = formatter
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Choose your training sheet")
                .font(Theme.font(.sheetTitle))

            content

            if let onPasteURL {
                Button {
                    store?.cancelSelection()
                    onPasteURL()
                } label: {
                    Text("Paste a URL instead")
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.accent)
            }
        }
        .padding()
        .frame(maxWidth: 520)
        .background(palette.surface, in: .rect(cornerRadius: Theme.Radius.card))
        .task {
            guard store == nil else { return }
            let pickerStore = SheetPickerStore(
                client: client,
                settings: settings,
                onValidatedSelection: onValidatedSelection
            )
            store = pickerStore
            await pickerStore.loadInitial()
        }
        .toolbar {
            if let onDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store?.cancelSelection()
                        onDone()
                    }
                    .accessibilityIdentifier("sheet-picker-done-button")
                }
            }
        }
        .onDisappear {
            store?.cancelSelection()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let store {
            if let message = store.listErrorMessage {
                VStack(spacing: 12) {
                    Text(message)
                        .font(Theme.font(.queuePill))
                        .foregroundStyle(.red)

                    Button("Retry") {
                        Task { await store.loadInitial() }
                    }
                    .buttonStyle(.bordered)
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
                                isValidating: store.validatingSpreadsheetId == spreadsheet.spreadsheetId,
                                isDisabled: store.validatingSpreadsheetId != nil || isSelectionDisabled
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
                            .buttonStyle(.bordered)
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
    @Environment(\.themePalette) private var palette

    let spreadsheet: SpreadsheetFile
    let modifiedText: String
    let errorMessage: String?
    let isValidating: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(spreadsheet.name)
                            .font(Theme.font(.sheetTitle))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(modifiedText)
                            .font(Theme.font(.historyChip))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isValidating {
                        ProgressView()
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.font(.historyChip))
                        .foregroundStyle(.red)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.pillFill, in: .rect(cornerRadius: Theme.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .stroke(palette.pillStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

@MainActor
func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
    var top = scene?.keyWindow?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
}
