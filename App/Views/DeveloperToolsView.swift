import SwiftUI
import UIKit

struct DeveloperToolsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(SyncCoordinator.self) private var sync
    @Environment(SheetConnection.self) private var connection
    @Environment(WorkoutStore.self) private var workout
    @Environment(\.themePalette) private var palette
    @State private var diagnostics: [PendingWriteDiagnostic] = []
    @State private var writeAuditDiagnostics: [WriteTargetAuditDiagnostic] = []
    @State private var diagnosticsErrorMessage: String?
    @State private var writeAuditErrorMessage: String?
    /// By address, so a sync that lands under the celebration shows the Session it parsed.
    @State private var forcedCelebrationAddress: SessionAddress?

    var body: some View {
        ZStack {
            palette.gradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.cardSpacing) {
                    currentSessionSection
                    loadSuggestionSection
                    liveActivitySection
                    pendingWritesSection
                    actionsSection
                    writeAuditSection
                }
                .padding()
            }
        }
        .navigationTitle("Developer Tools")
        .task {
            loadDiagnostics()
        }
        .overlay {
            if let forcedCelebrationSession {
                MoveOnCelebrationView(session: forcedCelebrationSession) {
                    forcedCelebrationAddress = nil
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: forcedCelebrationAddress)
    }

    private var forcedCelebrationSession: Session? {
        forcedCelebrationAddress.flatMap { workout.block?.session(at: $0) }
    }

    private var currentSessionSection: some View {
        let info = workout.currentSessionDebugInfo

        return DeveloperToolsSection(title: "Current Session Debug Info") {
            VStack(alignment: .leading, spacing: 10) {
                CurrentSessionDebugRow(
                    label: "Current Block Tab",
                    value: info.currentBlockTab,
                    valueIdentifier: "current-session-debug-block-value"
                )
                CurrentSessionDebugRow(
                    label: "Sheet-derived Session",
                    value: info.sheetDerivedSession,
                    valueIdentifier: "current-session-debug-sheet-derived-value"
                )
                CurrentSessionDebugRow(
                    label: "Current Session Pin",
                    value: info.pinnedSession,
                    valueIdentifier: "current-session-debug-manual-override-value"
                )
                CurrentSessionDebugRow(
                    label: "Displayed Session",
                    value: info.viewedSession,
                    valueIdentifier: "current-session-debug-displayed-value"
                )
                CurrentSessionDebugRow(
                    label: "Resolved Current Session",
                    value: info.resolvedCurrentSession,
                    valueIdentifier: "current-session-debug-resolved-value"
                )
                CurrentSessionDebugRow(
                    label: "Reason",
                    value: info.reason,
                    valueIdentifier: "current-session-debug-reason-value"
                )

                if let localOnlyNote = info.localOnlyNote {
                    Text(localOnlyNote)
                        .font(Theme.font(.historyChip))
                        .foregroundStyle(palette.action)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("current-session-debug-local-only-note")
                }
            }
            .textSelection(.enabled)

            HStack(spacing: 10) {
                BorderedCircleIconButton(label: "Copy Current Session Debug Info", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = info.copyText
                }
                .accessibilityIdentifier("copy-current-session-debug-info-button")

                BorderedCircleIconButton(
                    label: "Clear Current Session Pin",
                    systemImage: "arrow.counterclockwise",
                    role: .destructive
                ) {
                    workout.clearCurrentSessionPin()
                }
                .disabled(!info.canClearPin)
                .accessibilityIdentifier("reset-current-session-override-button")
            }
        }
    }

    private var loadSuggestionSection: some View {
        DeveloperToolsSection(title: "Load Suggestion") {
            Toggle(
                "Show Load Basis",
                isOn: Binding(get: { settings.showsLoadBasis }, set: { settings.setShowsLoadBasis($0) })
            )
            .accessibilityIdentifier("developer-tools-shows-load-basis-toggle")
        }
    }

    private var actionsSection: some View {
        DeveloperToolsSection(title: "Actions") {
            HStack(spacing: 10) {
                BorderedCircleIconButton(label: "Force Move On Celebration", systemImage: "sparkles") {
                    forcedCelebrationAddress = workout.viewedSession?.address
                }
                .disabled(workout.viewedSession == nil)
                .accessibilityIdentifier("developer-tools-force-celebration-button")

                BorderedCircleIconButton(label: "Sync", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await syncConfiguredSheet() }
                }
                .disabled(!connection.canSyncNow)
                .accessibilityIdentifier("developer-tools-sync-button")
            }

            SyncStatusBanner(outcome: sync.outcome, isSyncing: sync.isSyncing)
                .accessibilityIdentifier("developer-tools-sync-status-banner")
        }
    }

    private var liveActivitySection: some View {
        DeveloperToolsSection(title: "Live Activity (prototype)") {
            NavigationLink {
                LiveActivityLabView()
            } label: {
                Image(systemName: "flask")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Open Live Activity Lab")
            .accessibilityIdentifier("developer-tools-live-activity-lab-link")
        }
    }

    private var pendingWritesSection: some View {
        DeveloperToolsSection(title: "Pending Sheet Writes") {
            if let diagnosticsErrorMessage {
                Text(diagnosticsErrorMessage)
                    .font(Theme.font(.queuePill))
                    .foregroundStyle(palette.textSecondary)
            } else if diagnostics.isEmpty {
                Text("No pending or conflicted writes")
                    .font(Theme.font(.queuePill))
                    .foregroundStyle(palette.textSecondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(diagnostics) { diagnostic in
                        PendingWriteDiagnosticRow(diagnostic: diagnostic)
                    }
                }
            }
        }
    }

    private var writeAuditSection: some View {
        DeveloperToolsSection(title: "Write Target Audit Log") {
            if let writeAuditErrorMessage {
                Text(writeAuditErrorMessage)
                    .font(Theme.font(.queuePill))
                    .foregroundStyle(palette.textSecondary)
            } else if writeAuditDiagnostics.isEmpty {
                Text("No write-target audit entries")
                    .font(Theme.font(.queuePill))
                    .foregroundStyle(palette.textSecondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(writeAuditDiagnostics) { diagnostic in
                        WriteTargetAuditDiagnosticRow(diagnostic: diagnostic)
                    }
                }
            }

            HStack(spacing: 10) {
                BorderedCircleIconButton(label: "Copy Write Log", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = WriteTargetAuditDiagnostic.copyText(for: writeAuditDiagnostics)
                }
                .accessibilityIdentifier("copy-write-log-button")

                BorderedCircleIconButton(label: "Clear Write Log", systemImage: "trash", role: .destructive) {
                    clearWriteAuditLog()
                }
                .accessibilityIdentifier("clear-write-log-button")
            }
            .disabled(writeAuditDiagnostics.isEmpty)
        }
    }

    @MainActor
    private func syncConfiguredSheet() async {
        await connection.syncNow()
        loadDiagnostics()
    }

    private func loadDiagnostics() {
        do {
            diagnostics = try sync.pendingWriteDiagnostics()
            diagnosticsErrorMessage = nil
        } catch {
            diagnostics = []
            diagnosticsErrorMessage = "Couldn't load pending Sheet writes."
        }

        do {
            writeAuditDiagnostics = try sync.writeTargetAuditDiagnostics()
            writeAuditErrorMessage = nil
        } catch {
            writeAuditDiagnostics = []
            writeAuditErrorMessage = "Couldn't load write-target audit log."
        }
    }

    private func clearWriteAuditLog() {
        do {
            try sync.clearWriteTargetAuditLog()
            loadDiagnostics()
        } catch {
            writeAuditErrorMessage = "Couldn't clear write-target audit log."
        }
    }
}

