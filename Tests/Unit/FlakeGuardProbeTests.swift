import Testing

// A planted flake for the flake guard's red proof: it passes the gate's one run and fails from its
// third repetition in the same process.
struct FlakeGuardProbeTests {
    nonisolated(unsafe) static var runs = 0

    @Test func flakeGuardProbePassesOnlyItsFirstTwoRuns() {
        Self.runs += 1
        #expect(Self.runs <= 2, "run \(Self.runs)")
    }
}
