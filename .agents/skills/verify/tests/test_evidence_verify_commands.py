from evidence_support import *  # noqa: F401,F403
from evidence_lane import *  # noqa: F401,F403


class VerifyDiff(unittest.TestCase):
    def setUp(self):
        self.run = "selftest-%d" % os.getpid()
        self.evidence = Path(tempfile.mkdtemp())
        self.dir = self.evidence / self.run
        self.dir.mkdir(parents=True, exist_ok=True)
        for offset, name in enumerate(["01-before", "02-after-log"]):
            shutil.copy(FIXTURES / ("%s.tree.txt" % name), self.dir / ("%s.tree.txt" % name))
            os.utime(self.dir / ("%s.tree.txt" % name), (offset, offset))

    def tearDown(self):
        shutil.rmtree(self.evidence, ignore_errors=True)

    def test_verify_diff_maps_shot_names_onto_the_run(self):
        code, out, err = verify_sh("diff", "01-before", "02-after-log", run=self.run, evidence=self.evidence)
        self.assertEqual(code, 0, err)
        self.assertEqual(out, (FIXTURES / "01-before--02-after-log.diff.txt").read_text())

    def test_verify_diff_lists_the_shots_when_a_name_is_wrong(self):
        code, out, err = verify_sh("diff", "01-before", "03-typo", run=self.run, evidence=self.evidence)
        self.assertEqual(code, 1)
        self.assertIn("shots: 01-before 02-after-log", err, "capture order, so the agent can pick again")

    def test_a_png_whose_tree_never_landed_is_not_a_shot(self):
        (self.dir / "03-half.png").write_bytes(b"png")
        code, out, err = verify_sh("diff", "01-before", "03-half", run=self.run, evidence=self.evidence)
        self.assertEqual(code, 1)
        self.assertIn("shots: 01-before 02-after-log", err, "a shot exists when its tree exists")

    def test_a_run_name_that_is_not_a_plain_name_is_refused(self):
        for run in ["../escape", "two words", "-x"]:
            code, out, err = verify_sh("diff", "01-before", "02-after-log", run=run)
            self.assertEqual(code, 2, "%r must be refused before it becomes a path: %s" % (run, err))

    def test_launch_refuses_an_unknown_fixture_before_any_simulator_is_touched(self):
        code, out, err = verify_sh("launch", "no-such-fixture", run=self.run, sim="NO-SUCH-DEVICE")
        self.assertEqual(code, 2, err)
        self.assertIn("unknown fixture: no-such-fixture", err)
        self.assertEqual(out, "", "nothing was launched")

    def test_sheet_refuses_an_argument_it_would_ignore(self):
        code, out, err = verify_sh("sheet", "02-after-log", run=self.run)
        self.assertEqual(code, 2, "sheet tiles the whole run; a stray name must not look accepted: %s" % err)
        self.assertEqual(out, "")

    def test_tap_says_usage_for_a_flag_left_without_its_value(self):
        for argv in [["tap", "--id"], ["tap", "--wait-timeout"], ["tap", "--label", "Save", "--wait-timeout"]]:
            code, out, err = verify_sh(*argv, run=self.run, sim="NO-SUCH-DEVICE")
            self.assertEqual(code, 2, "%s must print usage, not die on its own shift: %s" % (argv, err))
            self.assertIn("Usage:", err)

    def test_tap_by_id_refuses_a_wait_timeout_it_cannot_count(self):
        code, out, err = verify_sh(
            "tap", "--id", "weight-pill", "--wait-timeout", "1.5", run=self.run, sim="NO-SUCH-DEVICE")
        self.assertEqual(code, 2, "the poll budget is counted in whole seconds: %s" % err)
        self.assertIn("whole seconds", err)
        self.assertEqual(out, "", "refused before any simulator is touched")

    def test_shot_refuses_a_name_that_could_collide(self):
        for name in ["_sheet", "a.burst", "-x"]:
            code, out, err = verify_sh("shot", name, run=self.run)
            self.assertEqual(code, 2, "%s must be refused before any simulator is touched: %s" % (name, err))


FAKE_AXE = """#!/bin/sh
printf '%s\\n' "$*" >> "{dir}/calls"
case $1 in
  describe-ui)
    case "$*" in
      *--point*) cat "{dir}/point.json" ;;
      *) cat "{dir}/describe-ui.json" ;;
    esac ;;
  tap) echo "Tap completed" ;;
  *) exit 64 ;;
esac
"""
WITH_GEAR = json.loads(MINI)
WITH_GEAR[0]["pid"] = int(APP)
WITH_GEAR[0]["children"].append(json.loads(GEAR_UP))
WITH_GEAR = json.dumps(WITH_GEAR)


