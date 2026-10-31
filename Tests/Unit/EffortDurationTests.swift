import Testing

@testable import WorkoutTracker

@Test(
    "Text that is one duration reads as its whole seconds",
    arguments: [
        ("15 sec", 15),
        ("15s", 15),
        ("15 secs", 15),
        ("15 seconds", 15),
        ("15-sec", 15),
        ("15 – sec", 15),
        ("15sec", 15),
        ("15 SEC", 15),
        (" 15 Sec ", 15),
        ("1 second", 1),
        (":15", 15),
        (":59", 59),
        ("0:45", 45),
        ("1:30", 90),
        ("1:30 min", 90),
        ("0:45 sec", 45),
        ("1 min", 60),
        ("2 minutes", 120),
        ("2 Mins", 120),
        ("90 sec", 90),
        ("1.5 min", 90),
        ("0.5 min", 30),
        ("40 sec", 40),
        ("25 min", 1500),
        ("60 min", 3600),
        ("30-45 sec", 30),
        ("30 – 45 seconds", 30),
        ("30–45s", 30),
        ("1-2 min", 60),
        ("0:30-0:45", 30),
        ("0:30 – 0:45", 30),
        ("45-45 sec", 45),
        ("30—45 sec", 30),
        ("30\u{2011}45 sec", 30),
        ("30\u{2012}45 sec", 30),
        ("30\u{2212}45 sec", 30),
        ("0:30—0:45", 30),
        ("40 sec.", 40),
        ("40 Sec.", 40),
        ("40s.", 40),
        ("0:40.", 40),
        ("1 min 30 sec", 90),
        ("1 minute 30 seconds", 90),
        ("1 min 30s", 90),
        ("1m30s", 90),
        ("1m 30s", 90),
        ("2 mins 5 secs", 125),
        ("1-2 min 30 sec", 90)
    ]
)
func textThatIsOneDurationReadsAsItsSeconds(text: String, seconds: Int) {
    #expect(EffortDuration(text)?.seconds == seconds)
}

@Test(
    "Text that is not one duration from 1 second to 60 minutes reads as nothing",
    arguments: [
        "45-30 sec",
        "0:45-0:30",
        "30-0 sec",
        "0 sec",
        "0:00",
        "61 min",
        "90 min",
        "3601 sec",
        "99999999999999999999 sec",
        "0:75",
        "0:60",
        ".5 min",
        "2.5 sec",
        "1m",
        "1 hr",
        "10 sets",
        "5",
        "40",
        "1-2-3-3-2-1",
        "1-2-3-3-2-1 min",
        "0:5:0",
        "2-3:1:0",
        "0:3:0",
        "1:30:0",
        "x 20yd",
        "AMRAP",
        "5+",
        "BW",
        "15 sec hold",
        "2x30s",
        "",
        "sec",
        "1—2—3 min",
        "1\u{2011}2\u{2011}3 min",
        "1\u{2012}2\u{2012}3 min",
        "1\u{2212}2\u{2212}3 min",
        "40 sec..",
        "1 min 60 sec",
        "30 sec 20 sec",
        "1 min 30",
        "20m",
        "1m 30",
        "90 min 30 sec"
    ]
)
func textThatIsNotOneDurationReadsAsNothing(text: String) {
    #expect(EffortDuration(text) == nil)
}

@Test(
    "Prose writes each duration it holds, and no Cadence or run of numbers",
    arguments: [
        ("HARD, MAX EFFORT rd, rest 1 minute; ski 2 minutes hard, rest 2 minutes", [60, 120, 120]),
        ("Super set w/ 0:5:0 Push Ups for AMRAP", []),
        ("2-3:1:0 BB RDL", []),
        ("SkiErg 1-2-3-3-2-1 min", []),
        ("3x30s plank, 45 sec rest", [30, 45]),
        ("rest 1.5 min.", [90]),
        ("hold 10 sec, rest 0:30-0:45", [10, 30]),
        ("0:45 sec", [45]),
        ("– 30 sec", [30]),
        ("1:30:15 split", []),
        ("0:456", []),
        ("rest .5 min", []),
        ("3-4-5 min", []),
        ("3–4–5 min", []),
        ("3 - 4 - 5 min", []),
        ("3—4—5 min", []),
        ("Hold 1 min 30 sec", [90]),
        ("1m30s hold", [90]),
        ("Hold 1 min, 30 sec rest", [60, 30]),
        ("rest 1 min 30 sec hold", [90]),
        ("Sled 20m, 10 sec hold", [10])
    ]
)
func proseWritesEachDurationItHolds(prose: String, seconds: [Int]) {
    #expect(EffortDuration.written(in: prose).map(\.duration.seconds) == seconds)
}

