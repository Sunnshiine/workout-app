import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(SheetConnection.self) private var connection
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var isSheetPickerPresented = false
    @State private var isSignOutConfirmationPresented = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Appearance", selection: appearanceSelection) {
                        ForEach(AppearancePreference.allCases, id: \.self) { appearance in
                            Text(appearance.label).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings-appearance-picker")
                }
                .listRowBackground(palette.surface)

                Section("Rest") {
                    Stepper(value: standardRestSeconds, in: restRange, step: RestDurationSetting.stepSeconds) {
                        LabeledContent("Standard", value: settings.standardRestDuration.displayText)
                    }
                    .accessibilityIdentifier("settings-standard-rest-stepper")

                    Stepper(value: supersetRestSeconds, in: restRange, step: RestDurationSetting.stepSeconds) {
                        LabeledContent("Superset rest", value: settings.supersetRestDuration.displayText)
                    }
                    .accessibilityIdentifier("settings-superset-rest-stepper")
                }
                .listRowBackground(palette.surface)

                Section {
                    Button {
                        isSheetPickerPresented = true
                    } label: {
                        LabeledContent("Training Sheet", value: sheetDisplayName)
                    }
                    .disabled(isSheetBusy)
                    .accessibilityIdentifier("settings-training-sheet-row")

                    Button {
                        Task { await connection.syncNow() }
                    } label: {
                        LabeledContent("Sync now") {
                            Text(connection.syncNowDetail)
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
        .alert("Settings Error", isPresented: settingsErrorPresented) {
            Button("OK", role: .cancel) {
                connection.clearError()
            }
        } message: {
            Text(connection.errorMessage ?? "")
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
        case .failed:
            break
        }
    }

    private func signOutNow() async {
        guard await connection.signOut() else { return }

        GoogleAuth.signOut()
        dismiss()
    }

    private var sheetPickerSheet: some View {
        NavigationStack {
            SheetPickerView(
                client: GoogleSheetsClient.forCurrentEnvironment(),
                onValidatedSelection: { spreadsheet in
                    let result = await connection.requestSwitch(to: spreadsheet)
                    if result == .switched || result == .unchanged {
                        isSheetPickerPresented = false
                    }
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
            isPresented: pendingSwitchConfirmation
        ) {
            Button("Cancel", role: .cancel) {
                connection.cancelPendingSwitch()
            }
            Button("Switch Anyway", role: .destructive) {
                Task {
                    let didSwitch = await connection.confirmPendingSwitch()
                    if didSwitch {
                        isSheetPickerPresented = false
                    }
                }
            }
        } message: {
            Text("Pending logs for the current sheet will be discarded.")
        }
    }

    private var pendingSwitchConfirmation: Binding<Bool> {
        Binding {
            connection.pendingConfirmation != nil
        } set: { _ in
            // Alert buttons own cancellation so "Switch Anyway" can still confirm the pending sheet.
        }
    }

    private var settingsErrorPresented: Binding<Bool> {
        Binding {
            connection.errorMessage != nil
        } set: { isPresented in
            if !isPresented {
                connection.clearError()
            }
        }
    }
}
