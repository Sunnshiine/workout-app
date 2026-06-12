// PROTOTYPE — throwaway. Session View layout lab; see docs/prototypes/session-view-prototypes.md.
import Foundation

/// Which Session View layout renders. `production` is the shipping view and the
/// default; everything else is a throwaway prototype switched from Developer Tools.
enum SessionPrototypeVariant: String, CaseIterable, Identifiable {
    case production
    case focusStack
    case pager
    case stage
    case rail

    static let storageKey = "sessionPrototypeVariant"
    static let launchArgumentKey = "SESSION_PROTOTYPE"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .production: "Production"
        case .focusStack: "Focus Stack"
        case .pager: "Pager"
        case .stage: "Stage"
        case .rail: "Rail"
        }
    }

    var summary: String {
        switch self {
        case .production: "The shipping Session View."
        case .focusStack: "One Exercise expanded; the rest collapse to slim rows."
        case .pager: "One Exercise per page; swipe between them."
        case .stage: "Only the active Set on screen; the queue lives in a sheet."
        case .rail: "Chip rail for orientation; one Exercise below."
        }
    }

    /// Read-only override from the `-SESSION_PROTOTYPE <variant>` launch argument
    /// (registered in the NSArgumentDomain); never written back to storage.
    static var launchOverride: SessionPrototypeVariant? {
        UserDefaults.standard.string(forKey: launchArgumentKey)
            .flatMap(SessionPrototypeVariant.init(rawValue:))
    }

    static func effective(storedRawValue: String) -> SessionPrototypeVariant {
        launchOverride ?? SessionPrototypeVariant(rawValue: storedRawValue) ?? .production
    }
}
