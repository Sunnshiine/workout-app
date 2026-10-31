from evidence_support import *  # noqa: F401,F403


TAKE_LINES = """format=take/1
name=appear
video=appear.mp4
drive=launch --animated session
tail=2.0
load_limit=50
load_before=12.31
load_after=14.02
started=1791817306.217
drive_start=0.004
drive_end=2.694
stopped=4.714
recorder_exit=0
recorder_early=0
frames=37
first_frame=0.000
last_frame=3.402
video_px=1206x2622
verdict=VALID
invalid=
invalid_rules=
"""
STAMP = TAKE_LINES + ("screen_pt=402x874\ncard_pt=@16,476 370x308\nanimations=on\n"
                      "app=app 804e750cad00 commit ea5af074 (this worktree's build)\n")


def stamp_with(**changes):
    text = STAMP
    for key, value in changes.items():
        text = re.sub(r"(?m)^%s=.*$" % key, "%s=%s" % (key, value), text)
    return take.parse(text)


class TakeJudge(unittest.TestCase):
    def test_a_take_that_breaks_no_rule_is_valid_and_writes_back_the_same_take_lines(self):
        self.assertEqual(take.judge(take.parse(STAMP)), [])
        self.assertEqual("\n".join(take.take_lines(take.parse(STAMP))) + "\n", TAKE_LINES)

    def test_the_summary_reads_the_whole_stamp(self):
        self.assertEqual(take.summary(take.parse(STAMP)), (
            "take appear VALID 4.71 s, drive +0.00..+2.69 s, 37 frames, last +3.40 s, load 12.3 then 14.0 (limit 50), "
            "animations on"))
        self.assertEqual(take.summary(stamp_with(drive="", frames=1, load_after="63.20", animations="off")), (
            "take appear INVALID 4.71 s, no drive, 1 frame, last +3.40 s, load 12.3 then 63.2 (limit 50), "
            "animations off"))

    def test_parse_reads_the_four_lines_verify_sh_appends_and_defaults_them_when_absent(self):
        appended = take.parse(STAMP)
        self.assertEqual((appended.screen_pt, appended.card_pt, appended.animations, appended.app),
                         ((402, 874), (16, 476, 370, 308), "on",
                          "app 804e750cad00 commit ea5af074 (this worktree's build)"))
        bare = take.parse(TAKE_LINES)
        self.assertEqual((bare.screen_pt, bare.card_pt, bare.animations, bare.app), (None, None, "unknown", ""))

    def test_card_pt_is_the_trees_frame_of_the_card_in_points_or_none(self):
        card = take.parse(STAMP).card_pt
        self.assertEqual((type(card), card, card.center, card.text),
                         (tree.Frame, (16, 476, 370, 308), (201.0, 630.0), "@16,476 370x308"))
        self.assertEqual(take.parse(STAMP.replace("card_pt=@16,476 370x308", "card_pt=@-83,476 4770x308")).card_pt.text,
                         "@-83,476 4770x308")
        self.assertEqual(take.parse(STAMP.replace("card_pt=@16,476 370x308", "card_pt=none")).card_pt, "none")

    def test_parse_refuses_a_stamp_that_is_not_take_1_naming_what_is_wrong(self):
        for text, why in [
            (STAMP.replace("format=take/1", "format=take/2"), "format=take/2, not take/1"),
            (STAMP.replace("format=take/1\n", ""), "no format=take/1"),
            (re.sub(r"(?m)^(drive_start|frames)=.*\n", "", STAMP), "no drive_start= frames="),
            (STAMP.replace("frames=37", "frames=many"), "frames=many does not parse"),
            (STAMP.replace("screen_pt=402x874", "screen_pt=402"), "screen_pt=402 does not parse"),
            (STAMP.replace("card_pt=@16,476 370x308", "card_pt=@16,476"), "card_pt=@16,476 does not parse"),
        ]:
            with self.subTest(why=why):
                with self.assertRaises(ValueError) as raised:
                    take.parse(text)
                self.assertEqual(str(raised.exception), why)

    def test_load_over_the_limit_at_the_end_as_host_admission_reads_over(self):
        self.assertEqual(take.judge(stamp_with(load_after="63.20")), [("load", "load 63.2 at the end, over 50")])
        self.assertEqual(take.judge(stamp_with(load_after="50.01")), [("load", "load 50.0 at the end, over 50")])
        self.assertEqual(take.judge(stamp_with(load_after="50.00")), [])

    def test_load_over_the_limit_at_the_start_is_record_s_refusal_not_a_rule_so_the_take_is_valid(self):
        self.assertEqual(take.judge(stamp_with(load_before="63.20", load_after="14.02")), [])

    def test_a_recorder_that_stopped_early_or_exited_nonzero(self):
        self.assertEqual(take.judge(stamp_with(recorder_early="1")),
                         [("recorder_early", "the recorder stopped before the take ended")])
        self.assertEqual(take.judge(stamp_with(recorder_exit="1")),
                         [("recorder_exit", "recorder exit 1 after SIGINT; the video may be cut short")])

    def test_a_drive_needs_a_frame_after_the_first_at_or_after_it_began(self):
        self.assertEqual(take.judge(stamp_with(drive_start="0.320", last_frame="0.300")), [("coverage",
            "the screen never changed after the drive began at +0.32 s, so the take shows nothing the drive did")])
        self.assertEqual(take.judge(stamp_with(drive_start="0.000", first_frame="0.000", last_frame="0.000",
                                               frames="1")), [("coverage",
            "the screen never changed after the drive began at +0.00 s, so the take shows nothing the drive did")])
        self.assertEqual(take.judge(stamp_with(drive_start="0.320", last_frame="0.320", frames="2")), [])

    def test_a_take_with_no_drive_needs_two_frames(self):
        self.assertEqual(take.judge(stamp_with(drive="", frames="1", last_frame="0.000")),
                         [("coverage", "one frame: the screen never changed while recording")])
        self.assertEqual(take.judge(stamp_with(drive="", frames="2")), [])

    def test_every_failed_rule_gives_its_rule_and_reason_in_rule_order_and_the_stamp_lists_the_rules(self):
        broken = stamp_with(load_after="70.00", recorder_early="1", recorder_exit="2", drive_start="3.500")
        self.assertEqual(take.judge(broken), [
            ("load", "load 70.0 at the end, over 50"),
            ("recorder_early", "the recorder stopped before the take ended"),
            ("recorder_exit", "recorder exit 2 after SIGINT; the video may be cut short"),
            ("coverage",
             "the screen never changed after the drive began at +3.50 s, so the take shows nothing the drive did"),
        ])
        self.assertEqual(take.take_lines(broken)[-3:], [
            "verdict=INVALID",
            "invalid=load 70.0 at the end, over 50; the recorder stopped before the take ended; recorder exit "
            "2 after SIGINT; the video may be cut short; the screen never changed after the drive began at +3.50 s, "
            "so the take shows nothing the drive did",
            "invalid_rules=load,recorder_early,recorder_exit,coverage",
        ])



