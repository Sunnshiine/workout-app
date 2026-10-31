import Foundation
import Testing

@testable import WorkoutTracker

/// "eighty for" sounds as "eighty-four", so the recognizer writes "80 for 5 reps at 8" as "84 5 reps
/// at 8." and "180 for 5 reps at 8" as "184 5 reps at eight.", as it writes "185 for 5" as "1854 5".
/// Verbatim from SpeechTranscriber, then the comma, article, and bare-4 forms of the same Set.
@Test(
    "A leading number ending in 4 may be a weight and its for run together, so it is never the weight left over",
    arguments: [
        "84 5 reps at 8.", "184 5 reps at eight.", "224 3 reps at nine.", "64 5 rips at RPE 9.", "64 5 representatives at RP 9.",
        "84, 5 reps, RPE 8", "84 a triple at 8", "4 5 reps at 8"
    ]
)
func aLeadingNumberEndingInFourMayHideTheForAfterAWeight(transcript: String) {
    #expect(SpokenSet.parse(transcript) == .failure(.fusedNumber))
}

@Test(
    "A number ending in 4 that a word labels is the value said",
    arguments: [
        ("84 for 5", SpokenSet.values(weight: .heard(.pounds(84)), reps: .heard(5), rpe: .notSaid)),
        ("184 for 5 at 8", .values(weight: .heard(.pounds(184)), reps: .heard(5), rpe: .heard(.eight))),
        ("184 pounds, 5 reps, RPE 8", .values(weight: .heard(.pounds(184)), reps: .heard(5), rpe: .heard(.eight))),
        ("bodyweight for 24 at 8", .values(weight: .heard(.bodyweight), reps: .heard(24), rpe: .heard(.eight))),
        ("135 for 34 reps", .values(weight: .heard(.pounds(135)), reps: .heard(34), rpe: .notSaid)),
        ("8 reps at 84 pounds", .values(weight: .heard(.pounds(84)), reps: .heard(8), rpe: .notSaid))
    ]
)
func aNumberEndingInFourThatAWordLabelsIsTheValueSaid(transcript: String, heard: SpokenSet) {
    #expect(SpokenSet.parse(transcript) == .success(heard))
}

/// The first and last lists are verbatim from SpeechTranscriber for "180 for 5 reps at 8", the top
/// transcript and each alternative in order. The second cuts the RPE off after "at".
@Test func alternativesThatRunTheForIntoALeadingNumberNeverStandInForIt() {
    #expect(SpokenSet.parse(candidates: ["184 5 reps at eight.", "1845 reps at eight.", "184 5 reps at 8."]) == .failure(.fusedNumber))
    #expect(SpokenSet.parse(candidates: ["184 5 reps at", "184 5 reps at 8"]) == .failure(.fusedNumber))
    #expect(
        SpokenSet.parse(candidates: ["184 5 reps at eight.", "1845 reps at eight.", "180 for 5 reps at eight.", "184 5 reps at 8."])
            == .success(
                SpokenSet.Chosen(
                    spokenSet: .values(weight: .heard(.pounds(180)), reps: .heard(5), rpe: .heard(.eight)),
                    source: .alternative
                )
            )
    )
}
