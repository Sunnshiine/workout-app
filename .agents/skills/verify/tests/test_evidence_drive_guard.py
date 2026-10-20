from evidence_support import *  # noqa: F401,F403
from evidence_lane import *  # noqa: F401,F403


KEYBOARD = ("AXe keyboard input hides the software keyboard in this app until its next launch (issue 700); "
            "the preference that would keep it hidden after that is reset\n")


class DriveGuard(Lane):
    def test_a_drive_command_refuses_another_live_runs_app(self):
        app = self.own_the_app("owner-1")
        for argv in [["tap", "-x", "5", "-y", "6"], ["hold", "weight-pill"], ["type", "245"], ["swipe", "up"],
                     ["shot", "01-before"], ["burst", "log-transition"], ["axe", "key", "40"]]:
            with self.subTest(argv=argv):
                self.assertEqual(self.verify(*argv, VERIFY_RUN="lane-1"), (75, "", (
                    "the app on {sim} belongs to run owner-1 (pid {pid}), not to lane-1, so this would drive another "
                    "run's app; launch yours first: SIM={sim} VERIFY_RUN=lane-1 {verify} launch <fixture>\n"
                ).format(sim=self.sim, pid=app.pid, verify=self.verify_path)))
                self.assertEqual(self.calls(), [], "nothing was driven or filmed")

    def test_a_refused_relaunch_of_the_same_run_drives_nothing_until_a_launch_of_it_succeeds(self):
        self.verify("build")
        self.verify("install", self.a)
        control = self.own_the_app("ui12")
        refusal = ("%s holds %s, and this launch would replace it with %s. To run the cached build: launch --at %s "
                   "session. To replace it: install, then launch.") % (
            self.sim, self.cached_build(b"v1\n", self.a), self.worktree_build(b"v2\n", self.b), self.a[:8])
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="ui12")[0], 65)
        for argv in [["tap", "-x", "5", "-y", "6"], ["shot", "02-head"], ["type", "245"]]:
            with self.subTest(argv=argv):
                self.assertEqual(self.verify(*argv, VERIFY_RUN="ui12"), (75, "", (
                    "the last launch of run ui12 on {sim} was refused, so this would drive whatever that refusal left "
                    "running ({refusal}); stop it, then launch again: SIM={sim} VERIFY_RUN=ui12 {verify} stop, then "
                    "SIM={sim} VERIFY_RUN=ui12 {verify} launch <fixture>\n"
                ).format(sim=self.sim, refusal=refusal, verify=self.verify_path)))
                self.assertEqual(self.calls(), [], "the control app is neither driven nor filmed as the head")
        self.assertRegex((self.evidence("main", "ui12") / "launches.txt").read_text(),
                         r"^\S+ launch refused: %s\n$" % re.escape(refusal))
        control.kill()
        control.wait()
        self.assertEqual(self.verify("install")[0], 0)
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6", VERIFY_RUN="ui12")[0], 75, "an install is not a launch")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="ui12")[0], 0)
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6", VERIFY_RUN="ui12"), (0, "", ""))

    def test_a_drive_that_names_no_run_is_refused_after_the_refused_relaunch_of_the_run_it_would_drive(self):
        self.verify("build")
        self.verify("install", self.a)
        self.own_the_app("ui12")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="ui12")[0], 65)
        for argv in [["shot", "02-head"], ["tap", "-x", "5", "-y", "6"]]:
            with self.subTest(argv=argv):
                code, out, err = self.verify(*argv)
                self.assertEqual((code, out), (75, ""))
                self.assertRegex(err, r"^the last launch of run ui12 on %s was refused" % self.sim)
                self.assertEqual(self.calls(), [], "the stale app is neither driven nor filmed into ui12's evidence")

    def test_a_cache_build_that_fails_refuses_the_run_until_a_launch_of_it_succeeds(self):
        self.verify("build")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="r1")[0], 0)
        refusal = "app on %s unchanged: %s; this launch wanted %s from the app cache, and its build failed" % (
            self.sim, self.worktree_build(b"v2\n", self.b), self.a[:8])
        code, out, err = self.verify("launch", "--at", self.a, "session", VERIFY_RUN="r1", STUB_BUILD_FAIL="1")
        self.assertEqual((code, out, err.splitlines()[-1]), (65, "", refusal))
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6", VERIFY_RUN="r1")[0], 75)
        self.assertRegex((self.evidence("main", "r1") / "launches.txt").read_text(),
                         r"\n\S+ launch refused: %s\n$" % re.escape(refusal))

    def test_a_cache_build_that_never_gets_a_build_slot_refuses_the_run_until_a_launch_of_it_succeeds(self):
        self.verify("build")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="r1")[0], 0)
        refusal = "app on %s unchanged: %s; this launch wanted %s from the app cache" % (
            self.sim, self.worktree_build(b"v2\n", self.b), self.a[:8])
        code, out, err = self.verify("launch", "--at", self.a, "session", VERIFY_RUN="r1", WORKOUT_MEM_FLOOR="25")
        self.assertEqual((code, out, err.splitlines()[-1]), (75, "", refusal))
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6", VERIFY_RUN="r1")[0], 75)

    def test_a_drive_that_names_no_run_is_refused_after_a_launch_that_named_none_was_refused(self):
        self.verify("build")
        self.assertEqual(self.verify("launch", "session")[0], 0)
        run = (Path("/tmp/workout-verify-%s" % self.sim) / "run").read_text().strip()
        refusal = "app on %s unchanged: %s; this launch wanted %s from the app cache, and its build failed" % (
            self.sim, self.worktree_build(b"v2\n", self.b), self.a[:8])
        self.assertEqual(self.verify("launch", "--at", self.a, "session", STUB_BUILD_FAIL="1")[0], 65)
        for argv in [["tap", "-x", "5", "-y", "6"], ["shot", "02-head"]]:
            with self.subTest(argv=argv):
                self.assertEqual(self.verify(*argv), (75, "", (
                    "the last launch of run {run} on {sim} was refused, so this would drive whatever that refusal "
                    "left running ({refusal}); stop it, then launch again: SIM={sim} {verify} stop, then "
                    "SIM={sim} {verify} launch <fixture>\n"
                ).format(run=run, sim=self.sim, refusal=refusal, verify=self.verify_path)))
                self.assertEqual(self.calls(), [], "the app the refusal left is neither driven nor filmed")
        self.assertRegex((self.evidence("main", run) / "launches.txt").read_text(),
                         r"\n\S+ launch refused: %s\n$" % re.escape(refusal))
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="r2")[0], 0)
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6"), (0, "", ""), "any launch that succeeds clears it")

    def test_a_drive_that_names_no_run_is_refused_after_the_first_launch_on_the_simulator_was_refused(self):
        self.assertEqual(self.verify("launch", "session")[0], 65)
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6")[0], 75)
        self.assertEqual(self.calls(), [])

    def test_a_refused_launch_that_named_no_run_does_not_stop_a_named_owner_driving_unnamed(self):
        self.verify("build")
        self.assertEqual(self.verify("launch", "session")[0], 0)
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="owner-1")[0], 0)
        self.assertEqual(self.verify("launch", "--at", self.a, "session", STUB_BUILD_FAIL="1")[0], 65)
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6", VERIFY_RUN="owner-1"), (0, "", ""))
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6"), (0, "", ""))

    def test_a_named_launch_that_starts_but_never_comes_up_is_not_held_to_an_earlier_unnamed_refusal(self):
        self.assertEqual(self.verify("launch", "session")[0], 65)
        self.verify("build")
        (self.tmp / "describe-ui.json").write_text(MINI.replace('"pid": 4121', '"pid": 99999999'))
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="owner-1")[0], 70)
        (self.tmp / "describe-ui.json").write_text(MINI)
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6"), (0, "", ""))

    def test_a_refused_install_blocks_no_drive(self):
        self.verify("build")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="r1")[0], 0)
        self.assertEqual(self.verify("install", self.a, VERIFY_RUN="r1", STUB_BUILD_FAIL="1")[0], 65)
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6", VERIFY_RUN="r1"), (0, "", ""))
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6"), (0, "", ""))

    def test_a_run_refused_because_another_runs_app_is_alive_is_not_told_to_stop_it(self):
        self.verify("build")
        app = self.own_the_app("owner-1")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1")[0], 75)
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6", VERIFY_RUN="lane-1"), (75, "", (
            "the app on {sim} belongs to run owner-1 (pid {pid}), not to lane-1, so this would drive another "
            "run's app; launch yours first: SIM={sim} VERIFY_RUN=lane-1 {verify} launch <fixture>\n"
        ).format(sim=self.sim, pid=app.pid, verify=self.verify_path)))

    def test_another_runs_refused_launch_does_not_stop_the_owner(self):
        self.verify("build")
        self.own_the_app("owner-1")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1")[0], 75)
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6", VERIFY_RUN="owner-1"), (0, "", ""))

    def test_the_owner_an_unnamed_caller_and_a_dead_owner_still_drive(self):
        self.own_the_app("owner-1")
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6", VERIFY_RUN="owner-1"), (0, "", ""))
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6"), (0, "", ""))
        (Path("/tmp/workout-verify-%s" % self.sim) / "pid").write_text("99999999\n")
        self.assertEqual(self.verify("tap", "-x", "5", "-y", "6", VERIFY_RUN="lane-1"), (0, "", ""))
        self.assertEqual(self.calls(), ["axe tap --udid %s --wait-timeout 3 -x 5 -y 6" % self.sim])


