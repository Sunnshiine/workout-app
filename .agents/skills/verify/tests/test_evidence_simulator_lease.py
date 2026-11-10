from evidence_support import *  # noqa: F401,F403
from evidence_lane import *  # noqa: F401,F403


STUB = """#!/bin/sh
printf '%s\\n' "$(basename "$0") $*" >> "{dir}/calls"
case "$(basename "$0") $*" in
  "xcrun simctl list devices booted") echo "    iPhone 17 Pro (${STUB_BOOTED:-}) (Booted)" ;;
  "xcrun simctl install "*) rm -rf "{dir}/container"; mkdir "{dir}/container"; cp -R "$4" "{dir}/container/" ;;
  "xcrun simctl get_app_container "*) [ -d "{dir}/container/WorkoutTracker.app" ] && echo "{dir}/container/WorkoutTracker.app" ;;
  "xcrun simctl bootstatus "*|"xcrun simctl terminate "*) ;;
  "xcrun simctl launch "*) echo "com.sunnypatel.WorkoutTracker: 4121" ;;
  "xcodebuild "*) echo "** BUILD FAILED **" ; exit 65 ;;
  "plutil -extract WorkspacePath"*) echo "{project}" ;;
  "axe describe-ui "*) cat "{dir}/describe-ui.json" ;;
  *) exit 1 ;;
esac
"""
NO_LEASE = "you hold no Simlock lease; verify.sh launch <fixture> takes one\n"
NO_SIMLOCK = "simlock is not on PATH, and every simulator here comes from a Simlock lease; see .agents/skills/simlock/SKILL.md\n"
DRIVES = [["doctor"], ["stop"], ["online"], ["tree"], ["find", "weight-pill"], ["tap", "-x", "1", "-y", "2"],
          ["hold", "weight-pill"], ["type", "245"], ["swipe", "up"], ["shot", "01-before"], ["burst", "log-transition"],
          ["record", "take-1"], ["axe", "key", "40"]]


def lease_udid(serial):
    return "%08X-0579-4ABC-8DEF-%012X" % (os.getpid(), serial)


def not_yours(named, held):
    return ("%s is not the simulator of a Simlock lease you hold (yours: %s); lease one first, "
            "see .agents/skills/simlock/SKILL.md\n") % (named, held)


