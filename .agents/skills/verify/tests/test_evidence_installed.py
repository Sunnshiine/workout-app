from evidence_support import *  # noqa: F401,F403
from evidence_lane import *  # noqa: F401,F403


def app_hash(app):
    lines = "".join("%s  ./%s\n" % (hashlib.sha256(f.read_bytes()).hexdigest(), f.relative_to(app))
                    for f in sorted(app.rglob("*")) if f.is_file() and f.name != "verify-stamp")
    return hashlib.sha256(lines.encode()).hexdigest()


class InstalledIdentity(Lane):
    def test_build_stamps_the_app_and_launch_prints_its_hash_and_commit(self):
        self.assertEqual(self.verify("build"), (0, "built %s\n%s\n" % (self.built, self.worktree_build(b"v2\n", self.b)), ""))
        self.assertEqual((self.built / "verify-stamp").read_text(), "commit=%s\ndirty=0\norigin=%s\ncode_sha256=%s\n"
                         % (self.b, self.checkout, bundle_hash(b"v2\n")))
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1"),
                         (0, self.launched(self.worktree_build(b"v2\n", self.b)), ""))
        self.assertRegex((self.evidence("main", "lane-1") / "launches.txt").read_text(),
                         r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d session %s on %s from %s\n$" % (
                             re.escape(self.worktree_build(b"v2\n", self.b)), self.sim, re.escape(str(self.checkout))),
                         "the evidence names its binary after the worktree and the simulator are gone")

    def test_a_claims_end_restarts_the_simulators_idle_clock_however_the_command_ends(self):
        self.verify("build")
        lock = Path("/tmp/workout-verify-%s/lock" % self.sim)
        for ending, env, code in [("a launch", {}, 0), ("a refused install", {"STUB_INSTALL_FAIL": "1"}, 70),
                                  ("a failed boot wait", {"STUB_BOOTSTATUS": "1"}, 70)]:
            self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1", STUB_BACKDATE=str(lock), **env)[0], code)
            self.assertLess(time.time() - lock.stat().st_mtime, 60, "%s restarts the idle clock its claim began" % ending)

    def test_only_an_edit_to_what_the_app_compiles_marks_the_build_dirty(self):
        (self.checkout / "decisions.tsv").write_text("an untracked file at the root\n")
        self.assertEqual(self.verify("build")[1].splitlines()[1], self.worktree_build(b"v2\n", self.b))
        self.edit("v3\n")
        self.assertEqual(self.verify("build")[1].splitlines()[1], self.worktree_build(b"v3\n", self.b, "-dirty"))

    def test_a_stamp_whose_code_hash_no_longer_matches_reads_commit_unknown(self):
        self.verify("build")
        (self.built / "WorkoutTracker.debug.dylib").write_bytes(b"rebuilt by Xcode\n")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1"), (0, self.launched(
            "app %s commit unknown (not built by verify.sh)" % digest(b"rebuilt by Xcode\n")), ""),
            "the hash is the identity; a stamp that does not describe these bytes vouches for nothing")

    def test_a_runs_own_relaunch_that_would_replace_a_cached_build_refuses_before_it_takes_anything_over(self):
        self.verify("build")
        self.assertEqual(self.verify("install", self.a)[0], 0)
        app = self.own_the_app("ui12")
        (Path("/tmp/workout-verify-%s" % self.sim) / "args").write_text("-UITEST_FIXTURE -UITEST_SESSION\n")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="ui12"), (65, "", (
            "{sim} holds {cached}, and this launch would replace it with {wanted}. To run the cached build: launch --at "
            "{a8} session. To replace it: install, then launch.\n").format(
                sim=self.sim, cached=self.cached_build(b"v1\n", self.a), wanted=self.worktree_build(b"v2\n", self.b),
                a8=self.a[:8])), "a run that had Live Activities on is not uninstalled, and no takeover is announced")
        self.assertEqual([call for call in self.calls() if " install" in call or "uninstall" in call], [])
        self.assertIsNone(app.poll(), "the run's app still runs")

    def test_a_lock_refusal_names_the_app_it_left_installed_and_the_one_it_wanted(self):
        self.verify("build")
        self.assertEqual(self.verify("install", self.a)[0], 0)
        app = self.own_the_app("owner-1")
        code, out, err = self.verify("launch", "session", VERIFY_RUN="lane-1")
        self.assertEqual((code, out), (75, ""), err)
        self.assertEqual(err, (
            "a verify run owner-1 owns the app on {sim} (pid {pid}), last used 0 min ago; a claim takes it once it goes "
            "60 min unused. If it is yours, rerun with VERIFY_RUN=owner-1 or run: SIM={sim} VERIFY_RUN=owner-1 "
            "{checkout}/.agents/skills/verify/verify.sh stop, else use another simulator\n"
            "app on {sim} unchanged: {installed}; this launch wanted {wanted}\n"
        ).format(sim=self.sim, pid=app.pid, checkout=self.checkout, installed=self.cached_build(b"v1\n", self.a),
                 wanted=self.worktree_build(b"v2\n", self.b)), "a driver that drops the first line still reads the second")
        self.assertNotIn("xcrun simctl install", " ".join(self.calls()))

    def test_installed_bytes_that_differ_from_the_build_after_a_reinstall_exit_70_naming_both(self):
        self.verify("build")
        tampered = "app %s commit unknown (not built by verify.sh)" % digest(b"v2\nx")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1", STUB_TAMPER="1"), (70, "", (
            "after simctl install, {sim} holds {tampered}, not {wanted}; uninstalling it and installing once more\n"
            "after simctl install, {sim} holds {tampered}, not {wanted} that this launch installed from {built}\n"
        ).format(sim=self.sim, tampered=tampered, wanted=self.worktree_build(b"v2\n", self.b), built=self.built)))
        self.assertEqual([c for c in self.calls() if c.startswith(("xcrun simctl install", "xcrun simctl uninstall"))], [
            "xcrun simctl install %s %s" % (self.sim, self.built),
            "xcrun simctl uninstall %s com.sunnypatel.WorkoutTracker" % self.sim,
            "xcrun simctl install %s %s" % (self.sim, self.built),
        ], "one reinstall, then the refusal")
        self.assertNotIn("xcrun simctl launch", " ".join(self.calls()), "the wrong bytes are never launched")

    def test_an_install_that_leaves_the_old_bytes_is_uninstalled_and_installed_once_more(self):
        self.verify("build")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1")[0], 0)
        self.edit("v3\n")
        self.verify("build")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1", STUB_STALE_INSTALL="1"), (
            0, self.launched(self.worktree_build(b"v3\n", self.b, "-dirty")),
            "after simctl install, %s holds app %s commit %s (an earlier build of this worktree), not %s; uninstalling it "
            "and installing once more\n" % (self.sim, digest(b"v2\n"), self.b[:8],
                                             self.worktree_build(b"v3\n", self.b, "-dirty"))))
        self.assertEqual(self.verify("doctor")[1].splitlines()[1],
                         "ok   installed %s" % self.worktree_build(b"v3\n", self.b, "-dirty"))

    def test_a_file_outside_the_dylib_is_part_of_the_apps_identity(self):
        self.verify("build")
        self.verify("launch", "session", VERIFY_RUN="lane-1")
        (self.built / "Assets.car").write_bytes(b"a new colour\n")
        self.assertEqual(self.verify("doctor")[1].splitlines()[1], (
            "FAIL installed app %s commit %s (an earlier build of this worktree) is not this worktree's build, "
            "app %s commit unknown (run: %s install)") % (digest(b"v2\n"), self.b[:8],
                                                          app_hash(self.built)[:12], self.verify_path))

    def test_a_failed_simctl_install_says_so_once_and_names_what_is_there(self):
        self.verify("build")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1", STUB_INSTALL_FAIL="1"), (70, "", (
            "simctl install failed, so %s holds nothing installed, not %s\n") % (self.sim, self.worktree_build(b"v2\n", self.b))))

    def test_at_after_the_fixture_is_refused_instead_of_passed_to_the_app(self):
        self.assertEqual(self.verify("launch", "session", "--at", self.a, VERIFY_RUN="lane-1"),
                         (2, "", "--at goes before the fixture: launch --at COMMIT session\n"))
        self.assertEqual(self.calls(), [])

    def test_a_sim_no_simulator_answers_to_is_refused_before_any_build(self):
        self.assertEqual(self.verify("build", STUB_AVAILABLE="SOMEONE-ELSE"), (2, "", (
            "no available simulator %s; xcrun simctl list devices available lists them\n") % self.sim))
        self.assertEqual(self.calls(), ["xcrun simctl list devices available -j"])

    def test_a_bare_launch_over_a_cached_build_refuses_and_launch_at_runs_it(self):
        self.verify("build")
        self.assertEqual(self.verify("install", self.a[:8])[:2], (0, self.cached_build(b"v1\n", self.a) + "\n"))
        cached, head = self.cached_build(b"v1\n", self.a), self.worktree_build(b"v2\n", self.b)
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1"), (65, "", (
            "{sim} holds {cached}, and this launch would replace it with {head}. To run the cached build: "
            "launch --at {a8} session. To replace it: install, then launch.\n"
        ).format(sim=self.sim, cached=cached, head=head, a8=self.a[:8])))
        self.assertNotIn("xcrun simctl install", " ".join(self.calls()), "the control build stays installed")
        self.assertEqual(self.verify("launch", "--at", self.a[:8], "session", VERIFY_RUN="lane-1"), (0, self.launched(
            "%s; this worktree's build is app %s commit %s" % (cached, digest(b"v2\n"), self.b[:8])), ""))
        self.assertEqual(self.verify("install"), (0, "replaced %s\n%s\n" % (cached, head), ""),
                         "the head phase reinstalls this worktree's build on purpose")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1"), (0, self.launched(head), ""))

    def test_a_refused_animated_launch_hints_the_animated_launch_of_the_cached_build(self):
        self.verify("build")
        self.verify("install", self.a[:8])
        cached, head = self.cached_build(b"v1\n", self.a), self.worktree_build(b"v2\n", self.b)
        self.assertEqual(self.verify("launch", "--animated", "session", VERIFY_RUN="lane-1"), (65, "", (
            "{sim} holds {cached}, and this launch would replace it with {head}. To run the cached build: "
            "launch --at {a8} --animated session. To replace it: install, then launch.\n"
        ).format(sim=self.sim, cached=cached, head=head, a8=self.a[:8])))


