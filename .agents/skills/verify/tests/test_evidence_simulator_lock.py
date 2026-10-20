from evidence_support import *  # noqa: F401,F403
from evidence_lane import *  # noqa: F401,F403


STUB = """#!/bin/sh
[ "$(basename "$0") $*" != "xcrun simctl list devices available -j" ] || { echo '{"devices": {"iOS-27-0": [{"udid": "{sim}"}]}}'; exit 0; }
printf '%s\\n' "$(basename "$0") $*" >> "{dir}/calls"
[ "$(basename "$0") $1 $2" != "plutil -extract WorkspacePath" ] || { echo "{project}"; exit 0; }
[ "$(basename "$0")" != xcodebuild ] || echo "** BUILD FAILED **"
[ -n "${STUB_HOLD:-}" ] || exit 1
touch "{dir}/holding"
i=0
while [ ! -f "{dir}/release" ] && [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
exit 1
"""


class SimulatorLock(unittest.TestCase):
    def setUp(self):
        self.sim = "LOCK-TEST-%d" % os.getpid()
        self.state = Path("/tmp/workout-verify-%s" % self.sim)
        shutil.rmtree(self.state, ignore_errors=True)
        self.stubs = Path(tempfile.mkdtemp())
        stub = STUB.replace("{dir}", str(self.stubs)).replace("{sim}", self.sim)
        for tool in ["xcodebuild", "xcrun", "npm", "plutil"]:
            (self.stubs / tool).write_text(stub.replace("{project}", str(REPO / "WorkoutTracker.xcodeproj")))
            (self.stubs / tool).chmod(0o755)
        self.path = "%s:%s" % (self.stubs, os.environ["PATH"])
        self.home = self.stubs / "home"
        self.app = built_app(self.home, b"head\n")
        self.evidence = self.stubs / "evidence"
        self.runs = []
        self.checkout = fake_checkout(self.stubs)

    def tearDown(self):
        (self.stubs / "release").touch()
        for run in self.runs:
            if run.poll() is None:
                os.killpg(run.pid, 9)
                run.wait()
            for pipe in (run.stdout, run.stderr):
                if pipe:
                    pipe.close()
        shutil.rmtree(self.stubs, ignore_errors=True)
        shutil.rmtree(self.state, ignore_errors=True)

    def calls(self):
        path = self.stubs / "calls"
        return path.read_text().splitlines() if path.exists() else []

    def verify(self, *argv, run="issue-626"):
        return verify_sh(*argv, run=run, sim=self.sim, path=self.path, evidence=self.evidence, HOME=str(self.home))

    def first_words(self):
        return [call.split()[:2] for call in self.calls()]

    def spawn(self, argv, hold=False, **env):
        env = dict(os.environ, PATH=self.path, **env)
        if hold:
            env["STUB_HOLD"] = "1"
        run = subprocess.Popen(
            argv, cwd=str(REPO), env=env, start_new_session=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
        )
        self.runs.append(run)
        return run

    def spawn_test_sim(self, hold=False):
        return self.spawn([str(self.checkout / "scripts" / "test-sim.sh"), "--sim", self.sim, "unit"], hold)

    def wait_for_hold(self, run, stub):
        for _ in range(100):
            if (self.stubs / "holding").exists():
                return run
            if run.poll() is not None:
                self.fail("exited %s before it reached %s: %s" % (run.returncode, stub, run.stderr.read()))
            time.sleep(0.1)
        self.fail("never reached %s" % stub)

    def holding_test_sim(self):
        (self.stubs / "holding").unlink(missing_ok=True)
        return self.wait_for_hold(self.spawn_test_sim(hold=True), "xcodebuild")

    def own_the_app(self, owner, argv=FIXTURE_APP):
        app = subprocess.Popen(argv, start_new_session=True)
        self.runs.append(app)
        self.state.mkdir(parents=True, exist_ok=True)
        (self.state / "run").write_text("%s\n" % owner)
        (self.state / "pid").write_text("%d\n" % app.pid)
        (self.state / "args").write_text("-UITEST_FIXTURE -UITEST_SESSION -UITEST_DISABLE_LIVE_ACTIVITIES\n")
        return app

    def test_launch_refuses_while_a_test_sim_run_holds_the_simulator(self):
        run = self.holding_test_sim()
        code, out, err = self.verify("launch", "session")
        self.assertEqual((code, out), (75, ""), err)
        self.assertEqual(err, (
            "%s is held by a test-sim.sh run (pid %d); wait for it to finish, or use another simulator "
            "(lsof /tmp/workout-verify-%s/lock lists every process holding it)\n"
            "app on %s unchanged: an unknown app (the simulator is not booted); this launch wanted app %s commit unknown "
            "(not built by verify.sh)\n"
        ) % (self.sim, run.pid, self.sim, self.sim, digest(b"head\n")), "names the holder, then the app left installed")
        self.assertEqual(self.calls()[1:], [
            "plutil -extract WorkspacePath raw %s" % (self.app.parents[3] / "info.plist"),
            "xcrun simctl get_app_container %s com.sunnypatel.WorkoutTracker" % self.sim,
            "xcrun simctl list devices booted",
        ], "refused before any simulator is touched: no install, no axe install, only reads of what is installed")

    def test_test_sim_refuses_while_a_verify_run_owns_the_app(self):
        app = self.own_the_app("owner-626")
        run = self.spawn_test_sim()
        out, err = run.communicate(timeout=30)
        self.assertEqual(run.returncode, 75, err)
        self.assertEqual(
            err,
            "a verify run owner-626 owns the app on %s (pid %d), last used 0 min ago; a claim takes it once it goes 60 min "
            "unused. If it is yours, rerun with VERIFY_RUN=owner-626 or run: SIM=%s VERIFY_RUN=owner-626 "
            "%s/.agents/skills/verify/verify.sh stop, else use another simulator\n" % (self.sim, app.pid, self.sim, self.checkout),
            "names the verify run and its app, and a stop that frees this simulator from any directory",
        )
        self.assertEqual(self.calls(), [], "refused before xcodebuild")

    def test_a_pid_another_process_reused_does_not_hold_the_simulator(self):
        self.own_the_app("owner-626", ["sleep", "60"])
        run = self.spawn_test_sim()
        out, err = run.communicate(timeout=30)
        self.assertEqual(run.returncode, 65, "went ahead to the stub build, which failed: %s" % err)
        self.assertEqual(self.first_words(), [["xcodebuild", "build-for-testing"]])

    def test_test_sim_refuses_while_a_launch_is_under_way(self):
        launch = self.spawn([str(SKILL / "verify.sh"), "launch", "session"], hold=True,
                            SIM=self.sim, VERIFY_RUN="issue-626", HOME=str(self.home))
        self.wait_for_hold(launch, "xcrun simctl bootstatus")
        run = self.spawn_test_sim()
        out, err = run.communicate(timeout=30)
        self.assertEqual(run.returncode, 75, err)
        self.assertIn("verify.sh launch (pid %d)" % launch.pid, err, "names the launch that holds it")
        self.assertEqual(self.first_words(), [["plutil", "-extract"], ["xcrun", "simctl"]],
                         "the launch got as far as its boot wait, and test-sim.sh ran no xcodebuild")

    def test_stop_refuses_to_uninstall_while_a_test_sim_run_holds_the_simulator(self):
        self.state.mkdir(parents=True, exist_ok=True)
        (self.state / "run").write_text("owner-626\n")
        (self.state / "pid").write_text("99999999\n")
        (self.state / "args").write_text("-UITEST_FIXTURE -UITEST_SESSION -UITEST_DISABLE_ANIMATIONS\n")
        run = self.holding_test_sim()
        code, out, err = self.verify("stop", run="owner-626")
        self.assertEqual(code, 75, "the uninstall would remove the app under test: %s" % err)
        self.assertIn("test-sim.sh run (pid %d)" % run.pid, err, "names the run that holds it")
        self.assertEqual(out, "")
        self.assertEqual(self.first_words(), [["xcodebuild", "build-for-testing"]], "no xcrun call")
        self.assertEqual(sorted(p.name for p in self.state.iterdir()), ["args", "lock", "pid", "run"],
                         "a later stop can still uninstall")
        (self.stubs / "release").touch()
        run.communicate(timeout=30)
        code, out, err = self.verify("stop", run="owner-626")
        self.assertEqual(code, 0, err)
        self.assertEqual(self.calls()[-1], "xcrun simctl uninstall %s com.sunnypatel.WorkoutTracker" % self.sim)
        self.assertEqual(sorted(p.name for p in self.state.iterdir()), ["lock", "run"])

    def test_a_test_sim_run_holds_the_simulator_until_it_exits(self):
        run = self.holding_test_sim()
        self.assertEqual(self.verify("launch", "session")[0], 75)
        (self.stubs / "release").touch()
        run.communicate(timeout=30)
        self.assertEqual(run.returncode, 65, "the stub build failed, so the run ended")
        code, out, err = self.verify("launch", "session")
        self.assertNotEqual(code, 75, err)
        self.assertNotIn("test-sim.sh", err)

    def test_a_killed_test_sim_run_does_not_hold_the_simulator(self):
        killed = self.holding_test_sim()
        os.killpg(killed.pid, 9)
        killed.wait()
        run = self.holding_test_sim()
        code, out, err = self.verify("launch", "session")
        self.assertEqual(code, 75, err)
        self.assertIn("test-sim.sh run (pid %d)" % run.pid, err, "the live run holds it, not the killed one")

    def test_a_dead_verify_app_does_not_hold_the_simulator(self):
        self.own_the_app("owner-626")
        (self.state / "pid").write_text("99999999\n")
        run = self.holding_test_sim()
        code, out, err = self.verify("launch", "session")
        self.assertEqual(code, 75, "the test-sim.sh run went ahead and holds it now: %s" % err)
        self.assertIn("test-sim.sh run (pid %d)" % run.pid, err)

    def test_shot_and_burst_refuse_while_a_test_sim_run_holds_the_simulator(self):
        run = self.holding_test_sim()
        name = "issue-626-%d" % os.getpid()
        evidence = self.evidence / name
        for argv in [["shot", "01-mid-test"], ["burst", "log-transition"]]:
            code, out, err = self.verify(*argv, run=name)
            self.assertEqual(code, 75, "%s would record the test run's screen: %s" % (argv[0], err))
            self.assertIn("test-sim.sh run (pid %d)" % run.pid, err, "names the run that holds it")
            self.assertEqual(out, "")
        self.assertEqual(self.first_words(), [["xcodebuild", "build-for-testing"]],
                         "refused before any simulator is touched: no xcrun, no axe install")
        self.assertFalse(evidence.exists(), "no evidence directory for shots that were never taken")
        (self.stubs / "release").touch()
        run.communicate(timeout=30)
        for argv in [["shot", "02-after-test"], ["burst", "log-transition"]]:
            code, out, err = self.verify(*argv, run=name)
            self.assertNotEqual(code, 75, "%s goes ahead once the test run is over: %s" % (argv[0], err))
            self.assertNotIn("is held", err)

    def test_the_xcodebuild_of_a_killed_test_sim_run_holds_the_simulator_until_it_exits(self):
        run = self.holding_test_sim()
        os.kill(run.pid, 9)
        run.wait()
        code, out, err = self.verify("launch", "session")
        self.assertEqual(code, 75, "its xcodebuild still drives the simulator: %s" % err)
        self.assertIn("test-sim.sh run (pid %d)" % run.pid, err, "the run that started it")
        self.assertIn("lsof /tmp/workout-verify-%s/lock" % self.sim, err, "finds the xcodebuild its dead pid hides")
        self.assertEqual(out, "")
        (self.stubs / "release").touch()
        for _ in range(50):
            code, out, err = self.verify("launch", "session")
            if code != 75:
                break
            time.sleep(0.1)
        self.assertNotEqual(code, 75, "the xcodebuild exited, so nothing holds the simulator: %s" % err)
        self.assertRegex((self.state / "lock").read_text(), r"^verify\.sh launch \(pid \d+\)\n$", "the launch took it")


