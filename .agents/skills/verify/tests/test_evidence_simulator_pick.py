from evidence_support import *  # noqa: F401,F403
from evidence_lane import *  # noqa: F401,F403


PICK_STUB = """#!/bin/sh
printf '%s\\n' "$(basename "$0") $*" >> "{dir}/calls"
case "$(basename "$0") $*" in
  "xcrun simctl list devices available -j") cat "{dir}/devices.json" ;;
  "xcrun simctl list devices booted") echo "    iPhone 17 Pro (${STUB_BOOTED:-}) (Booted)" ;;
  "xcrun simctl list -j") cat "{dir}/catalog.json" ;;
  "xcrun simctl create "*)
    python3 -c 'import json, sys
from pathlib import Path
stubs, name, runtime, udid = sys.argv[1:]
for listing in ("devices.json", "catalog.json"):
    path = Path(stubs, listing)
    machine = json.loads(path.read_text())
    machine["devices"].setdefault(runtime, []).append(
        {"name": name, "udid": udid, "state": "Shutdown", "isAvailable": True})
    path.write_text(json.dumps(machine))' "{dir}" "$3" "$5" {created}
    echo {created} ;;
  "xcrun simctl boot "*) ;;
  "xcrun simctl install "*) rm -rf "{dir}/container"; mkdir "{dir}/container"; cp -R "$4" "{dir}/container/" ;;
  "xcrun simctl get_app_container "*) [ -d "{dir}/container/WorkoutTracker.app" ] && echo "{dir}/container/WorkoutTracker.app" ;;
  "xcrun simctl bootstatus "*) exit "${STUB_BOOTSTATUS:-1}" ;;
  "xcrun simctl launch "*) echo "com.sunnypatel.WorkoutTracker: 4121" ;;
  "xcodebuild "*) echo "** BUILD FAILED **" ; exit 65 ;;
  "plutil -extract WorkspacePath"*) echo "{project}" ;;
  "axe describe-ui "*) cat "{dir}/describe-ui.json" ;;
  *) exit 1 ;;
esac
"""
IOS_26_5 = {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5", "version": "26.5", "isAvailable": True}
IOS_27_0 = {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0", "version": "27.0", "isAvailable": True}
PRO = {"name": "iPhone 17 Pro", "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"}
PRO_MAX = {"name": "iPhone 17 Pro Max", "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"}
AIR = {"name": "iPhone Air", "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-Air"}
CREATE_PRO = ("xcrun simctl create iPhone 17 Pro com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro "
              "com.apple.CoreSimulator.SimRuntime.iOS-27-0")
SIM_UNSET = (
    "SIM is not set. verify.sh drives only the simulator you name, because the stock iPhone 17 Pro is shared and "
    "another agent's app may be on it (issue 660).\n"
    "Make a lane simulator once and pass it on every call:\n"
    "  export SIM=$(xcrun simctl create LANE_NAME \"iPhone 17 Pro\" com.apple.CoreSimulator.SimRuntime.iOS-27-0)\n"
)


def device(name, udid, state="Shutdown", available=True):
    return {"name": name, "udid": udid, "state": state, "isAvailable": available}


def pick_udid(serial):
    return "%08X-0579-4ABC-8DEF-%012X" % (os.getpid(), serial)


class SimulatorPick(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.checkout = fake_checkout(self.tmp)
        self.home = self.tmp / "home"
        self.app = built_app(self.home, b"head\n")
        self.plist = self.app.parents[3] / "info.plist"
        self.evidence = self.tmp / "evidence"
        self.stubs = self.tmp / "bin"
        self.stubs.mkdir()
        self.created = pick_udid(1)
        self.locks = [self.created]
        stub = PICK_STUB.replace("{dir}", str(self.stubs)).replace("{created}", self.created)
        stub = stub.replace("{project}", str(self.checkout / "WorkoutTracker.xcodeproj"))
        axe = self.checkout / ".build" / "verify" / "node_modules" / "xcodebuildmcp" / "bundled" / "axe"
        axe.parent.mkdir(parents=True)
        for tool in [self.stubs / "xcodebuild", self.stubs / "xcrun", self.stubs / "npm", self.stubs / "plutil", axe]:
            tool.write_text(stub)
            tool.chmod(0o755)
        (self.stubs / "describe-ui.json").write_text(MINI)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)
        for udid in self.locks:
            shutil.rmtree("/tmp/workout-verify-%s" % udid, ignore_errors=True)

    def machine(self, runtimes, devicetypes, devices):
        self.locks += [d["udid"] for ds in devices.values() for d in ds]
        catalog = {"runtimes": runtimes, "devicetypes": devicetypes, "devices": devices}
        (self.stubs / "catalog.json").write_text(json.dumps(catalog))
        available = {runtime: [d for d in ds if d["isAvailable"]] for runtime, ds in devices.items()}
        (self.stubs / "devices.json").write_text(json.dumps({"devices": available}))

    def fresh_machine(self):
        self.machine([IOS_26_5, IOS_27_0], [PRO, PRO_MAX, AIR], {
            IOS_26_5["identifier"]: [],
            IOS_27_0["identifier"]: [device("iPhone 17 Pro Max", pick_udid(2))],
        })

    def run_script(self, argv, **env):
        (self.stubs / "calls").unlink(missing_ok=True)
        for log in self.checkout.glob(".build/*/*-build.log"):
            log.unlink()
        environment = dict(os.environ, HOME=str(self.home), PATH="%s:%s" % (self.stubs, os.environ["PATH"]),
                           VERIFY_EVIDENCE=str(self.evidence))
        environment.pop("SIM", None)
        environment.pop("VERIFY_RUN", None)
        environment.update(env)
        done = subprocess.run(
            argv, cwd=str(self.checkout), env=environment,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
        )
        calls = self.stubs / "calls"
        return done.returncode, done.stdout, done.stderr, calls.read_text().splitlines() if calls.exists() else []

    def run_test_sim(self, *argv):
        code, out, err, calls = self.run_script([str(self.checkout / "scripts" / "test-sim.sh")] + list(argv or ["visual"]))
        body, _, last = out.rstrip("\n").rpartition("\n")
        self.assertRegex(last, r"^test-sim: suite=\S+ passed=- failed=- expected=- exit=%d load1=\S+/\S+ bundle=-$" % code)
        return code, body + "\n" if body else "", err, calls

    def verify(self, *argv, **env):
        return self.run_script([str(self.checkout / ".agents" / "skills" / "verify" / "verify.sh")] + list(argv), **env)

    def failed_build(self):
        log, = self.checkout.glob(".build/*/*-build.log")
        return "** BUILD FAILED **\nbuild log: %s\n" % log

    def build_for_testing_on(self, udid):
        return ("xcodebuild build-for-testing -project %s/WorkoutTracker.xcodeproj -scheme WorkoutTracker "
                "-destination platform=iOS Simulator,id=%s -skipPackagePluginValidation -skipMacroValidation "
                "CODE_SIGNING_ALLOWED=NO" % (self.checkout, udid) + cache_settings(self.home))

    def test_test_sim_creates_the_missing_iphone_17_pro_on_the_baseline_runtime_and_runs_on_it(self):
        self.fresh_machine()
        code, out, err, calls = self.run_test_sim()
        self.assertEqual(calls, [
            "xcrun simctl list devices available -j",
            "xcrun simctl list -j",
            CREATE_PRO,
            "xcrun simctl list devices available -j",
            "xcrun simctl list devices available -j",
            "xcrun simctl list devices available -j",
            "xcrun simctl boot %s" % self.created,
            self.build_for_testing_on(self.created),
        ], "the created simulator is picked from simctl again, admitted on the host's booted count, recounted under the admit lock, booted, and built for")
        self.assertEqual((code, out, err), (65, "", "creating iPhone 17 Pro on iOS 27.0\n" + self.failed_build()))

    def test_the_created_simulator_is_the_pair_the_visual_baselines_were_recorded_on(self):
        ci = (REPO / ".github" / "workflows" / "ci.yml").read_text()
        pinned = re.search(r"BASELINE_DEVICE: (.+)\n\s+BASELINE_RUNTIME: \"(.+)\"", ci).groups()
        self.fresh_machine()
        code, out, err, calls = self.run_test_sim()
        self.assertEqual(err.splitlines()[0], "creating %s on iOS %s" % pinned,
                         "re-recording the baselines on a new pair moves pick_sim's pair with it")

    def test_with_sim_unset_every_verify_command_that_needs_a_simulator_refuses_and_calls_no_xcrun(self):
        self.fresh_machine()
        for argv in [["build"], ["install"], ["install", "HEAD"], ["launch", "session"], ["launch", "--at", "HEAD", "session"],
                     ["doctor"], ["stop"], ["tree"], ["find", "weight-pill"], ["tap", "-x", "1", "-y", "2"],
                     ["hold", "weight-pill"], ["type", "245"], ["swipe", "up"], ["shot", "01-before"],
                     ["burst", "log-transition"], ["axe", "key", "40"]]:
            with self.subTest(argv=argv):
                self.assertEqual(self.verify(*argv, VERIFY_RUN="issue-660"), (2, "", SIM_UNSET, []),
                                 "issue 660: the stock iPhone 17 Pro is never picked for you")
        self.assertFalse(self.evidence.exists(), "nothing was shot")

    def test_with_sim_unset_diff_sheet_and_crop_read_the_run_verify_run_names(self):
        run = self.evidence / "issue-660"
        run.mkdir(parents=True)
        for name in ["01-before", "02-after-log"]:
            shutil.copy(FIXTURES / ("%s.tree.txt" % name), run / ("%s.tree.txt" % name))
        diff = (FIXTURES / "01-before--02-after-log.diff.txt").read_text()
        self.assertEqual(self.verify("diff", "01-before", "02-after-log", VERIFY_RUN="issue-660"), (0, diff, "", []))
        verify = self.checkout / ".agents" / "skills" / "verify" / "verify.sh"
        for argv in [["diff", "01-before", "02-after-log"], ["sheet"], ["crop", "01-before", "weight-pill"]]:
            with self.subTest(argv=argv):
                self.assertEqual(self.verify(*argv), (1, "", (
                    "no evidence directory for this run in %s; name one: VERIFY_RUN=<run> %s %s ...\n"
                    "recent runs:\n  issue-660\n") % (self.evidence, verify, argv[0]), []),
                    "with neither SIM nor VERIFY_RUN there is no run to read, so it says to name one")

    def test_a_missing_runtime_or_device_type_fails_with_what_the_machine_has(self):
        unavailable = pick_udid(4)
        no_type = "Xcode has no iPhone 17 Pro device type. available:\n  iPhone 17 Pro Max\n  iPhone Air\n"
        machines = {
            "no iOS 27.0": ([IOS_26_5], [PRO, PRO_MAX], {IOS_26_5["identifier"]: []},
                            "no available iOS 27.0 runtime. available: 26.5\n"),
            "no iPhone 17 Pro": ([IOS_26_5, IOS_27_0], [PRO_MAX, AIR],
                                 {IOS_26_5["identifier"]: [], IOS_27_0["identifier"]: []}, no_type),
            "an unavailable iPhone 17 Pro and no type": (
                [IOS_26_5, IOS_27_0], [PRO_MAX, AIR],
                {IOS_27_0["identifier"]: [device("iPhone 17 Pro", unavailable, available=False)]}, no_type),
        }
        for machine, (runtimes, devicetypes, devices, message) in machines.items():
            with self.subTest(machine=machine):
                self.machine(runtimes, devicetypes, devices)
                code, out, err, calls = self.run_test_sim()
                self.assertEqual((code, out, err), (1, "", message))
                self.assertEqual(calls, ["xcrun simctl list devices available -j", "xcrun simctl list -j"],
                                 "nothing is created, booted, locked, or built")
                self.assertFalse(Path("/tmp/workout-verify-%s" % unavailable).exists(),
                                 "the unavailable one is never claimed")

    def test_an_existing_iphone_17_pro_is_picked_booted_first_then_newest_and_nothing_is_created(self):
        old, new = pick_udid(0x2605), pick_udid(0x2700)
        cases = [
            ("the booted one, though older", "Booted", "Shutdown",
             ["xcrun simctl list devices available -j", self.build_for_testing_on(old)]),
            ("the newest when none is booted", "Shutdown", "Shutdown",
             ["xcrun simctl list devices available -j", "xcrun simctl list devices available -j",
              "xcrun simctl boot %s" % new, self.build_for_testing_on(new)]),
        ]
        for case, old_state, new_state, after_pick in cases:
            with self.subTest(case):
                self.machine([IOS_26_5, IOS_27_0], [PRO], {
                    IOS_26_5["identifier"]: [device("iPhone 17 Pro", old, old_state)],
                    IOS_27_0["identifier"]: [device("iPhone 17 Pro", new, new_state)],
                })
                code, out, err, calls = self.run_test_sim()
                self.assertEqual(calls, ["xcrun simctl list devices available -j"] + after_pick)
                self.assertEqual((code, out, err), (65, "", self.failed_build()))

    def test_a_lowercase_sim_is_the_simulator_simctl_spells_in_capitals(self):
        udid = pick_udid(3)
        self.locks.append(udid)
        state = Path("/tmp/workout-verify-%s" % udid)
        state.mkdir(parents=True, exist_ok=True)
        app = subprocess.Popen(FIXTURE_APP, start_new_session=True)
        self.addCleanup(app.wait)
        self.addCleanup(app.kill)
        (state / "run").write_text("owner-579\n")
        (state / "pid").write_text("%d\n" % app.pid)
        self.machine([IOS_27_0], [PRO], {IOS_27_0["identifier"]: [device("iPhone 17 Pro", udid)]})
        code, out, err, calls = self.run_test_sim("--sim", udid.lower(), "unit")
        self.assertEqual((code, out, err), (75, "", (
            "a verify run owner-579 owns the app on %s (pid %d), last used 0 min ago; a claim takes it once it goes 60 min "
            "unused. If it is yours, rerun with VERIFY_RUN=owner-579 or run: SIM=%s VERIFY_RUN=owner-579 "
            "%s/.agents/skills/verify/verify.sh stop, else use another simulator\n") % (udid, app.pid, udid, self.checkout)),
            "the lock is keyed by the one spelling, so a case-sensitive /tmp cannot split it")
        self.assertEqual(calls, ["xcrun simctl list devices available -j"])

    def test_a_lowercase_sim_launches_on_the_simulator_simctl_spells_in_capitals(self):
        udid = pick_udid(3)
        self.machine([IOS_27_0], [PRO], {IOS_27_0["identifier"]: [device("iPhone 17 Pro", udid)]})
        code, out, err, calls = self.verify("launch", "session", SIM=udid.lower(), VERIFY_RUN="issue-579",
                                            STUB_BOOTSTATUS="0", STUB_BOOTED=udid)
        self.assertEqual((code, out, err), (0, "launched session as pid 4121 on %s\n"
                                               "app %s commit unknown (not built by verify.sh)\n"
                                               "evidence %s/issue-579\n" % (udid, digest(b"head\n"), self.evidence), ""),
                         "simctl lists it booted in capitals")
        self.assertEqual(calls, [
            "xcrun simctl list devices available -j",
            "plutil -extract WorkspacePath raw %s" % self.plist,
            "xcrun simctl list devices available -j",
            "xcrun simctl list devices available -j",
            "xcrun simctl boot %s" % udid,
            "xcrun simctl bootstatus %s -b" % udid,
            "xcrun simctl list devices booted",
            "xcrun simctl get_app_container %s com.sunnypatel.WorkoutTracker" % udid,
            "xcrun simctl install %s %s" % (udid, self.app),
            "xcrun simctl get_app_container %s com.sunnypatel.WorkoutTracker" % udid,
            "xcrun simctl spawn %s defaults read com.apple.keyboard.preferences AutomaticMinimizationEnabled" % udid,
            "xcrun simctl launch --terminate-running-process %s com.sunnypatel.WorkoutTracker -UITEST_FIXTURE "
            "-UITEST_SESSION -UITEST_FULL_BLOCK -UITEST_DISABLE_ANIMATIONS -UITEST_DISABLE_LIVE_ACTIVITIES" % udid,
            "axe describe-ui --udid %s" % udid,
        ])
