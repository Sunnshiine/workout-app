import SwiftUI

/// Settings stays native (DESIGN.md §5.9, ledger §10.4): system-owned `Form` rows, native text
/// styles, and normal Dynamic Type — no glass card, no hand-built role table. Appearance
/// (System / Light / Night) lives here, and manual sync is the `Sync now` row (the Settings Own
/// Manual Sync Rule).
struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(SyncCoordinator.self) private var sync
    @Environment(WorkoutStore.self) private var workout
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var isSheetPickerPresented = false
    @State private var isSignOutConfirmationPresented = false
    @State private var settingsErrorMessage: String?
    @State private var syncActivity = SettingsSyncActivity()
    @State private var manualSyncStore: SettingsManualSyncStore?
    @State private var sheetSwitchStore: SettingsSheetSwitchStore?

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

                Section {
                    Button {
                        isSheetPickerPresented = true
                    } label: {
                        LabeledContent("Training Sheet", value: sheetDisplayName)
                    }
                    .disabled(isSheetRouteDisabled)
                    .accessibilityIdentifier("settings-training-sheet-row")

                    Button {
                        syncNow()
                    } label: {
                        LabeledContent("Sync now") {
                            Text(manualSyncDetail ?? "")
                        }
                    }
                    .disabled(isManualSyncDisabled)
                    .accessibilityIdentifier("settings-sync-now-button")
                    .accessibilityValue(manualSyncDetail ?? "")

                    NavigationLink {
                        DeveloperToolsView()
                    } label: {
                        Text("Developer Tools")
                    }
                    .accessibilityIdentifier("settings-developer-tools-row")
                }

                Section {
                    Button(role: .destructive) {
                        requestSignOut()
                    } label: {
                        Text("Sign Out")
                    }
                    .accessibilityIdentifier("settings-sign-out-button")
                }

                Section {
                    BuildIdentityFooter()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
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
        .onAppear(perform: ensureSettingsStores)
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
                clearSettingsError()
            }
        } message: {
            Text(currentSettingsErrorMessage)
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

    private var isManualSyncDisabled: Bool {
        settings.spreadsheetId == nil || syncActivity.isSyncInFlight || sync.state == .syncing
            || sheetSwitchStore?.isSwitching == true
    }

    private var isSheetRouteDisabled: Bool {
        syncActivity.isSyncInFlight || sync.state == .syncing || sheetSwitchStore?.isSwitching == true
    }

    private var manualSyncDetail: String? {
        if syncActivity.isSyncInFlight || sync.state == .syncing {
            return "Syncing..."
        }

        switch sync.state {
        case .idle:
            return settings.spreadsheetId == nil ? "Connect a sheet first" : "Refresh workout state"
        case .offline:
            return "Offline"
        case .pendingWrites(let count):
            return count == 1 ? "1 unsynced log" : "\(count) unsynced logs"
        case .conflict:
            return "Needs attention"
        case .syncing:
            return "Syncing..."
        }
    }

    private func ensureSettingsStores() {
        ensureManualSyncStore()
        ensureSheetSwitchStore()
    }

    private func ensureManualSyncStore() {
        guard manualSyncStore == nil else { return }
        manualSyncStore = SettingsManualSyncStore(settings: settings, sync: sync, syncActivity: syncActivity) {
            workout.reload()
        }
    }

    private func ensureSheetSwitchStore() {
        guard sheetSwitchStore == nil else { return }
        sheetSwitchStore = SettingsSheetSwitchStore(settings: settings, sync: sync, syncActivity: syncActivity) {
            workout.reload()
        }
    }

    private func syncNow() {
        ensureManualSyncStore()
        Task {
            await manualSyncStore?.syncNow()
        }
    }

    private func requestSignOut() {
        do {
            if try sync.hasPendingWrites() {
                isSignOutConfirmationPresented = true
                return
            }

            Task { await signOutNow() }
        } catch {
            settingsErrorMessage = "Couldn't check pending logs. Try again."
        }
    }

    private func signOutNow() async {
        do {
            try await sync.discardPendingWrites()
        } catch {
            settingsErrorMessage = "Couldn't discard pending logs. Try again."
            return
        }

        GoogleAuth.signOut()
        settings.signOut()
        dismiss()
    }

    @ViewBuilder
    private var sheetPickerSheet: some View {
        if let sheetSwitchStore {
            NavigationStack {
                SheetPickerView(
                    client: GoogleSheetsClient.forCurrentEnvironment(),
                    onValidatedSelection: { spreadsheet in
                        let result = await sheetSwitchStore.requestSwitch(to: spreadsheet)
                        if result == .switched || result == .unchanged {
                            isSheetPickerPresented = false
                        }
                    },
                    onDone: {
                        isSheetPickerPresented = false
                    },
                    isSelectionDisabled: isSheetSelectionDisabled
                )
                .background(palette.gradient.ignoresSafeArea())
                .navigationTitle("Training Sheet")
            }
            .alert(
                "You have unsynced changes. Switch anyway?",
                isPresented: pendingSwitchConfirmation
            ) {
                Button("Cancel", role: .cancel) {
                    sheetSwitchStore.cancelPendingSwitch()
                }
                Button("Switch Anyway", role: .destructive) {
                    Task {
                        let didSwitch = await sheetSwitchStore.confirmPendingSwitch()
                        if didSwitch {
                            isSheetPickerPresented = false
                        }
                    }
                }
            } message: {
                Text("Pending logs for the current sheet will be discarded.")
            }
        } else {
            ProgressView()
                .task { ensureSheetSwitchStore() }
        }
    }

    private var pendingSwitchConfirmation: Binding<Bool> {
        Binding {
            sheetSwitchStore?.pendingConfirmation != nil
        } set: { _ in
            // Alert buttons own cancellation so "Switch Anyway" can still confirm the pending sheet.
        }
    }

    private var isSheetSelectionDisabled: Bool {
        sheetSwitchStore?.isSwitching == true || syncActivity.isSyncInFlight || sync.state == .syncing
    }

    private var settingsErrorPresented: Binding<Bool> {
        Binding {
            settingsErrorMessage != nil || sheetSwitchStore?.errorMessage != nil
        } set: { isPresented in
            if !isPresented {
                clearSettingsError()
            }
        }
    }

    private var currentSettingsErrorMessage: String {
        settingsErrorMessage ?? sheetSwitchStore?.errorMessage ?? "Something went wrong."
    }

    private func clearSettingsError() {
        settingsErrorMessage = nil
        sheetSwitchStore?.clearError()
    }
}
