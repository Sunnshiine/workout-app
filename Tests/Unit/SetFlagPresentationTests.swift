import Foundation
import Testing

@testable import WorkoutTracker

@Test func aDraftMakesNoFlagUntilAKindOrWordsAreGiven() {
    var draft = SetFlagDraft()
    draft.words = "   "
    #expect(draft.kind == nil)
    #expect(draft.flag == nil)

    draft.kind = .pain
    #expect(draft.flag == SetFlag(kind: .pain, text: nil))
}

@Test func wordsTypedBeforeAKindChooseOtherAndALaterChoiceKeepsThem() {
    var draft = SetFlagDraft()
    draft.words = "left hip"
    #expect(draft.flag == SetFlag(kind: .other, text: "left hip"))

    draft.kind = .pain
    draft.words = "left hip pinch"
    #expect(draft.flag == SetFlag(kind: .pain, text: "left hip pinch"))
}

@Test func aDraftOfOtherMakesNoFlagUntilItHasWords() {
    var draft = SetFlagDraft()
    draft.kind = .other
    #expect(draft.flag == nil)
    #expect(draft.placeholder == "Other needs a few words")

    draft.words = "   "
    #expect(draft.flag == nil)

    draft.words = "gym closed early"
    #expect(draft.flag == SetFlag(kind: .other, text: "gym closed early"))
}

@Test func aDraftOfAKindThatStandsAloneMakesAFlagWithNoWords() throws {
    var draft = SetFlagDraft()
    draft.kind = .technique

    let flag = try #require(draft.flag)
    #expect(flag.kind == .technique)
    #expect(flag.text == nil)
    #expect(draft.placeholder == "What should your coach know?")
}

@Test func aDraftsWordsStayOnOneLineAndInsideWhatAFlagCanCarry() {
    var draft = SetFlagDraft()
    draft.words = "left hip\npinch"
    #expect(draft.words == "left hip pinch")

    draft.words = String(repeating: "a", count: SetFlag.maximumTextLength + 40)
    #expect(draft.words.count == SetFlag.maximumTextLength)
}

@MainActor
private func secondBenchSet(in session: Session, state: SetState, log: SetLog?) throws -> ExerciseSet {
    let exercise = try #require(session.exercises.first { $0.order == 1 })
    let set = try #require(exercise.sets.first { $0.index == 1 })
    set.state = state
    set.setLog = log
    return set
}

@MainActor
private func sheetLine(state: SetState, log: SetLog?) throws -> String {
    let session = makeCoordinatorSession()
    let set = try secondBenchSet(in: session, state: state, log: log)
    return SetFlagSheetPresentation(id: try SetCoordinates(of: set).id, set: set).setLine
}

@MainActor
@Test func theSheetNamesTheSetAndWhatItHolds() throws {
    let session = makeCoordinatorSession()
    let set = try secondBenchSet(in: session, state: .logged, log: SetLog(weight: .pounds(185), reps: 5, rpe: .eight))
    let logged = SetFlagSheetPresentation(id: try SetCoordinates(of: set).id, set: set)

    #expect(logged.exerciseName == "Bench Press")
    #expect(logged.setLine == "Set 2 · 185x5@8")
    #expect(logged.raiseTitle == "Flag Set 2")
    #expect(try sheetLine(state: .skipped, log: nil) == "Set 2 · Skipped")
    #expect(try sheetLine(state: .pending, log: nil) == "Set 2")
}

@MainActor
@Test func theSheetListsTheFlagsAlreadyRaisedNewestFirstWithWhereEachStands() throws {
    let session = makeCoordinatorSession()
    let set = try secondBenchSet(in: session, state: .logged, log: SetLog(weight: .pounds(185), reps: 5, rpe: .eight))
    set.record(try #require(SetFlag(kind: .pain, text: "left hip")), standing: .landed)
    set.record(try #require(SetFlag(kind: .technique, text: nil)), standing: .unsynced)

    let raised = SetFlagSheetPresentation(id: try SetCoordinates(of: set).id, set: set).raisedFlags

    #expect(raised.map(\.sentence) == ["Technique", "Pain: left hip"])
    #expect(raised.map(\.standing) == [.unsynced, .landed])
}

@MainActor
@Test func aSetTheAthleteCameBackToOffersTheFlagAndAHeldOrPendingSetOnlySaysWhereOneStands() throws {
    let session = makeCoordinatorSession()
    let logged = try secondBenchSet(in: session, state: .logged, log: SetLog(weight: .pounds(185), reps: 5, rpe: .eight))
    let exercise = try #require(session.exercises.first { $0.order == 1 })
    let pending = try #require(exercise.sets.first { $0.index == 0 })
    let skipped = try #require(session.exercises.first { $0.order == 2 }?.sets.first)
    skipped.state = .skipped

    let review = SetCardSlot.Mode.reviewingLogged(showsSavedConfirmation: false)
    #expect(review.showsSetFlagControl(for: logged))
    #expect(SetCardSlot.Mode.logging.showsSetFlagControl(for: logged))
    #expect(SetCardSlot.Mode.logging.showsSetFlagControl(for: skipped))

    #expect(!SetCardSlot.Mode.logging.showsSetFlagControl(for: pending))
    #expect(!SetCardSlot.Mode.heldAfterSpokenWrite.showsSetFlagControl(for: logged))

    let flag = try #require(SetFlag(kind: .pain, text: nil))
    pending.record(flag, standing: .unsynced)
    logged.record(flag, standing: .unsynced)
    #expect(SetCardSlot.Mode.logging.showsSetFlagControl(for: pending))
    #expect(SetCardSlot.Mode.heldAfterSpokenWrite.showsSetFlagControl(for: logged))
}

@Test func theStandingsWordsMatchTheSyncLanguage() {
    #expect(SetFlagStanding.unsynced.word == "Unsynced")
    #expect(SetFlagStanding.landed.word == "In the Sheet")
    #expect(SetFlagStanding.refused.word == "Flag not written")
}
