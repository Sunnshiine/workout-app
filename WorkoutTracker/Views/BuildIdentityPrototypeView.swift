import SwiftUI
import UIKit

// PROTOTYPE #354 — throwaway, do not merge to main.
// Three variants of the in-app build-identity surface, hosted on the existing
// Settings screen and switchable via a floating prototype bar:
//   A — Quiet footer: one caption line under the settings card, tap to copy.
//   B — About row: a standard settings row pushing a detail screen with
//       per-field copy and "open PR / commit" links.
//   C — Identity banner: a loud glass banner above the card with tappable
//       chips that deep-link to GitHub.
// Reads the Info.plist keys the TestFlight workflows stamp (GitCommit,
// PRNumber, Branch, RunNumber) plus the version pair; falls back gracefully
// in local builds where the stamped keys are absent.

enum BuildIdentityPrototype {
    /// Visible in DEBUG builds and in the dev-flavor TestFlight app; never in
    /// the stable app, even if this branch were merged by mistake.
    static var isEnabled: Bool {
        #if DEBUG
            return true
        #else
            return Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true
        #endif
    }
}

enum BuildIdentityPrototypeVariant: String, CaseIterable {
    case footer = "A"
    case aboutRow = "B"
    case banner = "C"

    var displayName: String {
        switch self {
        case .footer: "Quiet footer"
        case .aboutRow: "About row"
        case .banner: "Identity banner"
        }
    }

    func next() -> Self {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }

    func previous() -> Self {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + all.count - 1) % all.count]
    }
}

struct PrototypeBuildIdentity {
    let version: String
    let build: String
    let commit: String?
    let prNumber: String?
    let branch: String?
    let runNumber: String?

    static func read(from bundle: Bundle = .main) -> PrototypeBuildIdentity {
        let info = bundle.infoDictionary ?? [:]
        func value(_ key: String) -> String? {
            guard let string = info[key] as? String, !string.isEmpty else { return nil }
            return string
        }
        return PrototypeBuildIdentity(
            version: value("CFBundleShortVersionString") ?? "0.0",
            build: value("CFBundleVersion") ?? "0",
            commit: value("GitCommit"),
            prNumber: value("PRNumber"),
            branch: value("Branch"),
            runNumber: value("RunNumber")
        )
    }

    var isStamped: Bool { commit != nil }

    /// e.g. `0.354 (129) · e4f5g6h · PR #354`
    var compactLine: String {
        var parts = ["\(version) (\(build))"]
        if let commit { parts.append(commit) }
        if let prNumber { parts.append("PR #\(prNumber)") }
        if !isStamped { parts.append("local build") }
        return parts.joined(separator: " · ")
    }

    var copyText: String {
        var lines = ["Version: \(version) (\(build))"]
        if let commit { lines.append("Commit: \(commit)") }
        if let branch { lines.append("Branch: \(branch)") }
        if let prNumber { lines.append("PR: #\(prNumber)") }
        if let runNumber { lines.append("Run: \(runNumber)") }
        if !isStamped { lines.append("Local build (no CI stamp)") }
        return lines.joined(separator: "\n")
    }

    var prURL: URL? {
        prNumber.flatMap { URL(string: "https://github.com/Sunnshiine/workout-app/pull/\($0)") }
    }

    var commitURL: URL? {
        commit.flatMap { URL(string: "https://github.com/Sunnshiine/workout-app/commit/\($0)") }
    }
}

// MARK: - Variant A — quiet footer

struct BuildIdentityFooterVariantA: View {
    private let identity = PrototypeBuildIdentity.read()
    @State private var didCopy = false

    var body: some View {
        Button {
            UIPasteboard.general.string = identity.copyText
            didCopy = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                didCopy = false
            }
        } label: {
            Text(didCopy ? "Copied" : identity.compactLine)
                .font(.caption2)
                .monospaced()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Build identity, tap to copy")
        .accessibilityIdentifier("build-identity-footer")
    }
}

// MARK: - Variant B — about row + detail screen

struct BuildIdentityAboutRowVariantB: View {
    @Environment(\.themePalette) private var palette
    private let identity = PrototypeBuildIdentity.read()

