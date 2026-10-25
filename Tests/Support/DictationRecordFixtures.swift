import Foundation

@testable import WorkoutTracker

enum DictationRecordFixtures {
    /// Five presses as a journal holds them: one both engines agreed on, one decided by the Live
    /// Transcript after the Recording Transcript missed the deadline, one cancelled, one whose
    /// Recording Transcript a lifter would never log, and one whose Recording Transcript wrote the
    /// prompt back. Each is one line once the source's line breaks are gone.
    static let lines = [
        #"""
        {"app":{"build":"431","commit":"6aba617","version":"1.9"},"decision":{"agreement":"agreed",
        "byRule":{"gate":{"heard":"185 for 5 at 8.","kind":"logged","setLog":"185x5@8"},
        "lead":{"heard":"185 for 5 at 8.","kind":"logged","setLog":"185x5@8"},"liveOnly":{"heard":"185 for 5 at 8.",
        "kind":"logged","setLog":"185x5@8"},"recordingOnly":{"heard":"185 for 5 at 8.","kind":"logged",
        "setLog":"185x5@8"}},"live":{"heard":"185 for 5 at 8.","kind":"logged","setLog":"185x5@8"},
        "outcome":{"heard":"185 for 5 at 8.","kind":"logged","setLog":"185x5@8"},
        "recording":{"heard":"185 for 5 at 8.","kind":"logged","setLog":"185x5@8"},"rule":"lead"},
        "device":{"footprintMB":420,"lowPower":false,"model":"iPhone17,1","os":"26.1.0","thermal":"nominal"},
        "end":"released","id":"6F1C2D0E-0000-4000-8000-000000000001","live":{"candidates":["185 for 5 at 8.",
        "185 for five at 8."],"captionChanges":7},"longestMainThreadStallMs":11,"pressedAt":"2026-10-19T17:02:11Z",
        "recording":{"audioSeconds":2.31,"decodeMs":{"decodeLoop":188,"encode":61,"fallbacks":0,"mel":4,"queued":0,
        "tokens":9,"total":262},"modelAtEnd":"ready","modelAtPress":"ready","segments":[{"avgLogprob":-0.11,
        "compressionRatio":1.07,"noSpeechProb":0.01,"temperature":0}],"transcript":"185 for 5 at 8.",
        "truncated":false,
        "version":{"model":"openai_whisper-small.en","modelRevision":"0f63a7800b00dd0226abd051b906c246e1907482",
        "options":"t0.nots.wc0.fb5","prompt":"p1","tokenizerRevision":"e8727524f962ee844a7319d92be39ac1bd25655a"}},
        "schema":1,"set":{"address":"w1d1.e0.s0","block":"Block 27","draft":{"reps":5,"rpe":8,
        "weight":"185"},"exercise":"Back Squat","previous":"185x5@7"},"surface":"card","timelineMs":{"decided":3368,
        "ended":3104,"firstHeard":640,"lastHeard":1902,"live":182,"liveFinished":3131,"recordingRead":3366}}
        """#,
        #"""
        {"app":{"build":"431","version":"1.9"},"decision":{"agreement":"liveOnly",
        "byRule":{"gate":{"heard":"same again","kind":"logged","setLog":"BWx12@7.5"},"lead":{"heard":"same again",
        "kind":"logged","setLog":"BWx12@7.5"},"liveOnly":{"heard":"same again","kind":"logged","setLog":"BWx12@7.5"},
        "recordingOnly":{"heard":"","kind":"rejected","rejection":{"reason":"nothingHeard"}}},
        "live":{"heard":"same again","kind":"logged","setLog":"BWx12@7.5"},"outcome":{"heard":"same again",
        "kind":"logged","setLog":"BWx12@7.5"},"rule":"lead"},"device":{"footprintMB":388,"lowPower":true,
        "model":"iPhone16,2","os":"26.0.1","thermal":"fair"},"end":"silence",
        "id":"6F1C2D0E-0000-4000-8000-000000000002","live":{"candidates":["same again"],"captionChanges":2},
        "longestMainThreadStallMs":4,"pressedAt":"2026-10-19T17:05:40Z","recording":{"audioSeconds":3.1,"miss":"late",
        "modelAtEnd":"ready","modelAtPress":"ready","truncated":false,
        "version":{"model":"openai_whisper-small.en","modelRevision":"0f63a7800b00dd0226abd051b906c246e1907482",
        "options":"t0.nots.wc0.fb5","prompt":"p1","tokenizerRevision":"e8727524f962ee844a7319d92be39ac1bd25655a"}},
        "schema":1,"set":{"address":"w1d1.e2.s1",
        "block":"Block 27","draft":{"reps":12,"rpe":7.5,"weight":"BW"},"exercise":"Pull Up","previous":"BWx12@7.5"},
        "surface":"headless","timelineMs":{"decided":4200,"ended":2700,"firstHeard":900,"lastHeard":1500,"live":150,
        "liveFinished":2760,"recordingDropped":4200}}
        """#,
        #"""
        {"app":{"build":"431","version":"1.9"},"device":{"footprintMB":401,"lowPower":false,"model":"iPhone17,1",
        "os":"26.1.0","thermal":"nominal"},"end":"cancelled","id":"6F1C2D0E-0000-4000-8000-000000000003",
        "longestMainThreadStallMs":3,"pressedAt":"2026-10-19T17:09:02Z","schema":1,"surface":"card",
        "timelineMs":{"ended":800,"live":120}}
        """#,
        #"""
        {"app":{"build":"431","commit":"6aba617","version":"1.9"},"decision":{"agreement":"liveFills",
        "byRule":{"gate":{"draft":{"reps":5,"rpe":8,"weight":"1247"},"heard":"1247 for 5 at 8","kind":"filled"},
        "lead":{"heard":"12.47 for 5 at 8.","kind":"rejected","rejection":{"field":"weight","reason":"implausible"}},
        "liveOnly":{"heard":"1247 for 5 at 8","kind":"logged","setLog":"1247x5@8"},
        "recordingOnly":{"heard":"12.47 for 5 at 8.","kind":"rejected","rejection":{"field":"weight",
        "reason":"implausible"}}},"live":{"heard":"1247 for 5 at 8","kind":"logged","setLog":"1247x5@8"},
        "outcome":{"heard":"12.47 for 5 at 8.","kind":"rejected","rejection":{"field":"weight","reason":"implausible"}},
        "recording":{"heard":"12.47 for 5 at 8.","kind":"rejected","rejection":{"field":"weight",
        "reason":"implausible"}},"rule":"lead"},"device":{"footprintMB":455,"lowPower":false,"model":"iPhone17,1",
        "os":"26.1.0","thermal":"serious"},"end":"released","id":"6F1C2D0E-0000-4000-8000-000000000004",
        "live":{"candidates":["1247 for 5 at 8"],"captionChanges":4},"longestMainThreadStallMs":38,
        "pressedAt":"2026-10-19T17:12:30Z","recording":{"audioSeconds":2.5,"modelAtEnd":"ready","modelAtPress":"ready",
        "segments":[],"transcript":"12.47 for 5 at 8.","truncated":false,
        "version":{"model":"openai_whisper-small.en","modelRevision":"0f63a7800b00dd0226abd051b906c246e1907482",
        "options":"t0.nots.wc0.fb5","prompt":"p1","tokenizerRevision":"e8727524f962ee844a7319d92be39ac1bd25655a"}},
        "schema":1,"set":{"address":"w1d1.e1.s0",
        "block":"Block 27","draft":{"reps":5,"rpe":8,"weight":"225"},"exercise":"Bench Press"},"surface":"card",
        "timelineMs":{"decided":2900,"ended":2100,"firstHeard":700,"lastHeard":1600,"live":140,"liveFinished":2350,
        "recordingRead":2900}}
        """#,
        #"""
        {"app":{"build":"431","commit":"6aba617","version":"1.9"},"decision":{"agreement":"disagreed",
        "byRule":{"gate":{"draft":{"reps":11,"rpe":9,"weight":"62"},"heard":"62 pounds for 11 at 9.","kind":"filled"},
        "lead":{"heard":"62 pounds for 11 at 9.","kind":"logged","setLog":"62x11@9"},
        "liveOnly":{"heard":"135 for 5 at 8","kind":"logged","setLog":"135x5@8"},
        "recordingOnly":{"heard":"62 pounds for 11 at 9.","kind":"logged","setLog":"62x11@9"}},
        "live":{"heard":"135 for 5 at 8","kind":"logged","setLog":"135x5@8"},
        "outcome":{"heard":"62 pounds for 11 at 9.","kind":"logged","setLog":"62x11@9"},
        "recording":{"heard":"62 pounds for 11 at 9.","kind":"logged","setLog":"62x11@9"},"rule":"lead"},
        "device":{"footprintMB":470,"lowPower":false,"model":"iPhone17,1","os":"26.1.0","thermal":"serious"},
        "end":"released","id":"6F1C2D0E-0000-4000-8000-000000000005","live":{"candidates":["135 for 5 at 8"],
        "captionChanges":4},"longestMainThreadStallMs":9,"pressedAt":"2026-10-19T17:15:00Z",
        "recording":{"audioSeconds":2.5,"modelAtEnd":"ready","modelAtPress":"ready","segments":[],
        "transcript":"62 pounds for 11 at 9.","truncated":false,
        "version":{"model":"openai_whisper-small.en","modelRevision":"0f63a7800b00dd0226abd051b906c246e1907482",
        "options":"t0.nots.wc0.fb5","prompt":"p1","tokenizerRevision":"e8727524f962ee844a7319d92be39ac1bd25655a"}},
        "schema":1,"set":{"address":"w1d1.e1.s0",
        "block":"Block 27","draft":{"reps":5,"rpe":8,"weight":"225"},"exercise":"Bench Press"},"surface":"card",
        "timelineMs":{"decided":2050,"ended":1800,"firstHeard":600,"lastHeard":1400,"live":160,"liveFinished":1830,
        "recordingRead":2050}}
        """#
    ].map { $0.replacingOccurrences(of: "\n", with: "") }

    /// The decided presses.
    static let decided = [lines[0], lines[1], lines[3], lines[4]]

    static func record(_ line: String) throws -> DictationRecord {
        try DictationRecord.lineDecoder().decode(DictationRecord.self, from: Data(line.utf8))
    }

    /// The cancelled press, as press `number` of the day `pressedAt` names.
    static func cancelled(_ number: Int, pressedAt: String) throws -> DictationRecord {
        try record(
            lines[2]
                .replacingOccurrences(of: "000000000003", with: String(format: "%012d", number))
                .replacingOccurrences(of: "2026-10-19T17:09:02Z", with: pressedAt)
        )
    }
}