class LaunchAnimated(Lane):
    def setUp(self):
        super().setUp()
        self.verify("build")

    def launch_call(self, flags):
        return ("xcrun simctl launch --terminate-running-process %s com.sunnypatel.WorkoutTracker -UITEST_FIXTURE "
                "-UITEST_SESSION -UITEST_FULL_BLOCK %s" % (self.sim, flags))

    def test_an_animated_launch_leaves_motion_on_and_says_so(self):
        head = self.worktree_build(b"v2\n", self.b)
        self.assertEqual(self.verify("launch", "--animated", "session", VERIFY_RUN="lane-1"), (0, (
            "launched session as pid 4121 on %s (animations on)\n%s\nevidence %s\n"
        ) % (self.sim, head, self.evidence("main", "lane-1")), ""))
        self.assertIn(self.launch_call("-UITEST_DISABLE_LIVE_ACTIVITIES"), self.calls())
        self.assertEqual((Path("/tmp/workout-verify-%s" % self.sim) / "args").read_text(),
                         "-UITEST_FIXTURE -UITEST_SESSION -UITEST_FULL_BLOCK -UITEST_DISABLE_LIVE_ACTIVITIES\n")
        self.assertRegex((self.evidence("main", "lane-1") / "launches.txt").read_text(),
                         r"^\S+ session animated %s on %s from %s\n$" % (re.escape(head), self.sim,
                                                                         re.escape(str(self.checkout))))

    def test_a_plain_launch_still_disables_animations(self):
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1")[0], 0)
        self.assertIn(self.launch_call("-UITEST_DISABLE_ANIMATIONS -UITEST_DISABLE_LIVE_ACTIVITIES"), self.calls())

    def test_animated_after_the_fixture_is_refused_instead_of_passed_to_the_app(self):
        self.assertEqual(self.verify("launch", "session", "--animated", VERIFY_RUN="lane-1"),
                         (2, "", "--animated goes before the fixture: launch --animated session\n"))
        self.assertEqual(self.calls(), [])

    def test_animated_and_at_go_in_either_order(self):
        cached = "%s; this worktree's build is app %s commit %s" % (
            self.cached_build(b"v1\n", self.a), digest(b"v2\n"), self.b[:8])
        for flags in [["--animated", "--at", self.a[:8]], ["--at", self.a[:8], "--animated"]]:
            with self.subTest(flags=flags):
                code, out, err = self.verify("launch", *(flags + ["session"]), VERIFY_RUN="lane-1")
                self.assertEqual((code, out.splitlines()[:2]),
                                 (0, ["launched session as pid 4121 on %s (animations on)" % self.sim, cached]), err)
                self.assertIn(self.launch_call("-UITEST_DISABLE_LIVE_ACTIVITIES"), self.calls())