BOOT_STUB = """#!/bin/sh
lock=/tmp/workout-verify-{sim}/lock
if [ "$*" = "simctl list devices available -j" ]; then
  echo '{"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-0": [{"name": "iPhone 17 Pro", "udid": "{sim}", "state": "Shutdown"}]}}'
  exit 0
fi
held=$(python3 -c 'import fcntl, sys
try: fcntl.flock(open(sys.argv[1]), fcntl.LOCK_SH | fcntl.LOCK_NB)
except FileNotFoundError: print("free")
except BlockingIOError: print("held by " + open(sys.argv[1]).read().strip())
else: print("free")' "$lock")
printf '%s, lock %s\\n' "$(basename "$0") $*" "$held" >> "{dir}/calls"
case "$(basename "$0") $2" in
  "plutil WorkspacePath") echo "{project}" ;;
  "xcrun bootstatus")
    if [ -n "${STUB_HOLD:-}" ]; then echo $$ > "{dir}/holding"; exec sleep 30; fi
    exit "${STUB_BOOTSTATUS:-1}" ;;
  "xcrun list"|"xcrun boot") ;;
  *) exit 1 ;;
esac
"""
NOT_BOOTED = ("simulator %s did not boot\n"
              "app on %s unchanged: an unknown app (the simulator is not booted); this launch wanted app %s commit unknown "
              "(not built by verify.sh)\n")


