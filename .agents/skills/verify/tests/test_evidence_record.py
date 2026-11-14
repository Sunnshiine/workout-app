from evidence_support import *  # noqa: F401,F403
from evidence_lane import *  # noqa: F401,F403


SYSCTL_STUB = """#!/bin/sh
if [ -f "{dir}/stopped" ]; then echo "{ ${STUB_LOAD_AFTER:-14.02} 9.00 8.00 }"; else echo "{ ${STUB_LOAD_BEFORE:-12.31} 9.00 8.00 }"; fi
"""
FFPROBE_STUB = """#!/bin/sh
for video; do :; done
[ -s "$video" ] || { echo "$video: No such file or directory" >&2; exit 1; }
frames=
for t in ${STUB_PTS:-0.000000 3.402000 0.400000}; do frames="$frames${frames:+, }{\\"pts_time\\": \\"$t\\"}"; done
echo "{\\"frames\\": [$frames], \\"streams\\": [{\\"width\\": 1206, \\"height\\": 2622}]}"
"""
CLAIMING_FOREGROUND_STUB = """import os, sys
if os.path.exists("{dir}/claimed"):
    print("ok (wall/cpu 1.02)")
    sys.exit(0)
open("{dir}/claimed", "w").close()
open("{state}/run", "w").write("lane-2\\n")
open("{state}/pid", "w").write("{pid}\\n")
print("starved (wall/cpu 2.70)")
sys.exit(3)
"""
TAKE_KEYS = ["format", "name", "video", "drive", "tail", "load_before", "load_after", "started", "drive_start",
             "drive_end", "stopped", "recorder_exit", "recorder_early", "frames", "first_frame", "last_frame",
             "video_px", "foreground", "verdict", "invalid", "invalid_rules", "screen_pt", "card_pt", "animations",
             "app"]
SUMMARY = re.compile(r"^take appear (VALID|INVALID) \d+\.\d\d s, drive \+\d+\.\d\d\.\.\+\d+\.\d\d s, 3 frames, "
                     r"last \+3\.40 s, load 12\.3 then (\d+\.\d), foreground ok \(wall/cpu 1\.02\), animations on$")


