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
    @State private var sheetSwitchStore: SettingsSheetSwitchStore?

    var body: some View {
        NavigationStack {
            ZStack {
                palette.gradient.ignoresSafeArea()

                GlassEffectContainer(spacing: 12) {
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
                        .accessibilityIdentifier("settings-training-sheet-row")

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
                    .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
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
        .onAppear(perform: ensureSheetSwitchStore)
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

    private func ensureSheetSwitchStore() {
        guard sheetSwitchStore == nil else { return }
        sheetSwitchStore = SettingsSheetSwitchStore(
            settings: settings,
            sync: sync,
            onSynced: {
                workout.reload()
            }
        )
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
                    client: sheetPickerClient,
                    onValidatedSelection: { spreadsheet in
                        let result = await sheetSwitchStore.requestSwitch(to: spreadsheet)
                        if result == .switched || result == .unchanged {
                            isSheetPickerPresented = false
                        }
                    },
                    onDone: {
                        isSheetPickerPresented = false
                    },
                    isSelectionDisabled: sheetSwitchStore.isSwitching
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

    private var sheetPickerClient: any SheetsClient {
        #if DEBUG
            if UITestFixture.isEnabled {
                return UITestFixture.makeSheetsClient()
            }
        #endif
        return GoogleSheetsClient()
    }

    private var pendingSwitchConfirmation: Binding<Bool> {
        Binding {
            sheetSwitchStore?.pendingConfirmation != nil
        } set: { _ in
            // Alert buttons own cancellation so "Switch Anyway" can still confirm the pending sheet.
        }
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

private struct SettingsRow: View {
    enum RowRole {
        case normal
        case destructive
    }

    let systemImage: String
    let title: String
    let detail: String?
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

            if role == .normal {
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
