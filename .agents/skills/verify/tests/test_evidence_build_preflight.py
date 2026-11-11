from evidence_support import *  # noqa: F401,F403
from evidence_lane import *  # noqa: F401,F403

FINDING = ("fail sandbox-report: 3 of 3 sandboxed, denied mach-lookups did not return within 5 s, so sandbox violation "
           "reporting is stuck\n  remedy: restart sandboxd when no simulator lease is held, or reboot\n  needs the operator")
REFUSAL = ("verify.sh will not start the build: the SwiftLint build plug-in would hang until the operator clears the "
           "finding above, by restarting sandboxd while no simulator lease is held, or by rebooting. Until then an app "
           "built before still works: verify.sh install and launch put it on the simulator, shot takes a screenshot, and "
           "find and tap drive it.")


class BuildPreflight(Lane):
    def stick_sandbox_reporting(self, after=0):
        self.env.update(FAKE_HOSTGATE_CHECK_RC="1", FAKE_HOSTGATE_CHECK_OUT=FINDING, FAKE_HOSTGATE_CHECK_SLEEP=str(after))

    def builds(self):
        return [call for call in self.calls() if call.startswith("xcodebuild")]

    def test_a_build_while_sandbox_reporting_is_stuck_is_refused_before_xcodebuild_starts(self):
        self.stick_sandbox_reporting()
        self.assertEqual(self.verify("build"), (75, "", FINDING + "\n" + REFUSAL + "\n"))
        self.assertEqual(self.builds(), [], "xcodebuild never started, so nothing hangs at the plug-in")

    def test_a_check_that_reports_the_wedge_after_7_s_as_hostgate_does_still_refuses(self):
        self.stick_sandbox_reporting(after=7)
        self.assertEqual(self.verify("build"), (75, "", FINDING + "\n" + REFUSAL + "\n"))
        self.assertEqual(self.builds(), [])

    def test_an_install_that_would_build_a_commit_into_the_cache_is_refused_the_same_way(self):
        self.stick_sandbox_reporting()
        code, out, err = self.verify("install", self.a)
        self.assertEqual((code, out), (75, ""))
        self.assertEqual(err, FINDING + "\n" + REFUSAL + "\napp on %s unchanged: nothing installed; this install wanted %s "
                         "from the app cache\n" % (self.sim, self.a[:8]))
        self.assertEqual(self.builds(), [])
        self.assertFalse((self.cache / self.a).exists(), "no cache entry was started")

    def test_an_app_built_before_still_installs_and_launches(self):
        self.assertEqual(self.verify("build")[0], 0)
        self.assertEqual(self.verify("install", self.a)[0], 0)
        self.stick_sandbox_reporting()
        code, out, err = self.verify("install", self.a)
        self.assertEqual((code, out.splitlines()[-1], err), (0, self.cached_build(b"v1\n", self.a), ""))
        code, out, err = self.verify("install")
        self.assertEqual((code, out.splitlines()[-1], err), (0, self.worktree_build(b"v2\n", self.b), ""))
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="r1")[0], 0)
        self.assertEqual(self.builds(), [], "the launch built nothing")
