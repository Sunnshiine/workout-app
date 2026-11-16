import SwiftUI

/// The stage's card, its actions wired to the Session's coordinator.
extension ActiveSetCard {
    init(slot: SetCardSlot, coordinator: SessionCoordinator) {
        self.init(
            set: slot.set,
            setOrdinal: slot.ordinal,
            setCount: slot.count,
            mode: slot.mode,
            mic: coordinator.cardDictation(for: slot).map { dictation in
                SetCardMic(
                    dictation: dictation,
                    startsHandsFree: coordinator.startsHandsFree(slot),
                    start: { coordinator.startDictation(for: slot.set) },
                    finish: { await coordinator.finishDictation(of: slot.set) },
                    listenHandsFree: { await coordinator.listenHandsFree(to: slot.set) },
                    cancel: { await coordinator.cancelDictation(of: slot.set) },
                    dismiss: { coordinator.dismissDictation() }
                )
            },
            timedEffort: coordinator.cardCountdown(for: slot).map { countdown in
                SetCardTimedEffort(
                    countdown: countdown,
                    startsOnArrival: coordinator.startsCountdownOnArrival(slot),
                    start: { coordinator.startCountdown(for: slot) },
                    startRequested: { coordinator.startRequestedCountdown(for: slot) },
                    cancel: { coordinator.cancelCountdown() }
                )
            },
            onLog: { coordinator.log($0, for: slot) },
            onSkip: { coordinator.skip(for: slot) },
            onDelete: { coordinator.deleteLog(for: slot.set) },
            onFlag: { coordinator.beginFlagging(slot.set) },
            onTouchWhileHeld: { coordinator.endSpokenWriteHold() },
            onClearMenuOpened: { coordinator.suspendSpokenWriteHold() },
            onClearMenuClosed: { coordinator.endSpokenWriteHold() },
            onShow: { coordinator.cardShows($0, for: slot.set) }
        )
    }
}
