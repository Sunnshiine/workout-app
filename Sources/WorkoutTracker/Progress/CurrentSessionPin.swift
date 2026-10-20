import Foundation
import Observation

/// The Current Session Pin for each Block tab (`CONTEXT.md`): the Session the athlete last
/// advanced to with Move On or made current, held locally and never written to the Sheet.
///
/// `@Observable` so a reader of `resolve(in:)` re-renders after `pin` or `clear` even when the
/// resolved Session did not change, as when the cleared Pin named the Sheet-derived Session.
@MainActor
@Observable
final class CurrentSessionPin {
    /// Which move wrote the Pin.
    enum Author: Equatable, Sendable {
        case moveOn
        /// The athlete's off-live-edge Make current control.
        case madeCurrent
    }

    /// The V2 order encoding, frozen: `(week - 1) * 7 + day`. It is a stored format, not the
    /// tracker's Block order, so it changes only with a new key namespace.
    ///
    /// V2: the stride changed 4 → 7 to support 2–6 day Weeks. Under the new stride a legacy
    /// `advancedToOrder_*` integer can name a different Session, so the `V2` namespace orphans
    /// it and the Pin resets to Sheet-derived progress once.
    private static let orderStride = 7
    private static let orderKeyPrefix = "advancedToOrderV2_"
    /// Holds the order Make current wrote. The Pin counts as Made Current only while this equals
    /// the stored order, so a Move On from a build that predates this key reads as a Move On.
    private static let madeCurrentKeyPrefix = "madeCurrentOrderV2_"
    /// Matches the legacy `advancedToOrder_` and the current `advancedToOrderV2_` keys.
    private static let anyOrderKeyPrefix = "advancedToOrder"

    private let defaults: AppDefaults
    private var revision = 0

    init(defaults: AppDefaults) {
        self.defaults = defaults
    }

    /// Whether `defaults` holds a Pin for any Block tab, under any encoding version.
    static func isStored(in defaults: AppDefaults) -> Bool {
        defaults.keys.contains { $0.hasPrefix(anyOrderKeyPrefix) }
    }

    /// Writes nothing for a Session `block` does not hold, as one held across the sync that
    /// replaced its Block, so a stale Session cannot pin some other Session's order.
    func pin(_ session: Session, in block: Block, by author: Author) {
        guard let order = Self.order(of: session, in: block) else { return }
        defaults.set(order, forKey: Self.orderKey(for: block))
        switch author {
        case .moveOn:
            defaults.removeValue(forKey: Self.madeCurrentKey(for: block))
        case .madeCurrent:
            defaults.set(order, forKey: Self.madeCurrentKey(for: block))
        }
        revision += 1
    }

    func clear(in block: Block) {
        defaults.removeValue(forKey: Self.orderKey(for: block))
        defaults.removeValue(forKey: Self.madeCurrentKey(for: block))
        revision += 1
    }

    /// The Current Session of `block` and why: the Pin wins while it resolves to an Available
    /// Session of this Block, otherwise Sheet-derived progress does.
    func resolve(in block: Block) -> CurrentSessionResolution {
        _ = revision
        let tracker = SessionProgressTracker()
        let sheetDerived = tracker.currentSession(in: block)
        guard let order = defaults.integer(forKey: Self.orderKey(for: block)) else {
            return CurrentSessionResolution(blockTab: block.tabName, session: sheetDerived, sheetDerivedSession: sheetDerived, pin: .unset)
        }

        let author: Author = defaults.integer(forKey: Self.madeCurrentKey(for: block)) == order ? .madeCurrent : .moveOn
        let pinned = block.weeks.lazy.flatMap { week in week.sessions.filter { Self.order(of: $0, in: week) == order } }.first
        guard let pinned else {
            return CurrentSessionResolution(
                blockTab: block.tabName,
                session: sheetDerived,
                sheetDerivedSession: sheetDerived,
                pin: .noLongerResolves(author)
            )
        }
        guard tracker.isAvailable(pinned) else {
            return CurrentSessionResolution(
                blockTab: block.tabName,
                session: sheetDerived,
                sheetDerivedSession: sheetDerived,
                pin: .unavailable(pinned, author)
            )
        }
        return CurrentSessionResolution(blockTab: block.tabName, session: pinned, sheetDerivedSession: sheetDerived, pin: .inForce(author))
    }

    private static func order(of session: Session, in block: Block) -> Int? {
        block.weeks.first { $0.sessions.contains(session) }.map { order(of: session, in: $0) }
    }

    private static func order(of session: Session, in week: Week) -> Int {
        (week.number - 1) * orderStride + session.dayNumber
    }

    private static func orderKey(for block: Block) -> String { orderKeyPrefix + block.tabName }

    private static func madeCurrentKey(for block: Block) -> String { madeCurrentKeyPrefix + block.tabName }
}

/// One answer to "which Session is Current, and why", so no caller re-derives which arm won.
struct CurrentSessionResolution: Equatable {
    /// The Current Session Pin's standing in the Block it was resolved against.
    enum PinStanding: Equatable {
        case unset
        /// The Pin names an Available Session of this Block, so it is the Current Session.
        case inForce(CurrentSessionPin.Author)
        /// The Pin names no Session of this Block, as after a re-parse renumbers Days.
        case noLongerResolves(CurrentSessionPin.Author)
        /// The Pin names a Session of this Block that is an Unavailable Session.
        case unavailable(Session, CurrentSessionPin.Author)
    }

    let blockTab: String
    let session: Session?
    let sheetDerivedSession: Session?
    let pin: PinStanding

    /// The athlete chose this Current Session over Sheet-derived progress. A Move On advance is
    /// not one: it moves along the Block rather than away from where the Sheet says they are.
    var isMadeCurrent: Bool { pin == .inForce(.madeCurrent) }

    var isPinInForce: Bool {
        if case .inForce = pin { true } else { false }
    }

    /// A Pin is stored for this Block, in force or not.
    var hasPin: Bool { pin != .unset }
}
