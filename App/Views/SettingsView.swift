import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(SheetConnection.self) private var connection
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var isSheetPickerPresented = false
    @State private var isSignOutConfirmationPresented = false
    @State private var pendingSwitch: SheetSelection?
    @State private var settingsError: DestructiveTransitionFailure?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Appearance", selection: appearanceSelection) {
                        ForEach(AppearancePreference.allCases, id: \.self) { appearance in
                            Text(appearance.label).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings-appearance-picker")
                } header: {
                    Text("Appearance").foregroundStyle(palette.textSecondary)
                }
                .listRowBackground(palette.surface)

                Section {
                    Stepper(value: standardRestSeconds, in: restRange, step: RestDurationSetting.stepSeconds) {
                        LabeledContent {
                            RowValue(text: settings.standardRestDuration.displayText)
                        } label: {
                            Text("Standard")
                        }
                    }
                    .accessibilityIdentifier("settings-standard-rest-stepper")

                    Stepper(value: supersetRestSeconds, in: restRange, step: RestDurationSetting.stepSeconds) {
                        LabeledContent {
                            RowValue(text: settings.supersetRestDuration.displayText)
                        } label: {
                            Text("Superset rest")
                        }
                    }
                    .accessibilityIdentifier("settings-superset-rest-stepper")
                } header: {
                    Text("Rest").foregroundStyle(palette.textSecondary)
                }
                .labeledContentStyle(StackedAtAccessibilitySizes())
                .listRowBackground(palette.surface)

                Section {
                    Button {
                        isSheetPickerPresented = true
                    } label: {
                        LabeledContent {
                            RowValue(text: sheetDisplayName)
                        } label: {
                            RowLabel(title: "Training Sheet")
                        }
                    }
                    .disabled(isSheetBusy)
                    .accessibilityIdentifier("settings-training-sheet-row")

                    Button {
                        Task { await connection.syncNow() }
                    } label: {
                        LabeledContent {
                            RowValue(text: connection.syncNowDetail)
                        } label: {
                            RowLabel(title: "Sync now")
                        }
                    }
                    .disabled(!connection.canSyncNow)
                    .accessibilityIdentifier("settings-sync-now-button")
                    .accessibilityValue(connection.syncNowDetail)

                    NavigationLink {
                        DeveloperToolsView()
                    } label: {
                        Text("Developer Tools")
                    }
                    .accessibilityIdentifier("settings-developer-tools-row")
                }
                .listRowBackground(palette.surface)

                Section {
                    Button(role: .destructive) {
                        requestSignOut()
                    } label: {
                        Text("Sign Out")
                    }
                    .disabled(isSheetBusy)
                    .accessibilityIdentifier("settings-sign-out-button")
                }
                .listRowBackground(palette.surface)

                Section {
                    BuildIdentityFooter()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.paperBackground.ignoresSafeArea())
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("settings-done-button")
                }
            }
        }
        .sheet(isPresented: $isSheetPickerPresented) {
            sheetPickerSheet
        }
        .alert(
            "You have unsynced changes. Sign out anyway?",
            isPresented: $isSignOutConfirmationPresented
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                Task { await signOutNow() }
            }
        } message: {
            Text("Pending logs for the current sheet will be discarded.")
        }
        .alert("Settings Error", isPresented: settingsErrorPresented, presenting: settingsError) { _ in
            Button("OK", role: .cancel) {}
        } message: { failure in
            Text(failure.message)
        }
        .preferredColorScheme(Theme.colorSchemeOverride(for: settings.appearance))
        .toolbarColorScheme(Theme.colorSchemeOverride(for: settings.appearance), for: .navigationBar)
    }

    private var sheetDisplayName: String {
        settings.spreadsheetTitle ?? "Google Sheet"
    }

    private var appearanceSelection: Binding<AppearancePreference> {
        Binding {
            settings.appearance
        } set: { preference in
            settings.setAppearance(preference)
        }
    }

    private var restRange: ClosedRange<Int> {
        RestDurationSetting.minimumSeconds...RestDurationSetting.maximumSeconds
    }

    private var standardRestSeconds: Binding<Int> {
        Binding {
            settings.standardRestDuration.seconds
        } set: { seconds in
            settings.setStandardRestDuration(RestDurationSetting(seconds: seconds))
        }
    }

    private var supersetRestSeconds: Binding<Int> {
        Binding {
            settings.supersetRestDuration.seconds
        } set: { seconds in
            settings.setSupersetRestDuration(RestDurationSetting(seconds: seconds))
        }
    }

    private var isSheetBusy: Bool {
        !connection.canBeginDestructiveTransition
    }

    private func requestSignOut() {
        switch connection.requestSignOut() {
        case .requiresConfirmation:
            isSignOutConfirmationPresented = true
        case .ready:
            Task { await signOutNow() }
        case .failed(let failure):
            settingsError = failure
        }
    }

    private func signOutNow() async {
        do throws(DestructiveTransitionFailure) {
            try await connection.signOut()
            GoogleAuth.signOut()
            dismiss()
        } catch {
            settingsError = error
        }
    }

    private func requestSwitch(to spreadsheet: SpreadsheetFile) async {
        switch await connection.requestSwitch(to: spreadsheet) {
        case .switched, .unchanged:
            isSheetPickerPresented = false
        case .requiresConfirmation(let selection):
            pendingSwitch = selection
        case .failed(let failure):
            settingsError = failure
        }
    }

    private func confirmSwitch(to selection: SheetSelection) async {
        do throws(DestructiveTransitionFailure) {
            try await connection.confirmSwitch(to: selection)
            isSheetPickerPresented = false
        } catch {
            settingsError = error
        }
    }

    private var sheetPickerSheet: some View {
        NavigationStack {
            SheetPickerView(
                client: GoogleSheetsClient.forCurrentEnvironment(),
                onValidatedSelection: { spreadsheet in
                    await requestSwitch(to: spreadsheet)
                },
                onDone: {
                    isSheetPickerPresented = false
                },
                isSelectionDisabled: isSheetBusy
            )
            .background(palette.gradient.ignoresSafeArea())
            .navigationTitle("Training Sheet")
        }
        .alert(
            "You have unsynced changes. Switch anyway?",
            isPresented: pendingSwitchConfirmation,
            presenting: pendingSwitch
        ) { selection in
            Button("Cancel", role: .cancel) {}
            Button("Switch Anyway", role: .destructive) {
                Task { await confirmSwitch(to: selection) }
            }
        } message: { _ in
            Text("Pending logs for the current sheet will be discarded.")
        }
    }

    private var pendingSwitchConfirmation: Binding<Bool> {
        Binding {
            pendingSwitch != nil
        } set: { isPresented in
            if !isPresented {
                pendingSwitch = nil
            }
        }
    }

    private var settingsErrorPresented: Binding<Bool> {
        Binding {
            settingsError != nil
        } set: { isPresented in
            if !isPresented {
                settingsError = nil
            }
        }
    }
}

/// System blue, named rather than read from the tint, so an app accent colour cannot repaint the
/// row. A Button whose label is a LabeledContent draws that label in the primary colour once
/// disabled, where it would read as tappable, so the label dims itself.
private struct RowLabel: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String

    var body: some View {
        Text(title).foregroundStyle(isEnabled ? Color.blue : inactiveRowInk)
    }
}

private struct RowValue: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.themePalette) private var palette
    let text: String

    var body: some View {
        Text(text).foregroundStyle(isEnabled ? palette.textSecondary : inactiveRowInk)
    }
}

// WCAG 1.4.3 exempts an inactive control from contrast.
// swiftlint:disable:next system_ink_outside_the_palette
private let inactiveRowInk = Color(.tertiaryLabel)

/// A Stepper lays out through LabeledContent. Beside its control, an accessibility-size label has
/// too little width and hyphenates mid-word (`Stan-dard`), so at those sizes the control drops
/// below the label. The other rows already stack on their own.
private struct StackedAtAccessibilitySizes: LabeledContentStyle {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeBody(configuration: Configuration) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                configuration.label
                configuration.content
            }
        } else {
            LabeledContent(configuration)
        }
    }
}