RECORDER_STUB = """#!/bin/sh
echo $$ > "{dir}/recorder.pid"
if [ -n "${STUB_STUCK:-}" ]; then trap '' INT; else trap 'echo mp4 > "$8"; exit 0' INT; fi
[ -n "${STUB_NEVER_STARTS:-}" ] || echo "Recording started" >&2
while :; do sleep 0.1; done
"""
WRAPPED_LAUNCH_STUB = """#!/bin/bash
trap 'echo "the EXIT trap ran" > "{dir}/drive-exit"' EXIT
[ "$1" != fail ] || exit 4
touch "{dir}/driving"
while :; do sleep 0.1; done
"""


class Film(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp()).resolve()
        self.addCleanup(shutil.rmtree, str(self.tmp), True)
        (self.tmp / "bin").mkdir()
        for path, stub in [(self.tmp / "bin" / "xcrun", RECORDER_STUB), (self.tmp / "verify.sh", WRAPPED_LAUNCH_STUB),
                           (self.tmp / "bin" / "sysctl", "#!/bin/sh\necho '{ 1.00 1.00 1.00 }'\n")]:
            path.write_text(stub.replace("{dir}", str(self.tmp)))
            path.chmod(0o755)
        self.env = dict(os.environ, PATH="%s:%s" % (self.tmp / "bin", os.environ["PATH"]))
        self.addCleanup(self.kill_recorder)
        self.saved = take.STOP_GRACE
        self.addCleanup(setattr, take, "STOP_GRACE", self.saved)
        take.STOP_GRACE = 10.0  # a recorder that honours SIGINT can take seconds to exit on a loaded host

    def film_stuck(self, drive, **env):
        take.STOP_GRACE = 0.3
        return self.film(drive, STUB_STUCK="1", **env)

    def kill_recorder(self):
        pid = self.tmp / "recorder.pid"
        if pid.exists():
            try:
                os.kill(int(pid.read_text()), signal.SIGKILL)
            except ProcessLookupError:
                pass

    def film(self, drive, start_timeout=5.0, **env):
        with mock.patch.dict(os.environ, dict(self.env, **env)), tempfile.TemporaryFile("w+") as stderr, \
                contextlib.redirect_stderr(stderr):
            try:
                take.film("SIM", "lane-1", str(self.tmp / "verify.sh"), self.tmp / "appear.mp4", 0.0, 50.0, drive,
                          start_timeout)
            except (take.DriveFailed, take.NoTake) as failure:
                stderr.seek(0)
                return type(failure).__name__, str(failure), stderr.read()
        self.fail("film returned a take")

    def stuck(self):
        pid = int((self.tmp / "recorder.pid").read_text())
        return "simctl recordVideo (pid %d) is still running 0.3 s after SIGINT; stop it with: kill -INT %d\n" % (pid, pid)

    def test_a_load_that_cannot_be_read_as_the_take_begins_drives_nothing(self):
        (self.tmp / "bin" / "sysctl").write_text("#!/bin/sh\necho 'sysctl: transient' >&2\nexit 1\n")
        failure = subprocess.CalledProcessError(1, ["sysctl", "-n", "vm.loadavg"])
        self.assertEqual(self.film(["fail"]), ("NoTake", "could not read the load as the take began: %s" % failure, ""))

    def test_a_failed_drive_is_the_failure_even_when_the_recorder_will_not_stop(self):
        failure = self.film_stuck(["fail"])
        self.assertEqual(failure, ("DriveFailed", "the drive `fail` exited 4, so the take is not kept", self.stuck()))

    def test_a_recorder_that_never_started_is_the_failure_even_when_it_will_not_stop(self):
        failure = self.film_stuck(["fail"], start_timeout=0.3, STUB_NEVER_STARTS="1")
        self.assertEqual(failure, ("NoTake", "simctl recordVideo did not start capturing within 0.3 s, so nothing "
                                             "was driven", self.stuck()))

    def test_an_interrupted_take_gives_the_drive_sigint_so_its_exit_trap_runs(self):
        record = subprocess.Popen(
            [sys.executable, str(SKILL / "take.py"), "record", "--sim", "SIM", "--run", "lane-1", "--verify",
             str(self.tmp / "verify.sh"), "--out", str(self.tmp / "appear.mp4"), "--tail", "0", "--limit", "50",
             "--", "launch", "--animated", "session"],
            env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        self.addCleanup(record.kill)
        deadline = time.time() + 10
        while not (self.tmp / "driving").exists():
            self.assertLess(time.time(), deadline, "the drive never started")
            time.sleep(0.05)
        record.send_signal(signal.SIGINT)
        self.assertEqual(record.communicate(timeout=10), ("", ""))
        self.assertEqual(record.returncode, 130)
        self.assertEqual((self.tmp / "drive-exit").read_text(), "the EXIT trap ran\n")
        self.assertEqual(sorted(p.name for p in self.tmp.iterdir()),
                         ["bin", "drive-exit", "driving", "recorder.pid", "verify.sh"])