private struct CurrentSessionDebugRow: View {
    @Environment(\.themePalette) private var palette

    let label: String
    let value: String
    let valueIdentifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Theme.font(.cadence))
                .foregroundStyle(palette.textSecondary)

            Text(value)
                .font(Theme.font(.queuePill))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(valueIdentifier)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DeveloperToolsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Theme.font(.heading))

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(palette.surface, in: .rect(cornerRadius: Theme.Radius.card))
    }
}

private struct PendingWriteDiagnosticRow: View {
    @Environment(\.themePalette) private var palette

    let diagnostic: PendingWriteDiagnostic

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(diagnostic.exercise)
                    .font(Theme.font(.queuePill))
                Spacer()
                Text(diagnostic.status)
                    .font(Theme.font(.historyChip))
                    .foregroundStyle(statusColor)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    diagnosticField("Block", diagnostic.block)
                    diagnosticField("Week", diagnostic.week)
                }
                GridRow {
                    diagnosticField("Day", diagnostic.day)
                    diagnosticField("Set", diagnostic.set)
                }
                GridRow {
                    diagnosticField("Column", diagnostic.column)
                    diagnosticField("Value", diagnostic.value)
                }
            }

            if let error = diagnostic.error, !error.isEmpty {
                DangerMarkedText(message: error, role: .historyChip)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(palette.chipCarvedFill, in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var statusColor: Color {
        diagnostic.status == "Conflict" ? palette.danger : palette.action
    }

    private var accessibilityLabel: String {
        let baseLabel =
            "\(diagnostic.block), \(diagnostic.week), \(diagnostic.day), \(diagnostic.exercise), "
            + "\(diagnostic.set), \(diagnostic.column), \(diagnostic.value), \(diagnostic.status)"
        guard let error = diagnostic.error else { return baseLabel }
        return "\(baseLabel), \(error)"
    }

    private func diagnosticField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.font(.cadence))
                .foregroundStyle(palette.textSecondary)
            Text(value)
                .font(Theme.font(.historyChip))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WriteTargetAuditDiagnosticRow: View {
    @Environment(\.themePalette) private var palette

    let diagnostic: WriteTargetAuditDiagnostic

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(diagnostic.semanticTarget)
                    .font(Theme.font(.historyChip))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(diagnostic.status)
                    .font(Theme.font(.historyChip))
                    .foregroundStyle(statusColor)
            }

            diagnosticField("Selected Target", diagnostic.target)
            diagnosticField("Value Check", diagnostic.valueCheckOutcome)
            diagnosticField("Row Scan", diagnostic.rowScanDetails)

            if let message = diagnostic.message, !message.isEmpty {
                DangerMarkedText(message: message, role: .historyChip)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(palette.chipCarvedFill, in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var statusColor: Color {
        diagnostic.status == "Conflict" ? palette.danger : palette.action
    }

    private var accessibilityLabel: String {
        [
            diagnostic.semanticTarget,
            diagnostic.target,
            diagnostic.valueCheckOutcome,
            diagnostic.rowScanDetails,
            diagnostic.status,
            diagnostic.message
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    private func diagnosticField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.font(.cadence))
                .foregroundStyle(palette.textSecondary)
            Text(value)
                .font(Theme.font(.historyChip))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
