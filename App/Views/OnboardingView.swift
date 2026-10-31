import SwiftUI

struct OnboardingView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(SheetConnection.self) private var connection
    @Environment(\.themePalette) private var palette
    @State private var urlText = ""
    @FocusState private var urlFieldFocused: Bool
    @State private var urlError = false
    @State private var showsURLFallback = false
    @State private var selectionErrorMessage: String?
    @State private var signInErrorMessage: String?

    // A value, not a SettingsStore read. While a removed view fades out, SwiftUI keeps the last
    // value its parent built, so signing in with a sheet still stored fades the connect screen
    // out instead of swapping it for the sheet picker mid-fade.
    let isSignedIn: Bool

    var body: some View {
        Group {
            switch step {
            case .signIn:
                // The flat-calm connect screen renders full-bleed on living paper —
                // no glass card in the flow (DESIGN.md §5.8).
                connectScreen
            case .sheetPicker, .urlEntry:
                VStack(spacing: 0) {
                    if step == .sheetPicker {
                        SheetPickerView(
                            client: GoogleSheetsClient.forCurrentEnvironment(),
                            onValidatedSelection: { spreadsheet in
                                await commitSelection(SheetSelection(spreadsheet))
                            },
                            onPasteURL: {
                                withAnimation { showsURLFallback = true }
                            }
                        )
                    } else {
                        urlEntryCard
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert("Couldn't load sheet", isPresented: selectionErrorPresented) {
            Button("OK", role: .cancel) { selectionErrorMessage = nil }
        } message: {
            Text(selectionErrorMessage ?? "")
        }
        .alert("Couldn't sign in", isPresented: signInErrorPresented) {
            Button("OK", role: .cancel) { signInErrorMessage = nil }
        } message: {
            Text(signInErrorMessage ?? "")
        }
    }

    private var step: OnboardingStep {
        OnboardingStep(isSignedIn: isSignedIn, showsURLFallback: showsURLFallback)
    }

    // MARK: - Phase 1: Connect screen (flat calm)

    private var connectScreen: some View {
        ZStack {
            palette.paperBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                ConnectPerch(width: 240)
                    .accessibilityHidden(true)

                Text("Plant the program.")
                    .font(Theme.font(.connectTitle))
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)
                    .accessibilityIdentifier("onboarding-title")

                Text("Connect the Sheet your coach programs. The app keeps it fresh and carries your logs back.")
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
                    Text("Connect Google Sheet")
                        .font(Theme.font(.logCapsule))
                        .foregroundStyle(palette.actionText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(palette.actionFill, in: .capsule)
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
            switch await GoogleAuth.signIn(presenting: vc) {
            case .signedIn:
                withAnimation { settings.isSignedIn = true }
            case .canceled:
                settings.isSignedIn = false
            case .failed:
                settings.isSignedIn = false
                signInErrorMessage = "Google sign-in didn't finish. Check your connection, then try again."
            }
        }
    }

    // MARK: - Phase 2: URL Entry Card

    private var urlEntryCard: some View {
        // A SwiftUI TextField publishes its placeholder as the accessibility value while it is
        // empty and only promotes it to a label once the athlete types, so an empty field has no
        // accessible name at all. Naming it explicitly gives it the same name in both states.
        let fieldName = "Google Sheet URL"
        return VStack(spacing: 20) {
            HStack {
                BorderedCircleIconButton(label: "Back", systemImage: "chevron.left") {
                    urlError = false
                    withAnimation { showsURLFallback = false }
                }
                .accessibilityIdentifier("onboarding-url-back-button")

                Spacer()
            }

            Text("Paste your sheet URL")
                .font(Theme.font(.sheetTitle))

            TextField(
                fieldName,
                text: $urlText,
                prompt: Text(fieldName).foregroundStyle(palette.textSecondary)
            )
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .textContentType(.URL)
            .submitLabel(.go)
            .onSubmit { if connection.canSaveSheetURL(urlText) { saveURL() } }
            .focused($urlFieldFocused)
            .accessibilityIdentifier("onboarding-url-field")
            .accessibilityLabel(fieldName)
            .onChange(of: urlText) { urlError = false }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(palette.pillFill, in: .capsule)
            .overlay { Capsule().strokeBorder(palette.pillStroke, lineWidth: 1) }
            .contentShape(Capsule())
            .onTapGesture { urlFieldFocused = true }

            if urlError {
                DangerMarkedText(message: "That doesn't look like a Sheet URL", role: .historyChip)
            }

            Button("Save") { saveURL() }
                .buttonStyle(.bordered)
                .disabled(!connection.canSaveSheetURL(urlText))
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

    private var signInErrorPresented: Binding<Bool> {
        Binding {
            signInErrorMessage != nil
        } set: { isPresented in
            if !isPresented { signInErrorMessage = nil }
        }
    }

    private func saveURL() {
        guard let id = extractSpreadsheetId(from: urlText) else {
            urlError = true
            return
        }
        Task { await commitSelection(SheetSelection(spreadsheetId: id, title: nil)) }
    }

    private func commitSelection(_ selection: SheetSelection) async {
        selectionErrorMessage = await connection.requestSwitch(to: selection).onboardingMessage
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
                .foregroundStyle(palette.actionInk)
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
                    DangerMarkedText(message: message, role: .queuePill)

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
                            .font(Theme.font(.heading))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(modifiedText)
                            .font(Theme.font(.historyChip))
                            .foregroundStyle(palette.textSecondary)
                    }

                    Spacer()

                    if isValidating {
                        ProgressView()
                    }
                }

                if let errorMessage {
                    DangerMarkedText(message: errorMessage, role: .historyChip)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.pillFill, in: .rect(cornerRadius: Theme.Radius.card))
            .themeElevation(palette.lighting.raisedControlShadow, in: .rect(cornerRadius: Theme.Radius.card))
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