class Doctor(Lane):
    def doctor_app_line(self):
        return self.verify("doctor")[1].splitlines()[1]

    def test_doctor_passes_this_worktrees_build_once_it_is_installed(self):
        self.verify("build")
        self.verify("launch", "session", VERIFY_RUN="lane-1")
        code, out, err = self.verify("doctor")
        self.assertEqual(out.splitlines()[:2], ["ok   simulator %s booted" % self.sim,
                                                "ok   installed %s" % self.worktree_build(b"v2\n", self.b)])
        self.assertNotIn("sources", out, "nothing was edited after the build")

    def test_doctor_fails_an_installed_app_that_is_not_this_worktrees_build_naming_both(self):
        self.verify("build")
        self.verify("launch", "session", VERIFY_RUN="lane-1")
        self.edit("v3\n")
        self.verify("build")
        self.assertEqual(self.doctor_app_line(), (
            "FAIL installed app %s commit %s (an earlier build of this worktree) is not this worktree's build, "
            "app %s commit %s-dirty (run: %s install)") % (digest(b"v2\n"), self.b[:8], digest(b"v3\n"), self.b[:8],
                                                          self.verify_path))

    def test_doctor_passes_a_cached_build_that_matches_its_cache_entry(self):
        self.verify("build")
        self.verify("install", self.a)
        self.assertEqual(self.doctor_app_line(), "ok   installed %s; this worktree's build is app %s commit %s"
                         % (self.cached_build(b"v1\n", self.a), digest(b"v2\n"), self.b[:8]))

    def test_doctor_fails_when_nothing_is_installed(self):
        self.verify("build")
        self.assertEqual(self.doctor_app_line(), "FAIL nothing installed on %s (run: %s launch <fixture>)"
                         % (self.sim, self.verify_path))