class KeyboardReset(Lane):
    RESET = "xcrun simctl spawn %s defaults write com.apple.keyboard.preferences AutomaticMinimizationEnabled -bool false"
    READ = "xcrun simctl spawn %s defaults read com.apple.keyboard.preferences AutomaticMinimizationEnabled"

    def minimized(self, value):
        (self.tmp / "minimization").write_text(value)

    def test_launch_resets_a_minimized_keyboard_before_it_starts_the_app_and_says_so(self):
        self.verify("build")
        self.minimized("1\n")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1"), (
            0, self.launched(self.worktree_build(b"v2\n", self.b)),
            "AutomaticMinimizationEnabled was 1 on %s, which hides the software keyboard (issue 700); "
            "this launch reset it to 0\n" % self.sim))
        calls = self.calls()
        start = [index for index, call in enumerate(calls) if call.startswith("xcrun simctl launch")][0]
        self.assertEqual(calls[start - 2:start], [self.READ % self.sim, self.RESET % self.sim])
        self.assertEqual((self.tmp / "minimization").read_text(), "0\n")

    def test_launch_leaves_a_keyboard_preference_that_is_0_or_unset_alone(self):
        self.verify("build")
        for value in [None, "0\n"]:
            with self.subTest(value=value):
                if value:
                    self.minimized(value)
                code, _, err = self.verify("launch", "session", VERIFY_RUN="lane-1")
                self.assertEqual((code, err), (0, ""))
                self.assertIn(self.READ % self.sim, self.calls())
                self.assertNotIn(self.RESET % self.sim, self.calls())

    def test_doctor_fails_a_minimized_keyboard_and_passes_one_that_is_not(self):
        self.verify("build")
        self.verify("launch", "session", VERIFY_RUN="lane-1")
        self.minimized("1\n")
        code, out, _ = self.verify("doctor")
        self.assertEqual((code, out.splitlines()[-1]), (1, (
            "FAIL AutomaticMinimizationEnabled is 1 on {sim}, so a focused field shows no software keyboard "
            "(issue 700); the next launch resets it (run: {verify} launch <fixture>)").format(
                sim=self.sim, verify=self.verify_path)))
        self.minimized("0\n")
        self.assertEqual(self.verify("doctor")[1].splitlines()[-1],
                         "ok   AutomaticMinimizationEnabled is not 1 on %s" % self.sim)

    def test_type_resets_the_keyboard_preference_after_axe_and_keeps_axes_status(self):
        self.assertEqual(self.verify("type", "245", STUB_AXE_EXIT="3"), (3, "", KEYBOARD))
        self.assertEqual(self.calls(), ["axe type --udid %s --stdin" % self.sim, self.RESET % self.sim])

    def test_an_axe_keyboard_verb_resets_it_too_and_any_other_verb_does_not(self):
        for verb in [["key", "42"], ["key-sequence", "--keycodes", "42,42"], ["key-combo", "--modifiers", "227", "--key", "4"],
                     ["type", "245"]]:
            with self.subTest(verb=verb[0]):
                self.assertEqual(self.verify("axe", *verb), (0, "", KEYBOARD))
                self.assertEqual(self.calls(), ["axe %s --udid %s" % (" ".join(verb), self.sim), self.RESET % self.sim])
        self.assertEqual(self.verify("axe", "tap", "-x", "5", "-y", "6", STUB_AXE_EXIT="4"), (4, "", ""))
        self.assertEqual(self.calls(), ["axe tap -x 5 -y 6 --udid %s" % self.sim])