class VerifyTap(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        skill = link_checkout(self.root)
        axe = self.root / ".build" / "verify" / "node_modules" / "xcodebuildmcp" / "bundled" / "axe"
        axe.parent.mkdir(parents=True)
        axe.write_text(FAKE_AXE.replace("{dir}", str(self.root)))
        axe.chmod(0o755)
        self.verify = skill / "verify.sh"
        self.sim = "TAP-TEST-%d" % os.getpid()

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def tap(self, tree, *args, point=None):
        (self.root / "describe-ui.json").write_text(tree)
        if point is not None:
            (self.root / "point.json").write_text(point)
        env = dict(os.environ, SIM=self.sim)
        env.pop("VERIFY_RUN", None)
        done = subprocess.run(
            [str(self.verify), "tap"] + list(args), cwd=str(self.root), env=env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
        )
        calls = self.root / "calls"
        return done.returncode, done.stdout, done.stderr, calls.read_text().splitlines() if calls.exists() else []

    def test_a_label_tree_py_refuses_is_never_tapped(self):
        self.assertEqual(self.tap(MINI, "--label", "Farmer Carry", "--wait-timeout", "0"),
                         (1, "", "off-screen: swipe it into view before tapping\n", ["describe-ui --udid %s" % self.sim]))

    def test_a_label_tree_py_resolves_is_tapped_once_at_its_centre(self):
        row = {"role": "AXButton", "AXUniqueId": "settings-developer-tools-row", "AXLabel": "Developer Tools",
               "pid": 890, "frame": {"x": 16, "y": 570, "width": 370, "height": 52}}
        self.assertEqual(self.tap(SETTINGS, "--label", "Developer Tools", "--wait-timeout", "0", point=json.dumps(row)),
                         (0, "Tap completed\n", "", ["describe-ui --udid %s" % self.sim,
                                                      "describe-ui --udid %s --point 201,596" % self.sim,
                                                      "tap --udid %s -x 201 -y 596" % self.sim]))

    def test_a_target_on_top_at_its_centre_is_tapped_after_the_point_read(self):
        self.assertEqual(self.tap(WITH_GEAR, "--id", "session-controls-settings-button", "--wait-timeout", "0",
                                  point=GEAR_UP),
                         (0, "Tap completed\n", "", ["describe-ui --udid %s" % self.sim,
                                                      "describe-ui --udid %s --point 356,87" % self.sim,
                                                      "tap --udid %s -x 356 -y 87" % self.sim]))

    def test_a_covered_target_is_never_tapped(self):
        self.assertEqual(self.tap(WITH_GEAR, "--id", "session-controls-settings-button", "--wait-timeout", "0",
                                  point=GEAR_HIDDEN),
                         (1, "", GEAR_COVERED, ["describe-ui --udid %s" % self.sim,
                                                "describe-ui --udid %s --point 356,87" % self.sim]),
                         "the tree still had the gear; the point read found the header text in its place")

    def test_a_row_half_below_the_fold_is_read_and_tapped_in_its_visible_half(self):
        tree = on_screen_of_402x874(HALF_ROW)
        self.assertEqual(self.tap(tree, "--id", "half-row", "--wait-timeout", "0", point=json.dumps(dict(HALF_ROW, pid=1))),
                         (0, "Tap completed\n", "", ["describe-ui --udid %s" % self.sim,
                                                      "describe-ui --udid %s --point 179,862" % self.sim,
                                                      "tap --udid %s -x 179 -y 862" % self.sim]))
        self.assertEqual(self.tap(tree, "--id", "half-row", "--wait-timeout", "0", point="[]")[:3],
                         (1, "", "covered: at 179,862 the screen has nothing, not AXButton half-row" + COVERED),
                         "the note names the point read, not the frame centre at y 876")

    def launched(self, pid):
        state = Path("/tmp/workout-verify-%s" % self.sim)
        state.mkdir(exist_ok=True)
        self.addCleanup(shutil.rmtree, str(state), True)
        (state / "pid").write_text(pid + "\n")

    def test_a_prompt_from_another_process_over_the_launched_app_is_never_tapped(self):
        self.launched(APP)
        prompt = {"role": "AXButton", "AXLabel": "Allow", "pid": 111, "frame": {"x": 0, "y": 0, "width": 402, "height": 874}}
        self.assertEqual(self.tap(WITH_GEAR, "--id", "session-controls-settings-button", "--wait-timeout", "0",
                                  point=json.dumps(prompt)),
                         (1, "", "covered: at 356,87 the screen has AXButton Allow @0,0 402x874, "
                                 "not AXButton session-controls-settings-button" + COVERED,
                          ["describe-ui --udid %s" % self.sim, "describe-ui --udid %s --point 356,87" % self.sim]))

    def test_a_home_screen_icon_is_tapped_by_the_tree_alone_while_the_app_is_away_and_says_so(self):
        self.launched("7427")
        misread = (FIXTURES / "home-screen-icon-point.describe-ui.json").read_text()
        self.assertEqual(self.tap(HOME_SCREEN, "--id", "WorkoutTracker", "--wait-timeout", "0", point=misread),
                         (0, "Tap completed\n",
                          "not checked for cover: pid 90129 is in front, not pid 7427 that launch started, "
                          "so this tap goes by the tree alone\n",
                          ["describe-ui --udid %s" % self.sim, "tap --udid %s -x 62 -y 336" % self.sim]),
                         "live-activity.md reopens the app this way; the springboard's point read is not its tree")

    def test_with_no_launch_pid_the_check_holds_on_the_home_screen_too(self):
        misread = (FIXTURES / "home-screen-icon-point.describe-ui.json").read_text()
        self.assertEqual(self.tap(HOME_SCREEN, "--id", "WorkoutTracker", "--wait-timeout", "0", point=misread),
                         (1, "", "covered: at 62,336 the screen has AXButton Contacts @211,188 72x91, "
                                 "not AXButton WorkoutTracker" + COVERED,
                          ["describe-ui --udid %s" % self.sim, "describe-ui --udid %s --point 62,336" % self.sim]),
                         "after stop, or for an app launch did not start, nothing tells the Home Screen apart")

    def test_the_launched_app_in_front_is_checked_and_prints_no_note(self):
        self.launched(APP)
        self.assertEqual(self.tap(WITH_GEAR, "--id", "session-controls-settings-button", "--wait-timeout", "0",
                                  point=GEAR_HIDDEN),
                         (1, "", GEAR_COVERED, ["describe-ui --udid %s" % self.sim,
                                                "describe-ui --udid %s --point 356,87" % self.sim]))

    def test_a_coordinate_tap_still_goes_straight_to_axe(self):
        self.assertEqual(self.tap(MINI, "-x", "5", "-y", "6"),
                         (0, "Tap completed\n", "", ["tap --udid %s --wait-timeout 3 -x 5 -y 6" % self.sim]),
                         "no element is resolved, so it reports success whatever is under 5,6")

    def test_a_label_without_its_text_or_beside_an_id_is_usage(self):
        for argv in [["--label"], ["--id", "settings-sign-out-button", "--label", "Sign Out"]]:
            with self.subTest(argv=argv):
                code, out, err, calls = self.tap(SETTINGS, *argv)
                self.assertEqual((code, out, calls), (2, "", []), err)
                self.assertIn("Usage:", err)

    def test_a_label_refuses_a_wait_timeout_it_cannot_count(self):
        self.assertEqual(self.tap(SETTINGS, "--label", "Developer Tools", "--wait-timeout", "1.5"),
                         (2, "", "--wait-timeout with --id or --label is whole seconds: 1.5\n", []))


class VerifyStop(unittest.TestCase):
    def setUp(self):
        self.owner = "owner-%d" % os.getpid()
        self.next = "next-%d" % os.getpid()
        self.sim = "NO-SUCH-DEVICE-%d" % os.getpid()
        self.state = Path("/tmp/workout-verify-%s" % self.sim)
        self.state.mkdir(parents=True, exist_ok=True)
        (self.state / "run").write_text("%s\n" % self.owner)
        (self.state / "pid").write_text("99999999\n")
        self.evidence = Path(tempfile.mkdtemp())

    def tearDown(self):
        shutil.rmtree(self.state, ignore_errors=True)
        shutil.rmtree(self.evidence, ignore_errors=True)

    def stop(self, run):
        return verify_sh("stop", run=run, sim=self.sim, evidence=self.evidence)

    def launched_with_live_activities(self):
        (self.state / "args").write_text("-UITEST_FIXTURE -UITEST_SESSION -UITEST_DISABLE_ANIMATIONS\n")

    def test_stop_refuses_to_end_a_run_that_is_not_the_callers(self):
        app = subprocess.Popen(FIXTURE_APP, start_new_session=True)
        self.addCleanup(app.wait)
        self.addCleanup(app.kill)
        (self.state / "pid").write_text("%d\n" % app.pid)
        code, out, err = self.stop("issue-660")
        self.assertEqual(code, 75, "the code launch already uses for a simulator another run owns")
        self.assertIn(self.owner, err, "whose app it is about to end")
        self.assertIn("VERIFY_RUN=%s" % self.owner, err, "the override, spelled out")
        self.assertEqual(out, "", "nothing was terminated")
        self.assertTrue((self.state / "pid").exists(), "the owner keeps the pid it recorded")

    def test_stop_ends_the_callers_own_run(self):
        self.launched_with_live_activities()
        code, out, err = self.stop(self.owner)
        self.assertEqual(code, 0, err)
        self.assertIn("could not uninstall on %s" % self.sim, err, "its own stop goes on to the uninstall")
        self.assertFalse((self.state / "pid").exists(), "its own stop clears the pid it recorded")

    def test_stop_refuses_to_uninstall_a_live_activity_run_that_is_not_the_callers(self):
        self.launched_with_live_activities()
        code, out, err = self.stop(self.next)
        self.assertEqual(code, 75, "its app died, but stop would still uninstall it and end the run's Live Activity")
        self.assertIn("VERIFY_RUN=%s" % self.owner, err)
        self.assertTrue((self.state / "args").exists(), "the owner's own stop can still uninstall")

    def test_a_pid_another_process_reused_is_forgotten_not_terminated(self):
        (self.state / "pid").write_text("%d\n" % os.getpid())
        (self.state / "args").write_text("-UITEST_FIXTURE -UITEST_SESSION -UITEST_DISABLE_LIVE_ACTIVITIES\n")
        code, out, err = self.stop(self.owner)
        self.assertEqual(
            (code, out, err), (0, "", ""),
            "the pid is live but not a fixture launch, so simctl terminate would exit 3 or end someone else's app (#728)",
        )
        self.assertFalse((self.state / "pid").exists(), "a stale pid file left behind fails every later stop")
        self.assertFalse((self.state / "args").exists())

    def test_a_dead_pid_that_stop_would_only_forget_is_not_refused(self):
        (self.state / "args").write_text("-UITEST_FIXTURE -UITEST_SESSION -UITEST_DISABLE_LIVE_ACTIVITIES\n")
        code, out, err = self.stop(self.next)
        self.assertEqual((code, out, err), (0, "", ""))
        self.assertFalse((self.state / "pid").exists(), "no app and no Live Activity, so nothing to protect")

    def test_a_dead_pid_with_no_args_is_not_refused(self):
        code, out, err = self.stop(self.next)
        self.assertEqual(
            (code, out, err), (0, "", ""),
            "a launch cut off after its pid write recorded no opt-in, so no stop would uninstall this app",
        )
        self.assertFalse((self.state / "pid").exists())

    def test_after_the_owners_stop_the_next_runs_stop_is_not_refused(self):
        code, out, err = self.stop(self.owner)
        self.assertEqual(code, 0, err)
        code, out, err = self.stop(self.next)
        self.assertEqual(code, 0, err)
        self.assertEqual(out, "nothing launched by this tool on %s\n" % self.sim)

    def test_an_unnamed_diff_after_stop_still_reads_the_runs_shots(self):
        evidence = self.evidence / self.owner
        evidence.mkdir(parents=True, exist_ok=True)
        for name in ["01-before", "02-after-log"]:
            shutil.copy(FIXTURES / ("%s.tree.txt" % name), evidence / ("%s.tree.txt" % name))
        self.stop(self.owner)
        code, out, err = verify_sh("diff", "01-before", "02-after-log", run=None, sim=self.sim, evidence=self.evidence)
        self.assertEqual(code, 0, err)
        self.assertEqual(out, (FIXTURES / "01-before--02-after-log.diff.txt").read_text())

    def test_stop_on_a_simulator_no_run_has_claimed_is_not_refused(self):
        (self.state / "run").unlink()
        self.launched_with_live_activities()
        code, out, err = self.stop("issue-660")
        self.assertEqual(code, 0, err)
        self.assertIn("could not uninstall on %s" % self.sim, err, "an app no run has claimed is nobody's")

    def test_stop_without_a_run_name_is_still_allowed(self):
        self.launched_with_live_activities()
        code, out, err = self.stop(None)
        self.assertEqual(code, 0, err)
        self.assertIn("could not uninstall on %s" % self.sim, err)
        self.assertFalse(
            (self.state / "pid").exists(),
            "with no VERIFY_RUN the guard has nothing to compare against, so it steps aside and "
            "the ordinary single drive keeps working",
        )