class SimulatorLease(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.checkout = fake_checkout(self.tmp)
        self.home = self.tmp / "home"
        built_app(self.home, b"head\n")
        self.evidence = self.tmp / "evidence"
        self.stubs = self.tmp / "bin"
        self.stubs.mkdir()
        self.udid, self.other = lease_udid(1), lease_udid(2)
        stub = STUB.replace("{dir}", str(self.stubs)).replace("{project}", str(self.checkout / "WorkoutTracker.xcodeproj"))
        axe = self.checkout / ".build" / "verify" / "node_modules" / "xcodebuildmcp" / "bundled" / "axe"
        axe.parent.mkdir(parents=True)
        for tool in [self.stubs / "xcodebuild", self.stubs / "xcrun", self.stubs / "npm", self.stubs / "plutil", axe]:
            tool.write_text(stub)
            tool.chmod(0o755)
        (self.stubs / "describe-ui.json").write_text(MINI)
        self.simlock = FakeSimlock(self.stubs, free=[self.udid])

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)
        for udid in [self.udid, self.other]:
            shutil.rmtree("/tmp/workout-verify-%s" % udid, ignore_errors=True)

    def run_script(self, argv, **env):
        (self.stubs / "calls").unlink(missing_ok=True)
        Path(str(self.simlock.state) + ".calls").unlink(missing_ok=True)
        environment = dict(os.environ, HOME=str(self.home), PATH="%s:%s" % (self.stubs, os.environ["PATH"]),
                           VERIFY_EVIDENCE=str(self.evidence))
        for name in ["SIM", "VERIFY_RUN"]:
            environment.pop(name, None)
        environment.update(env)
        done = subprocess.run(argv, cwd=str(self.checkout), env=environment,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        calls = self.stubs / "calls"
        return done.returncode, done.stdout, done.stderr, calls.read_text().splitlines() if calls.exists() else []

    def verify(self, *argv, **env):
        return self.run_script([str(self.checkout / ".agents" / "skills" / "verify" / "verify.sh")] + list(argv), **env)

    def run_test_sim(self, *argv, **env):
        code, out, err, calls = self.run_script([str(self.checkout / "scripts" / "test-sim.sh")] + list(argv), **env)
        body, _, last = out.rstrip("\n").rpartition("\n")
        self.assertRegex(last, r"^test-sim: suite=\S+ passed=- failed=- expected=- exit=%d " % code)
        return code, body + "\n" if body else "", err, calls

    def test_launch_with_no_lease_leases_an_iphone_17_pro_and_launches_on_it(self):
        code, out, err, calls = self.verify("launch", "session", VERIFY_RUN="issue-1", STUB_BOOTED=self.udid)
        self.assertEqual((code, out, err), (0, "launched session as pid 4121 on %s\n"
                                               "app %s commit unknown (not built by verify.sh)\n"
                                               "evidence %s/issue-1\n" % (self.udid, digest(b"head\n"), self.evidence), (
            "leasing an iPhone 17 Pro simulator on iOS 27.0 from Simlock for 60 min, renewed by each verify call\n"
            "simulator %s (Simlock lease lse_%s); verify.sh release gives it back\n") % (self.udid, self.udid)))
        self.assertEqual(self.simlock.calls(), [
            "simlock whoami", "simlock list --leases", "simlock list --devices",
            "simlock lease --platform ios --device iPhone 17 Pro --os 27.0 --timeout 540s --detach --ttl 60m",
            "simlock whoami", "simlock list --leases", "simlock list --devices", "simlock simctl bootstatus %s -b" % self.udid,
        ], "a detached lease with a TTL, checked again by the claim, and booted through Simlock")
        self.assertEqual(self.simlock.leases(), [(self.udid, FakeSimlock.PRINCIPAL)])
        steps = [call.split() for call in calls if call.split()[:3] in [["xcrun", "simctl", step] for step in
                                                                          ["bootstatus", "install", "launch"]]]
        self.assertEqual([(step[2], self.udid in step) for step in steps],
                         [("bootstatus", True), ("install", True), ("launch", True)], "booted, installed and launched on it")

    def test_the_leased_pair_is_the_pair_the_visual_baselines_were_recorded_on(self):
        ci = (REPO / ".github" / "workflows" / "ci.yml").read_text()
        device, runtime = re.search(r"BASELINE_DEVICE: (.+)\n\s+BASELINE_RUNTIME: \"(.+)\"", ci).groups()
        self.verify("launch", "session", VERIFY_RUN="issue-1")
        lease, = [call for call in self.simlock.calls() if call.startswith("simlock lease ")]
        self.assertIn(" --device %s --os %s " % (device, runtime), lease,
                      "re-recording the baselines on a new pair moves the leased pair with it")

    def test_later_calls_reuse_the_lease_and_renew_it_once_half_its_ttl_has_passed(self):
        self.simlock.hold(self.udid, minutes_left=31)
        code, out, err, calls = self.verify("tree")
        self.assertEqual(code, 0, err)
        self.assertEqual(self.simlock.calls(), ["simlock whoami", "simlock list --leases", "simlock list --devices"], "found, not renewed")
        self.assertEqual(calls, ["axe describe-ui --udid %s" % self.udid])
        self.simlock.edit(lambda state: state.update(leases=[]))
        self.simlock.hold(self.udid, minutes_left=29)
        self.assertEqual(self.verify("tree")[0], 0)
        self.assertEqual(self.simlock.calls(), ["simlock whoami", "simlock list --leases", "simlock list --devices", "simlock lease renew lse_%s" % self.udid])
        self.assertEqual(self.verify("tree")[0], 0)
        self.assertEqual(self.simlock.calls(), ["simlock whoami", "simlock list --leases", "simlock list --devices"], "the renewal reset its TTL")

    def test_a_sim_that_is_not_your_lease_is_refused_and_leases_nothing(self):
        self.simlock.hold(self.other, requester="another-agent")
        for held, mine in [("none", []), (self.udid, [(self.udid, FakeSimlock.PRINCIPAL)])]:
            if mine:
                self.simlock.hold(self.udid)
            for argv in [["launch", "session"], ["tree"], ["release"]]:
                with self.subTest(held=held, argv=argv):
                    self.assertEqual(self.verify(*argv, SIM=self.other), (2, "", not_yours(self.other, held), []))
                    self.assertEqual(self.simlock.leases(), [(self.other, "another-agent")] + mine)

    def test_with_no_lease_every_command_but_build_install_and_launch_refuses_and_touches_no_simulator(self):
        for argv in DRIVES:
            with self.subTest(argv=argv):
                self.assertEqual(self.verify(*argv, VERIFY_RUN="issue-1"), (2, "", NO_LEASE, []))
                self.assertEqual(self.simlock.calls(), ["simlock whoami", "simlock list --leases", "simlock list --devices"], "and leases nothing")
        self.assertFalse(self.evidence.exists(), "nothing was shot")

    def test_with_no_lease_diff_sheet_and_crop_read_only_the_run_verify_run_names(self):
        run = self.evidence / "issue-1"
        run.mkdir(parents=True)
        for name in ["01-before", "02-after-log"]:
            shutil.copy(FIXTURES / ("%s.tree.txt" % name), run / ("%s.tree.txt" % name))
        diff = (FIXTURES / "01-before--02-after-log.diff.txt").read_text()
        self.assertEqual(self.verify("diff", "01-before", "02-after-log", VERIFY_RUN="issue-1"), (0, diff, "", []))
        verify = self.checkout / ".agents" / "skills" / "verify" / "verify.sh"
        for argv in [["diff", "01-before", "02-after-log"], ["sheet"], ["crop", "01-before", "weight-pill"]]:
            with self.subTest(argv=argv):
                self.assertEqual(self.verify(*argv), (1, "", (
                    "no evidence directory for this run in %s; name one: VERIFY_RUN=<run> %s %s ...\n"
                    "recent runs:\n  issue-1\n") % (self.evidence, verify, argv[0]), []))

    def test_release_stops_the_app_then_gives_the_lease_back(self):
        self.simlock.hold(self.udid)
        state = Path("/tmp/workout-verify-%s" % self.udid)
        state.mkdir(parents=True)
        app = subprocess.Popen(FIXTURE_APP, start_new_session=True)
        self.addCleanup(app.wait)
        self.addCleanup(app.kill)
        (state / "run").write_text("issue-1\n")
        (state / "pid").write_text("%d\n" % app.pid)
        (state / "args").write_text("-UITEST_FIXTURE -UITEST_SESSION -UITEST_DISABLE_LIVE_ACTIVITIES\n")
        self.assertEqual(self.verify("release", VERIFY_RUN="issue-1"), (
            0, "terminated pid %d\nreleased Simlock lease lse_%s on %s\n" % (app.pid, self.udid, self.udid), "",
            ["xcrun simctl terminate %s com.sunnypatel.WorkoutTracker" % self.udid]))
        self.assertEqual(self.simlock.leases(), [])
        self.assertEqual(sorted(p.name for p in state.iterdir()), ["run"])
        self.assertEqual(self.verify("release"), (0, "you hold no Simlock lease\n", "", []), "a second release is a no-op")
        self.assertEqual(self.verify("tree"), (2, "", NO_LEASE, []))

    def test_stop_keeps_the_lease(self):
        self.simlock.hold(self.udid)
        self.assertEqual(self.verify("stop"), (0, "nothing launched by this tool on %s\n" % self.udid, "", []))
        self.assertEqual(self.simlock.leases(), [(self.udid, FakeSimlock.PRINCIPAL)])

    def test_without_simlock_every_command_that_touches_a_simulator_exits_78(self):
        (self.stubs / "simlock").unlink()
        for argv in [["build"], ["launch", "session"], ["install"], ["release"]] + DRIVES:
            with self.subTest(argv=argv):
                self.assertEqual(self.verify(*argv, VERIFY_RUN="issue-1"), (78, "", NO_SIMLOCK, []))
        code, out, err, calls = self.run_test_sim("--sim", self.udid, "unit")
        self.assertEqual((code, out, err, calls), (78, "", NO_SIMLOCK, []))

    def test_test_sim_without_sim_is_refused_while_you_hold_a_lease_and_runs_on_it_with_sim(self):
        self.simlock.hold(self.udid)
        code, out, err, calls = self.run_test_sim("unit")
        self.assertEqual((code, out, calls), (75, "", []))
        self.assertEqual(err.splitlines()[-1], (
            "your Simlock identity already holds a lease (simulator %s, lease lse_%s); pass that simulator with --sim "
            "or SIM=, or simlock release its lease first") % (self.udid, self.udid), "Simlock refused a second lease (exit 13)")
        code, out, err, calls = self.run_test_sim("--sim", self.udid, "unit")
        self.assertEqual(code, 65, "the stub build failed: %s" % err)
        self.assertIn("xcodebuild build-for-testing", "\n".join(calls))
        self.assertIn("-destination platform=iOS Simulator,id=%s " % self.udid, "\n".join(calls))
        self.assertEqual(self.simlock.leases(), [(self.udid, FakeSimlock.PRINCIPAL)], "the lease it reused is still yours")

    def test_a_lowercase_sim_launches_on_the_simulator_simlock_spells_in_capitals(self):
        self.simlock.hold(self.udid)
        code, out, err, calls = self.verify("launch", "session", SIM=self.udid.lower(), VERIFY_RUN="issue-579",
                                            STUB_BOOTED=self.udid)
        self.assertEqual((code, out, err), (0, "launched session as pid 4121 on %s\n"
                                               "app %s commit unknown (not built by verify.sh)\n"
                                               "evidence %s/issue-579\n" % (self.udid, digest(b"head\n"), self.evidence), ""))
        self.assertNotIn(self.udid.lower(), "\n".join(calls + self.simlock.calls()), "every call names it in capitals")

    def test_a_lowercase_sim_is_the_simulator_test_sim_keys_its_lock_by(self):
        self.simlock.hold(self.udid)
        state = Path("/tmp/workout-verify-%s" % self.udid)
        state.mkdir(parents=True)
        app = subprocess.Popen(FIXTURE_APP, start_new_session=True)
        self.addCleanup(app.wait)
        self.addCleanup(app.kill)
        (state / "run").write_text("owner-579\n")
        (state / "pid").write_text("%d\n" % app.pid)
        code, out, err, calls = self.run_test_sim("--sim", self.udid.lower(), "unit")
        self.assertEqual((code, out, err), (75, "", (
            "a verify run owner-579 owns the app on %s (pid %d), last used 0 min ago; a claim takes it once it goes 60 min "
            "unused. If it is yours, rerun with VERIFY_RUN=owner-579 or run: SIM=%s VERIFY_RUN=owner-579 "
            "%s/.agents/skills/verify/verify.sh stop, else use another simulator\n") % (self.udid, app.pid, self.udid, self.checkout)),
            "the lock is keyed by the one spelling, so a case-sensitive /tmp cannot split it")
        self.assertEqual(calls, [])