    var body: some View {
        NavigationLink {
            BuildIdentityDetailVariantB(identity: identity)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "info.circle")
                    .font(.title3.weight(.semibold))
                    .frame(width: 30)
                    .foregroundStyle(palette.accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text("About This Build")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(identity.compactLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("build-identity-about-row")
    }
}

struct BuildIdentityDetailVariantB: View {
    @Environment(\.themePalette) private var palette
    let identity: PrototypeBuildIdentity
    @State private var copiedField: String?

    var body: some View {
        ZStack {
            palette.gradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.cardSpacing) {
                    VStack(spacing: 0) {
                        field("Version", "\(identity.version) (\(identity.build))")
                        divider
                        field("Commit", identity.commit ?? "— local build")
                        divider
                        field("Branch", identity.branch ?? "—")
                        divider
                        field("Pull Request", identity.prNumber.map { "#\($0)" } ?? "—")
                        divider
                        field("CI Run", identity.runNumber ?? "—")
                    }
                    .padding(.vertical, 6)
                    .workoutGlass(.card)

                    if let prURL = identity.prURL {
                        Link(destination: prURL) {
                            Label("Open PR #\(identity.prNumber ?? "")", systemImage: "arrow.up.right.square")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.workoutGlass)
                    }

                    if let commitURL = identity.commitURL {
                        Link(destination: commitURL) {
                            Label("Open Commit \(identity.commit ?? "")", systemImage: "arrow.up.right.square")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.workoutGlass)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("About This Build")
    }

    private var divider: some View {
        Divider()
            .overlay(palette.bannerStroke)
            .padding(.leading, 16)
    }

    private func field(_ label: String, _ value: String) -> some View {
        Button {
            UIPasteboard.general.string = value
            copiedField = label
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                if copiedField == label { copiedField = nil }
            }
        } label: {
            HStack {
                Text(label)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(copiedField == label ? "Copied" : value)
                    .font(.subheadline)
                    .monospaced()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) \(value), tap to copy")
    }
}

// MARK: - Variant C — identity banner

struct BuildIdentityBannerVariantC: View {
    @Environment(\.themePalette) private var palette
    private let identity = PrototypeBuildIdentity.read()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "shippingbox")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.accent)

                Text("Build \(identity.version) (\(identity.build))")
                    .font(.title3.weight(.bold))

                Spacer()
            }

            if identity.isStamped {
                HStack(spacing: 8) {
                    if let prURL = identity.prURL {
                        Link(destination: prURL) {
                            chipLabel("PR #\(identity.prNumber ?? "")", systemImage: "arrow.triangle.pull")
                        }
                        .contextMenu {
                            Button("Copy PR Number") {
                                UIPasteboard.general.string = identity.prNumber
                            }
                        }
                    }

                    if let commitURL = identity.commitURL {
                        Link(destination: commitURL) {
                            chipLabel(identity.commit ?? "", systemImage: "number")
                        }
                        .contextMenu {
                            Button("Copy Commit") {
                                UIPasteboard.general.string = identity.commit
                            }
                        }
                    }

                    if let branch = identity.branch {
                        Button {
                            UIPasteboard.general.string = branch
                        } label: {
                            chipLabel(branch, systemImage: "arrow.branch")
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text("Local build — no CI stamp")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .workoutGlass(.card)
        .accessibilityIdentifier("build-identity-banner")
    }

    private func chipLabel(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
            Text(text)
                .font(.caption.weight(.semibold))
                .monospaced()
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(palette.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(palette.badgeFill, in: Capsule())
        .frame(maxWidth: 160)
    }
}

// MARK: - Floating prototype switcher

struct BuildIdentityPrototypeSwitcher: View {
    @Binding var variant: BuildIdentityPrototypeVariant

    var body: some View {
        HStack(spacing: 14) {
            Button {
                variant = variant.previous()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.bold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("build-identity-prototype-previous")

            VStack(spacing: 1) {
                Text("PROTOTYPE")
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(1.5)
                    .opacity(0.7)
                Text("\(variant.rawValue) — \(variant.displayName)")
                    .font(.footnote.weight(.semibold))
            }
            .frame(minWidth: 120)

            Button {
                variant = variant.next()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.bold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("build-identity-prototype-next")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(.white)
        .background(.black.opacity(0.78), in: Capsule())
        .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
        .accessibilityIdentifier("build-identity-prototype-switcher")
    }
}