class Record(Lane):
    def setUp(self):
        super().setUp()
        for name, stub in [("sysctl", SYSCTL_STUB), ("ffprobe", FFPROBE_STUB)]:
            (self.tmp / "bin" / name).write_text(stub.replace("{dir}", str(self.tmp)))
            (self.tmp / "bin" / name).chmod(0o755)
        self.verify("build")
        self.run = self.evidence("main", "lane-1")

    def launch(self):
        self.assertEqual(self.verify("launch", "--animated", "session", VERIFY_RUN="lane-1")[0], 0)

    def record(self, *argv, **env):
        for marker in ["signals", "stopped", "foreground-calls"]:
            (self.tmp / marker).unlink(missing_ok=True)
        env.setdefault("VERIFY_RUN", "lane-1")
        return self.verify("record", "appear", "--tail", "0.5", *argv, **env)

    def assertExit(self, code, want, out, err):
        """A failed exit names what verify.sh said, since the code alone cannot tell which path returned it."""
        self.assertEqual(code, want, "verify.sh record said\nstdout:\n%s\nstderr:\n%s" % (out, err))

    def stamp(self, run=None):
        return [line.split("=", 1) for line in ((run or self.run) / "appear.take").read_text().splitlines()]

    def signals(self):
        return (self.tmp / "signals").read_text()

    def listing(self, directory):
        return sorted(p.name for p in directory.iterdir())

    def staged(self):
        """The path the recorder wrote: a folder of its own under ~/Library/Caches, removed after the take."""
        video = Path(next(call for call in self.calls() if " recordVideo " in call).rsplit(" ", 1)[1])
        self.assertEqual((video.parent.parent, video.name),
                         (self.tmp / "home" / "Library" / "Caches" / "workout-verify", "appear.mp4"))
        self.assertFalse(video.parent.exists(), "the recorder's folder is removed")
        return video

    def test_a_valid_take_stamps_every_key_in_order_and_stops_the_recorder_with_one_sigint(self):
        self.launch()
        before = time.time()
        code, out, err = self.record("--", "tap", "-x", "5", "-y", "6")
        self.assertEqual((code, err), (0, ""))
        paths, summary = out.splitlines()[:3], out.splitlines()[3:]
        self.assertEqual(paths, [str(self.run / "appear.mp4"), str(self.run / "appear.take"),
                                 str(self.run / "appear.end.txt")])
        self.assertEqual([SUMMARY.match(line).groups() for line in summary], [("VALID", "14.0")])
        stamp = self.stamp()
        self.assertEqual([key for key, _ in stamp], TAKE_KEYS)
        values = dict(stamp)
        timed = {key: float(values.pop(key)) for key in ["started", "drive_start", "drive_end", "stopped"]}
        self.assertEqual(values, {
            "format": "take/1", "name": "appear", "video": "appear.mp4", "drive": "tap -x 5 -y 6", "tail": "0.5",
            "load_before": "12.31", "load_after": "14.02", "recorder_exit": "0",
            "recorder_early": "0", "frames": "3", "first_frame": "0.000", "last_frame": "3.402",
            "video_px": "1206x2622", "foreground": "ok (wall/cpu 1.02)", "verdict": "VALID", "invalid": "",
            "invalid_rules": "", "screen_pt": "402x874", "card_pt": "@-83,476 4770x308", "animations": "on",
            "app": self.worktree_build(b"v2\n", self.b)})
        self.assertTrue(before < timed["started"] < time.time(), timed)
        self.assertTrue(0 <= timed["drive_start"] <= timed["drive_end"], timed)
        self.assertGreaterEqual(timed["stopped"] - timed["drive_end"], 0.5, "the tail ran after the drive")
        self.assertEqual(self.signals(), "INT\n")
        self.assertEqual((self.run / "appear.mp4").read_text(), "mp4 \n")
        self.assertEqual(self.listing(self.run), ["appear.end.txt", "appear.mp4", "appear.take", "launches.txt"])
        self.assertEqual(self.calls()[:3], [
            "xcrun simctl io %s recordVideo --codec h264 --force %s" % (self.sim, self.staged()),
            "Recording started",
            "axe tap --udid %s --wait-timeout 3 -x 5 -y 6 --tap-style physical" % self.sim,
        ], "the drive ran only after the recorder said it was capturing")
        self.assertEqual((self.run / "appear.end.txt").read_text(), (
            "AXApplication\t\tWorkoutTracker\t\t@0,0 402x874\n"
            "AXButton\tweight-pill\tWeight, 237.5\t\t@98,531 206x66\n"
            "AXGroup\tactive-set-card\t\t\t@-83,476 4770x308\n"
            "AXStaticText\t\tRest 1:58 remaining\t\t@100,816 202x51\n"))
        self.assertEqual(self.calls().count("axe describe-ui --udid %s" % self.sim), 1,
                         "screen_pt=, card_pt= and the end tree come from one describe after the take")

    def test_a_take_is_kept_when_the_recorder_cannot_write_under_the_repo(self):
        """While sandbox reporting is stuck, recordVideo fails with Code=513 on any path under ~/Projects."""
        self.launch()
        code, _, err = self.record("--", "tap", "-x", "5", "-y", "6", STUB_DENY=str(self.run))
        self.assertEqual((code, err), (0, ""))
        self.assertEqual((self.run / "appear.mp4").read_text(), "mp4 \n")
        self.staged()

    def test_a_take_whose_tree_holds_no_active_set_card_stamps_card_pt_none(self):
        self.launch()
        tree = json.loads(MINI)
        tree[0]["children"] = [node for node in tree[0]["children"] if node.get("AXUniqueId") != "active-set-card"]
        (self.tmp / "describe-ui.json").write_text(json.dumps(tree))
        code, _, err = self.record("--", "tap", "-x", "5", "-y", "6")
        self.assertEqual((code, err), (0, ""))
        self.assertEqual((dict(self.stamp())["screen_pt"], dict(self.stamp())["card_pt"]), ("402x874", "none"))
        self.assertEqual(self.calls().count("axe describe-ui --udid %s" % self.sim), 1)

    def test_a_tree_whose_card_frame_cannot_be_read_keeps_nothing_and_exits_70_naming_doctor(self):
        self.launch()
        tree = json.loads(MINI)
        card = next(node for node in tree[0]["children"] if node.get("AXUniqueId") == "active-set-card")
        del card["frame"]
        (self.tmp / "describe-ui.json").write_text(json.dumps(tree))
        code, out, err = self.record("--", "tap", "-x", "5", "-y", "6")
        self.assertEqual((code, out, err.splitlines()[-1]), (70, "", (
            "could not read active-set-card's frame from the accessibility tree after the take, so appear.take "
            "cannot say where the card is; run: %s doctor" % self.verify_path)))
        self.assertEqual(self.listing(self.run), [".pending", "launches.txt"])
        self.assertEqual(self.listing(self.run / ".pending"), [])
        self.assertEqual(self.calls().count("axe describe-ui --udid %s" % self.sim), 1)

    def test_a_take_under_any_load_is_recorded_valid_and_stamps_the_load_as_information(self):
        self.launch()
        code, out, err = self.record("--", "tap", "-x", "5", "-y", "6", STUB_LOAD_BEFORE="130.00",
                                     STUB_LOAD_AFTER="520.00")
        self.assertEqual((code, err), (0, ""))
        values = dict(self.stamp())
        self.assertEqual((values["load_before"], values["load_after"], values["foreground"], values["verdict"]),
                         ("130.00", "520.00", "ok (wall/cpu 1.02)", "VALID"))

    def test_a_foreground_starved_for_the_whole_wait_is_recorded_anyway_and_stamped_starved(self):
        self.launch()
        code, out, err = self.record("--", "tap", "-x", "5", "-y", "6", STUB_FOREGROUND="starved 2.70")
        self.assertExit(code, 0, out, err)
        self.assertRegex(err, "^" + re.escape("recording anyway after ") + r"\d+" + re.escape(
            " s, with the foreground still starved (wall/cpu 2.70)\nthe host starved the foreground before this "
            "take (starved (wall/cpu 2.70)), so discount any jank in it\n") + "$")
        values = dict(self.stamp())
        self.assertEqual((values["foreground"], values["verdict"]), ("starved (wall/cpu 2.70)", "VALID"))
        self.assertEqual(self.listing(self.run), ["appear.end.txt", "appear.mp4", "appear.take", "launches.txt"])

    def test_a_starved_foreground_is_waited_on_until_it_gets_its_share(self):
        self.launch()
        code, out, err = self.record("--", "tap", "-x", "5", "-y", "6", STUB_FOREGROUND="starved 2.70,ok 1.40",
                                     WORKOUT_ADMIT_WAIT="30", STUB_CLOCK="1")
        self.assertExit(code, 0, out, err)
        self.assertEqual(err, "waiting up to 30 s for the host to stop starving the foreground: starved (wall/cpu "
                         "2.70)\nwent ahead after 2 s\n")
        self.assertEqual(dict(self.stamp())["foreground"], "ok (wall/cpu 1.40)")
        self.assertEqual(len((self.tmp / "foreground-calls").read_text().splitlines()), 2)

    def test_a_foreground_probe_that_fails_records_nothing(self):
        self.launch()
        self.assertEqual(self.record("--", "tap", "-x", "5", "-y", "6", STUB_FOREGROUND="broken 0"), (70, "", (
            "%s/foreground.py exited 1, so nothing was recorded\n" % self.verify_path.parent)))
        self.assertEqual(self.calls(), [])
        self.assertEqual(self.listing(self.run), ["launches.txt"])

    def test_a_run_that_takes_the_simulator_while_record_waits_for_the_foreground_is_refused_after_the_wait(self):
        self.launch()
        other = subprocess.Popen(FIXTURE_APP, start_new_session=True)
        self.addCleanup(other.wait)
        self.addCleanup(other.kill)
        state = Path("/tmp/workout-verify-%s" % self.sim)
        (self.verify_path.parent / "foreground.py").write_text(CLAIMING_FOREGROUND_STUB.replace(
            "{dir}", str(self.tmp)).replace("{state}", str(state)).replace("{pid}", str(other.pid)))
        code, out, err = self.record("--", "tap", "-x", "5", "-y", "6", WORKOUT_ADMIT_WAIT="10", STUB_CLOCK="1")
        self.assertEqual((code, out), (75, ""))
        self.assertRegex(err, "^" + re.escape(
            "waiting up to 10 s for the host to stop starving the foreground: starved (wall/cpu 2.70)\n")
            + "went ahead after 2 s\n" + re.escape(
            "the app on %s belongs to run lane-2 (pid %d), not to lane-1, so this would drive another run's app; "
            "launch yours first: SIM=%s VERIFY_RUN=lane-1 %s launch <fixture>\n"
            % (self.sim, other.pid, self.sim, self.verify_path)) + "$")
        self.assertEqual(self.calls(), [])

    def test_a_reclaimed_run_records_nothing_and_is_told_who_reclaimed_it_before_any_wait(self):
        self.launch()
        Path("/tmp/workout-verify-%s/reclaimed.lane-1" % self.sim).write_text("test-sim.sh run (pid 1) at T\n")
        for drive in [["tap", "-x", "5", "-y", "6"], ["launch", "--animated", "session"]]:
            with self.subTest(drive=drive):
                refused = self.record("--", *drive, STUB_FOREGROUND="starved 2.70", WORKOUT_ADMIT_WAIT="30")
                self.assertEqual(refused, (75, "", (
                    "run lane-1 was reclaimed by test-sim.sh run (pid 1) at T; launch again: SIM=%s VERIFY_RUN=lane-1 "
                    "%s launch <fixture>\n" % (self.sim, self.verify_path))))
                self.assertEqual(self.calls(), [])
                self.assertEqual(self.listing(self.run), ["launches.txt"])

    def test_a_take_of_a_launch_refused_for_another_runs_app_hints_that_launch_as_given(self):
        app = self.own_the_app("owner-1")
        for drive, hint in [(["launch", "--animated", "session"], "launch --animated session"),
                            (["launch", "--at", "abc123", "--animated", "session"],
                             "launch --at abc123 --animated session"),
                            (["launch", "session"], "launch session"),
                            (["tap", "-x", "5", "-y", "6"], "launch <fixture>")]:
            with self.subTest(drive=drive):
                self.assertEqual(self.record("--", *drive), (75, "", (
                    "the app on {sim} belongs to run owner-1 (pid {pid}), not to lane-1, so this would drive another "
                    "run's app; launch yours first: SIM={sim} VERIFY_RUN=lane-1 {verify} {hint}\n"
                ).format(sim=self.sim, pid=app.pid, verify=self.verify_path, hint=hint)))
                self.assertEqual(self.calls(), [])

    def test_a_take_of_a_launch_refused_after_a_refused_relaunch_hints_that_launch_as_given(self):
        self.verify("install", self.a)
        self.own_the_app("ui12")
        refusal = ("%s holds %s, and this launch would replace it with %s. To run the cached build: launch --at %s "
                   "session. To replace it: install, then launch." % (
                       self.sim, self.cached_build(b"v1\n", self.a), self.worktree_build(b"v2\n", self.b), self.a[:8]))
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="ui12")[:2], (65, ""))
        for drive, hint in [(["launch", "--at", "abc123", "--animated", "session"],
                             "launch --at abc123 --animated session"),
                            (["tap", "-x", "5", "-y", "6"], "launch <fixture>")]:
            with self.subTest(drive=drive):
                self.assertEqual(self.record("--", *drive, VERIFY_RUN="ui12"), (75, "", (
                    "the last launch of run ui12 on {sim} was refused, so this would drive whatever that refusal left "
                    "running ({refusal}); stop it, then launch again: SIM={sim} VERIFY_RUN=ui12 {verify} stop, then "
                    "SIM={sim} VERIFY_RUN=ui12 {verify} {hint}\n"
                ).format(sim=self.sim, refusal=refusal, verify=self.verify_path, hint=hint)))
                self.assertEqual(self.calls(), [])

    def test_a_recorder_that_never_starts_capturing_drives_nothing_and_leaves_nothing(self):
        self.launch()
        self.assertEqual(self.record("--", "tap", "-x", "5", "-y", "6", STUB_NEVER_STARTS="1", VERIFY_RECORD_START="1"),
                         (70, "", "simctl recordVideo did not start capturing within 1 s, so nothing was driven\n"))
        self.assertEqual(self.calls(), [
            "xcrun simctl io %s recordVideo --codec h264 --force %s" % (self.sim, self.staged())])
        self.assertEqual(self.signals(), "INT\n")
        self.assertEqual(self.listing(self.run), [".pending", "launches.txt"])
        self.assertEqual(self.listing(self.run / ".pending"), [])

    def test_a_failing_drive_stops_the_recorder_and_leaves_nothing(self):
        self.launch()
        self.assertEqual(self.record("--", "tap", "-x", "5", "-y", "6", STUB_AXE_EXIT="4"),
                         (1, "", "the drive `tap -x 5 -y 6` exited 4, so the take is not kept\n"))
        self.assertEqual(self.signals(), "INT\n")
        self.assertEqual(self.listing(self.run), [".pending", "launches.txt"])
        self.assertEqual(self.listing(self.run / ".pending"), [])

    def test_a_wrapped_launch_lands_in_the_takes_own_run(self):
        code, out, err = self.record("--", "launch", "--animated", "session", VERIFY_RUN="")
        self.assertEqual(code, 0, err)
        run = Path(out.splitlines()[0]).parent
        head = self.worktree_build(b"v2\n", self.b)
        self.assertEqual(err, "launched session as pid %d on %s (animations on)\n%s\nevidence %s\n" % (
            self.app_pid, self.sim, head, run), "the drive's output goes to stderr, and it launched into the take's run")
        self.assertEqual(self.listing(run), ["appear.end.txt", "appear.mp4", "appear.take", "launches.txt"])
        self.assertRegex((run / "launches.txt").read_text(), r"^\S+ session animated %s on %s from %s\n$" % (
            re.escape(head), self.sim, re.escape(str(self.checkout))))
        values = dict(self.stamp(run))
        self.assertEqual((values["drive"], values["animations"]), ("launch --animated session", "on"))

    def test_a_take_of_an_app_launched_without_animated_says_it_cannot_show_motion(self):
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1")[0], 0)
        code, out, err = self.record("--", "tap", "-x", "5", "-y", "6")
        self.assertEqual((code, err), (0, "animations are off in this app (it was launched without --animated), "
                                          "so the take cannot show motion\n"))
        self.assertEqual(dict(self.stamp())["animations"], "off")

    def test_a_rerun_replaces_the_pair(self):
        self.launch()
        self.assertEqual(self.record("--", "tap", "-x", "5", "-y", "6", STUB_MARK="first")[0], 0)
        self.assertEqual(self.record("--", "tap", "-x", "5", "-y", "6", STUB_MARK="second",
                                     STUB_PTS="1.250000 0.000000")[0], 0)
        self.assertEqual(self.listing(self.run), ["appear.end.txt", "appear.mp4", "appear.take", "launches.txt"])
        self.assertEqual((self.run / "appear.mp4").read_text(), "mp4 second\n")
        values = dict(self.stamp())
        self.assertEqual((values["frames"], values["last_frame"]), ("2", "1.250"))

    def test_a_tail_that_is_not_a_number_is_usage_before_anything_runs(self):
        code, out, err = self.verify("record", "appear", "--tail", "2s", VERIFY_RUN="lane-1")
        self.assertEqual((code, out, err.splitlines()[0]), (2, "", "Usage: .agents/skills/verify/verify.sh <command> [args]"))
        self.assertEqual(self.calls(), [])
