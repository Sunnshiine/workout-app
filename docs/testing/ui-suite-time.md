# UI Suite Time

Every pull request runs `WorkoutTrackerUITests` in the `visual-tests` job, on the simulator and the
products the Visual gate already used. `scripts/ui-suite.sh` runs it and times it from launch to exit.
The SLA is 600 seconds. A slower run still passes, but prints a message asking for a hill-climb of UI
test speed, with the five slowest tests. Under GitHub Actions the message is also a warning annotation
and a job-summary entry. The cap is 900 seconds. At the cap the script stops the run, fails the step,
and names every test still running.

On the `xcode-27` runner, which has 3 vCPUs and 7 GB of memory, a slim-booted simulator ran the suite
in 459 to 697 seconds across four runs, all green. A stock boot ran it in 567 to 1090 seconds. The cap
leaves room for the slow end of that range. Before you raise either number, make the suite faster:

- Shorten or split the slowest tests the message names. Each test's launch costs several seconds on
  the runner, so a test that only repeats another's setup costs more than it checks.
- Wait on an element or a state, never on a fixed time. `appears(within:)` returns as soon as the
  element exists.
- Use a fixture, or the `.offline` launch option, instead of a dependency the test does not control.
  #1009 made the fixture Sheet reachable, which let a pending write sync before the test read its
  banner.

Xcode's parallel testing stays off. On this runner two clones ran 0 to 33 percent slower than one
serial run, and three ran 122 to 290 percent slower. Across four parallel runs, six distinct tests
failed. Every serial run passed (runs 40261823333 and 40261825437). The clones compete for three
cores, which makes the UI tests' waits time out.

After the suite, `scripts/ui-flake-guard.sh` repeats each UI test whose lines the pull request changed,
up to 5 times, stopping at the first failure or after 300 seconds. `scripts/changed-tests.sh --ui`
prints its selection. A test's lines run from its `func test` to the brace that closes it. Unlike
`scripts/flake-guard.sh`, it adds no CPU load. Busy loops beside a simulator on three cores make the
UI tests' waits fail, which tests the runner, not the test. A failure names each failing test and the
`scripts/test-sim.sh` line that reproduces it. Failed runs upload both scripts' logs and result
bundles as the `ui-test-results` artifact.