class LaunchBoots(unittest.TestCase):
    def setUp(self):
        self.sim = "BOOT-TEST-%d" % os.getpid()
        self.state = Path("/tmp/workout-verify-%s" % self.sim)
        shutil.rmtree(self.state, ignore_errors=True)
        self.home = Path(tempfile.mkdtemp())
        self.plist = built_app(self.home, b"head\n").parents[3] / "info.plist"
        self.stubs = self.home / "bin"
        self.stubs.mkdir()
        stub = BOOT_STUB.replace("{sim}", self.sim).replace("{dir}", str(self.stubs))
        stub = stub.replace("{project}", str(REPO / "WorkoutTracker.xcodeproj"))
        for tool in ["xcodebuild", "xcrun", "npm", "plutil"]:
            (self.stubs / tool).write_text(stub)
            (self.stubs / tool).chmod(0o755)
        self.runs = []

    def tearDown(self):
        for run in self.runs:
            if run.poll() is None:
                os.killpg(run.pid, 9)
                run.wait()
            for pipe in (run.stdout, run.stderr):
                pipe.close()
        shutil.rmtree(self.home, ignore_errors=True)
        shutil.rmtree(self.state, ignore_errors=True)

    def spawn(self, **env):
        env = dict(os.environ, HOME=str(self.home), PATH="%s:%s" % (self.stubs, os.environ["PATH"]),
                   VERIFY_RUN="issue-676", VERIFY_EVIDENCE=str(self.home / "evidence"), SIM=self.sim, **env)
        run = subprocess.Popen(
            [str(SKILL / "verify.sh"), "launch", "session"], cwd=str(REPO), env=env, start_new_session=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
        )
        self.runs.append(run)
        return run

    def launch(self, **env):
        (self.stubs / "calls").unlink(missing_ok=True)
        run = self.spawn(**env)
        out, err = run.communicate(timeout=30)
        calls = self.stubs / "calls"
        return run, calls.read_text().splitlines() if calls.exists() else [], (run.returncode, out, err)

    def test_launch_waits_on_the_boot_under_its_lock_and_installs_nothing_when_it_fails(self):
        run, calls, result = self.launch()
        holder = "lock held by verify.sh launch (pid %d)" % run.pid
        self.assertEqual(calls, [
            "plutil -extract WorkspacePath raw %s, lock free" % self.plist,
            "xcrun simctl boot %s, %s" % (self.sim, holder),
            "xcrun simctl bootstatus %s -b, %s" % (self.sim, holder),
            "xcrun simctl get_app_container %s com.sunnypatel.WorkoutTracker, %s" % (self.sim, holder),
            "xcrun simctl list devices booted, %s" % holder,
        ], "the app is found before the claim; the simulator is admitted, booted and waited on while the launch holds it, "
           "and never installed to")
        self.assertEqual(result, (70, "", NOT_BOOTED % (self.sim, self.sim, digest(b"head\n"))))
        self.assertRegex((self.home / "evidence" / "issue-676" / "launches.txt").read_text(),
                         r"^\S+ launch refused: app on %s unchanged: an unknown app" % self.sim)

    def test_a_boot_wait_that_ends_with_the_simulator_down_installs_nothing(self):
        run, calls, result = self.launch(STUB_BOOTSTATUS="0")
        self.assertEqual(calls[2:], [
            "xcrun simctl bootstatus %s -b, lock held by verify.sh launch (pid %d)" % (self.sim, run.pid),
            "xcrun simctl list devices booted, lock held by verify.sh launch (pid %d)" % run.pid,
            "xcrun simctl get_app_container %s com.sunnypatel.WorkoutTracker, lock held by verify.sh launch (pid %d)"
            % (self.sim, run.pid),
            "xcrun simctl list devices booted, lock held by verify.sh launch (pid %d)" % run.pid,
        ], "bootstatus exits 0 when a shutdown ends the boot, so the launch reads the state before it installs")
        self.assertEqual(result, (70, "", NOT_BOOTED % (self.sim, self.sim, digest(b"head\n"))))

    def test_a_launch_killed_during_its_boot_wait_frees_the_simulator_at_once(self):
        killed = self.spawn(STUB_HOLD="1")
        for _ in range(100):
            if (self.stubs / "holding").exists() or killed.poll() is not None:
                break
            time.sleep(0.1)
        self.assertTrue((self.stubs / "holding").exists(), "the launch never reached its boot wait")
        os.kill(killed.pid, 9)
        killed.wait()
        boot_wait = int((self.stubs / "holding").read_text())
        self.addCleanup(os.kill, boot_wait, 9)
        run, calls, result = self.launch()
        os.kill(boot_wait, 0)
        self.assertEqual(result, (70, "", NOT_BOOTED % (self.sim, self.sim, digest(b"head\n"))),
                         "the next launch takes the simulator while the killed one's boot wait still runs")
