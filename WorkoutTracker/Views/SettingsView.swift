import SwiftUI

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
            ZStack {
                palette.gradient.ignoresSafeArea()

                WorkoutGlassContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        VStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Appearance")
                                    .font(.body.weight(.semibold))

                                Picker("Appearance", selection: appearanceSelection) {
                                    ForEach(AppearancePreference.allCases, id: \.self) { appearance in
                                        Text(appearance.label).tag(appearance)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .accessibilityIdentifier("settings-appearance-picker")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            Divider()
                                .overlay(palette.bannerStroke)
                                .padding(.leading, 16)

                            SettingsRestSection()

                            Divider()
                                .overlay(palette.bannerStroke)
                                .padding(.leading, 16)

                            Button {
                                isSheetPickerPresented = true
                            } label: {
                                SettingsRow(
                                    systemImage: "tablecells",
                                    title: "Training Sheet",
                                    detail: sheetDisplayName
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isSheetRouteDisabled)
                            .opacity(isSheetRouteDisabled ? 0.6 : 1)
                            .accessibilityIdentifier("settings-training-sheet-row")

                            Divider()
                                .overlay(palette.bannerStroke)
                                .padding(.leading, 56)

                            Button {
                                syncNow()
                            } label: {
                                SettingsRow(
                                    systemImage: "arrow.triangle.2.circlepath",
                                    title: "Sync now",
                                    detail: manualSyncDetail,
                                    showsChevron: false
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isManualSyncDisabled)
                            .opacity(isManualSyncDisabled ? 0.6 : 1)
                            .accessibilityIdentifier("settings-sync-now-button")
                            .accessibilityValue(manualSyncDetail ?? "")

                            Divider()
                                .overlay(palette.bannerStroke)
                                .padding(.leading, 56)

                            NavigationLink {
                                DeveloperToolsView()
                            } label: {
                                SettingsRow(
                                    systemImage: "wrench.and.screwdriver",
                                    title: "Developer Tools",
                                    detail: nil
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("settings-developer-tools-row")

                            Divider()
                                .overlay(palette.bannerStroke)
                                .padding(.leading, 56)

                            Button(role: .destructive) {
                                requestSignOut()
                            } label: {
                                SettingsRow(
                                    systemImage: "rectangle.portrait.and.arrow.right",
                                    title: "Sign Out",
                                    detail: nil,
                                    role: .destructive
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("settings-sign-out-button")
                        }
                        .padding(.vertical, 6)
                        .workoutGlass(.card)

                        BuildIdentityFooter()
                    }
                }
                .padding()
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

private struct SettingsRestSection: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rest")
                .font(.body.weight(.semibold))

            RestStepperRow(
                title: "Standard",
                duration: settings.standardRestDuration,
                decrementIdentifier: "settings-standard-rest-decrement",
                valueIdentifier: "settings-standard-rest-value",
                incrementIdentifier: "settings-standard-rest-increment",
                onDecrement: {
                    settings.setStandardRestDuration(settings.standardRestDuration.decremented())
                },
                onIncrement: {
                    settings.setStandardRestDuration(settings.standardRestDuration.incremented())
                }
            )

            RestStepperRow(
                title: "Superset rest",
                duration: settings.supersetRestDuration,
                decrementIdentifier: "settings-superset-rest-decrement",
                valueIdentifier: "settings-superset-rest-value",
                incrementIdentifier: "settings-superset-rest-increment",
                onDecrement: {
                    settings.setSupersetRestDuration(settings.supersetRestDuration.decremented())
                },
                onIncrement: {
                    settings.setSupersetRestDuration(settings.supersetRestDuration.incremented())
                }
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .contain)
    }
}

private struct RestStepperRow: View {
    let title: String
    let duration: RestDurationSetting
    let decrementIdentifier: String
    let valueIdentifier: String
    let incrementIdentifier: String
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))

                Text("30 sec steps")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                PillStepperButton(
                    systemName: "minus",
                    accessibilityIdentifier: decrementIdentifier,
                    isEnabled: duration.canDecrement,
                    action: onDecrement
                )

                Text(duration.displayText)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 58)
                    .accessibilityIdentifier(valueIdentifier)

                PillStepperButton(
                    systemName: "plus",
                    accessibilityIdentifier: incrementIdentifier,
                    isEnabled: duration.canIncrement,
                    action: onIncrement
                )
            }
        }
    }
}

private struct SettingsRow: View {
    enum RowRole {
        case normal
        case destructive
    }

    let systemImage: String
    let title: String
    let detail: String?
    var showsChevron = true
    var role = RowRole.normal
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 30)
                .foregroundStyle(iconStyle)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(titleStyle)

                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if role == .normal, showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private var iconStyle: Color {
        role == .destructive ? palette.danger : palette.accent
    }

    private var titleStyle: Color {
        role == .destructive ? palette.danger : .primary
    }
}
