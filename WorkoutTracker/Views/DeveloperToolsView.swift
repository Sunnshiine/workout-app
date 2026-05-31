import SwiftUI
import UIKit

struct DeveloperToolsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(SyncCoordinator.self) private var sync
    @Environment(WorkoutStore.self) private var workout
    @State private var diagnostics: [PendingWriteDiagnostic] = []
    @State private var writeAuditDiagnostics: [WriteTargetAuditDiagnostic] = []
    @State private var diagnosticsErrorMessage: String?
    @State private var writeAuditErrorMessage: String?
    @State private var isSyncInFlight = false
    @State private var previewSession: Session?

    var body: some View {
        ZStack {
            Theme.gradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.cardSpacing) {
                    currentSessionSection
                    celebrationSection
                    pendingWritesSection
                    writeAuditSection
                    syncSection
                }
                .padding()
            }
        }
        .navigationTitle("Developer Tools")
        .task {
            loadDiagnostics()
        }
        .overlay {
            if let previewSession {
                MoveOnCelebrationView(session: previewSession) {
                    self.previewSession = nil
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: previewSession?.persistentModelID)
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
                    label: "Manual Current Session Override",
                    value: info.manualOverrideSession,
                    valueIdentifier: "current-session-debug-manual-override-value"
                )
                CurrentSessionDebugRow(
                    label: "Displayed Session",
                    value: info.displayedSession,
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("current-session-debug-local-only-note")
                }
            }
            .textSelection(.enabled)

            Button {
                UIPasteboard.general.string = info.copyText
            } label: {
                Label("Copy Current Session Debug Info", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("copy-current-session-debug-info-button")

            Button(role: .destructive) {
                workout.resetCurrentSessionOverride()
            } label: {
                Label("Reset Current Session Override", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.glass)
            .disabled(!workout.hasCurrentSessionOverride)
            .accessibilityIdentifier("reset-current-session-override-button")
        }
    }

    private var celebrationSection: some View {
        DeveloperToolsSection(title: "Move On Celebration") {
            Button {
                previewSession = workout.displayedSession
            } label: {
                Label("Force Move On Celebration", systemImage: "sparkles")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.glass)
            .disabled(workout.displayedSession == nil)
            .accessibilityIdentifier("developer-tools-force-celebration-button")
        }
    }

    private var pendingWritesSection: some View {
        DeveloperToolsSection(title: "Pending Sheet Writes") {
            if let diagnosticsErrorMessage {
                Text(diagnosticsErrorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if diagnostics.isEmpty {
                Text("No pending or conflicted writes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if writeAuditDiagnostics.isEmpty {
                Text("No write-target audit entries")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(writeAuditDiagnostics) { diagnostic in
                        WriteTargetAuditDiagnosticRow(diagnostic: diagnostic)
                    }
                }
            }

            Button {
                UIPasteboard.general.string = WriteTargetAuditDiagnostic.copyText(for: writeAuditDiagnostics)
            } label: {
                Label("Copy Write Log", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.glass)
            .disabled(writeAuditDiagnostics.isEmpty)
            .accessibilityIdentifier("copy-write-log-button")

            Button(role: .destructive) {
                clearWriteAuditLog()
            } label: {
                Label("Clear Write Log", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.glass)
            .disabled(writeAuditDiagnostics.isEmpty)
            .accessibilityIdentifier("clear-write-log-button")
        }
    }

    private var syncSection: some View {
        DeveloperToolsSection(title: "Sync") {
            Button {
                Task { await syncConfiguredSheet() }
            } label: {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.glass)
            .disabled(isSyncDisabled)
            .accessibilityIdentifier("developer-tools-sync-button")

            SyncStatusBanner(state: sync.state)
        }
    }

    private var isSyncDisabled: Bool {
        isSyncInFlight || sync.state == .syncing || settings.spreadsheetId == nil
    }

    @MainActor
    private func syncConfiguredSheet() async {
        guard let id = settings.spreadsheetId, !isSyncDisabled else { return }
        isSyncInFlight = true
        defer {
            isSyncInFlight = false
            loadDiagnostics()
        }
        await sync.sync(spreadsheetId: id)
        workout.reload()
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
    let label: String
    let value: String
    let valueIdentifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
    }
}

private struct PendingWriteDiagnosticRow: View {
    let diagnostic: PendingWriteDiagnostic

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(diagnostic.exercise)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(diagnostic.status)
                    .font(.caption.weight(.semibold))
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
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var statusColor: Color {
        diagnostic.status == "Conflict" ? .red : Theme.accent
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
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WriteTargetAuditDiagnosticRow: View {
    let diagnostic: WriteTargetAuditDiagnostic

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(diagnostic.semanticTarget)
                    .font(.caption.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(diagnostic.status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }

            diagnosticField("Selected Target", diagnostic.target)
            diagnosticField("Value Check", diagnostic.valueCheckOutcome)
            diagnosticField("Row Scan", diagnostic.rowScanDetails)

            if let message = diagnostic.message, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var statusColor: Color {
        diagnostic.status == "Conflict" ? .red : Theme.accent
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
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