@Test func aDurationInProseKnowsWhereItIsWritten() throws {
    let prose = "Start w/ 15 sec hold"
    let written = try #require(EffortDuration.written(in: prose).first)

    #expect(prose[written.range] == "15 sec")
}

@Test(
    "A Coach Note that holds a duration at the start of the Set prescribes an Opening Hold",
    arguments: [
        ("Start w/ 15 sec hold at the top, and then proceed into leg ext. at prescribed cadence", 15),
        ("Start w/ 10 sec hold…", 10),
        ("Start w/ 10 sec hold", 10),
        ("Start w/ 10 sec hold, proceed to rep range.", 10),
        ("start with a 15 second hold", 15),
        ("15 sec hold at the top", 15),
        ("hold 10 sec", 10),
        ("Hold for 30 seconds, then 8 reps", 30),
        ("10-second iso hold", 10),
        ("20s isometric hold before the first rep", 20),
        ("15 sec iso at the top", 15),
        ("15 sec static hold", 15),
        ("iso hold 0:30", 30),
        ("START W/ 10 SEC HOLD", 10),
        ("15 sec. hold at the top", 15),
        ("15 sec-hold", 15),
        ("Start w/ 1:30 hold", 90),
        ("Start w/ 1.5 min hold", 90),
        ("start w/ a 30-45 sec hold", 30),
        ("10 sec hold, then 20 sec hold", 10),
        ("Rest 90 sec, then hold 20 sec", 20),
        ("hold 10 sec. Pause each rep.", 10),
        ("Pause every rep; start w/ 10 sec hold", 10),
        ("Pause every rep\nStart w/ 10 sec hold", 10),
        ("Pause every rep! Start w/ 10 sec hold", 10),
        ("Pause every rep? Start w/ 10 sec hold", 10),
        ("Iso 10s at the top", 10),
        ("Holding 20 sec at the top", 20),
        ("Holds 20 sec at the top", 20)
    ]
)
func aCoachNoteThatHoldsADurationAtTheStartPrescribesAnOpeningHold(coachNote: String, seconds: Int) {
    #expect(EffortDuration(openingHoldIn: coachNote)?.seconds == seconds)
}

@Test(
    "A Coach Note whose durations are no hold at the start of the Set prescribes no Opening Hold",
    arguments: [
        "HARD, MAX EFFORT rd, rest 1 minute; ski 2 minutes hard, rest 2 minutes",
        "Super set w/ 0:5:0 Push Ups for AMRAP",
        "AMRAP w/ 0:3:0 BW Push Up",
        "rest 90 sec",
        "Pause 2 sec at the bottom",
        "Hold at the top for 2 sec",
        "2 sec hold at the bottom of each rep",
        "hold 2 sec per rep",
        "3 sec hold every rep",
        "10 sec hold between sets",
        "Finish with a 10 sec hold",
        "finishing 10 sec hold",
        "10 sec hold after the last rep",
        "10 sec hold after your final rep",
        "10 sec hold on the last rep",
        "hold the last rep 10 sec",
        "hold 10 sec. pause each rep",
        "0:2:0 hold",
        "hold 0 sec",
        "hold 90 min",
        "Holding pattern",
        "hold for a while",
        "10 sets, hold",
        "x 20yd",
        "AMRAP",
        "5+",
        "BW",
        "1-2-3-3-2-1",
        "",
        "Pause every rep.",
        "Brace hard off the floor, controlled descent.",
        "Use full range.",
        "Upcoming Session.",
        "Tall posture.",
        "Pull fast from the floor.",
        "Perfect Session fixture.",
        "Pause at the top.",
        "Move crisply.",
        "Keep the front foot planted.",
        "Has Open Exercises.",
        "Exhale hard.",
        "Current Session.",
        "Controlled reps.",
        "Control the eccentric.",
        "Completed Session.",
        "Brace hard.",
        "Keep elbows soft",
        "Controlled eccentric",
        "Superset cue",
        "Keep the dumbbells honest at the bottom — full stretch, no rush.",
        "25x12@7",
        "20x10@8",
        "999x1@10",
        "100x1@10"
    ]
)
func aCoachNoteWithNoHoldAtTheStartPrescribesNoOpeningHold(coachNote: String) {
    #expect(EffortDuration(openingHoldIn: coachNote) == nil)
}
