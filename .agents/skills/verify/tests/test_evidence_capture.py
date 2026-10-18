from evidence_support import *  # noqa: F401,F403


AXE_STUB = """#!/bin/sh
case $1 in
  screenshot) cp "$STUB_FRAME" "$5" ;;
  describe-ui) cat "$STUB_TREE" ;;
  *) exit 1 ;;
esac
"""
AFTER_LOG = MINI.replace("Weight, 237.5", "Weight, 252.5")


class VerifyShot(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        skill = self.root / ".agents" / "skills" / "verify"
        skill.mkdir(parents=True)
        (self.root / "scripts").mkdir()
        (skill / "verify.sh").symlink_to(SKILL / "verify.sh")
        for name in ["verify-usage.sh", "verify-runs.sh", "verify-builds.sh", "verify-launch.sh"]:
            (skill / name).symlink_to(SKILL / name)
        (skill / "tree.py").symlink_to(SKILL / "tree.py")
        (self.root / "scripts" / "sim-lock.sh").symlink_to(REPO / "scripts" / "sim-lock.sh")
        axe = self.root / ".build" / "verify" / "node_modules" / "xcodebuildmcp" / "bundled" / "axe"
        axe.parent.mkdir(parents=True)
        axe.write_text(AXE_STUB)
        axe.chmod(0o755)
        self.verify = skill / "verify.sh"
        self.sim = "SHOT-TEST-%d" % os.getpid()
        self.evidence = self.root / "evidence" / "issue-674"
        self.home, self.stage = self.root / "home.png", self.root / "stage.png"
        write_png(self.home, 4, 4, (32, 96, 160))
        write_png(self.stage, 4, 4, (240, 240, 240))

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def shot(self, name, frame, tree):
        described = self.root / ("%s.describe-ui.json" % name)
        described.write_text(tree)
        env = dict(os.environ, SIM=self.sim, VERIFY_RUN="issue-674", STUB_FRAME=str(frame), STUB_TREE=str(described),
                   VERIFY_EVIDENCE=str(self.evidence.parent))
        done = subprocess.run(
            [str(self.verify), "shot", name], cwd=str(self.root), env=env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
        )
        return done.returncode, done.stdout, done.stderr

    def test_a_frame_identical_to_the_last_shot_while_the_tree_moved_is_refused(self):
        self.assertEqual(self.shot("01-before", self.stage, MINI)[0], 0)
        code, out, err = self.shot("02-after-log", self.stage, AFTER_LOG)
        self.assertEqual((code, out), (70, ""), "a wedged simulator returned the old frame: %s" % err)
        self.assertEqual(err, (
            "refused 02-after-log: its frame is byte-identical to 01-before.png but its tree changed, "
            "so the pixels did not move while the tree did\n"
            "changed from 01-before to 02-after-log, frames ignored:\n"
            "- AXButton\tweight-pill\tWeight, 237.5\t\t@98,531 206x66\n"
            "+ AXButton\tweight-pill\tWeight, 252.5\t\t@98,531 206x66\n"
            "\n"
            "2 changed, 3 unchanged\n"
            "if those lines are text the app does not draw, 01-before.png already shows this screen and the "
            "lines are the evidence\n"
            "if not, the shot fired before a transition drew (wait a second and shoot again) or the screenshot "
            "pipeline is wedged, as the axe button lock in issue 674 left it, and 01-before.png may be frozen too "
            "(run: xcrun simctl shutdown %s, then SIM=%s VERIFY_RUN=issue-674 %s launch <fixture>, "
            "and shoot 01-before again)\n" % (self.sim, self.sim, self.verify)
        ))
        self.assertEqual(sorted(p.name for p in self.evidence.iterdir() if not p.name.startswith(".")),
                         ["01-before.png", "01-before.tree.txt"], "the frozen frame is not filed as evidence")
        code, out, err = self.shot("02-after-log", self.home, AFTER_LOG)
        self.assertEqual(code, 0, err)
        self.assertEqual(out.splitlines()[-1], "2 changed, 3 unchanged", "shooting again once the frame moved lands")

    def test_retaking_a_landed_shot_with_its_own_frame_while_the_tree_moved_is_refused(self):
        self.assertEqual(self.shot("01-before", self.home, MINI)[0], 0)
        self.assertEqual(self.shot("02-after-log", self.stage, AFTER_LOG)[0], 0)
        code, out, err = self.shot("02-after-log", self.stage, AFTER_LOG.replace("1:58", "1:57"))
        self.assertEqual((code, out), (70, ""), err)
        self.assertEqual(err.splitlines()[0], "refused 02-after-log: its frame is byte-identical to 02-after-log.png "
                         "but its tree changed, so the pixels did not move while the tree did")
        self.assertEqual((self.evidence / "02-after-log.png").read_bytes(), self.stage.read_bytes())
        self.assertIn("AXStaticText\t\tRest 1:58 remaining\t\t@100,816 202x51",
                      (self.evidence / "02-after-log.tree.txt").read_text().splitlines(),
                      "the shot that landed under that name keeps its tree")

    def test_an_unchanged_screen_with_an_unchanged_tree_still_shoots(self):
        self.assertEqual(self.shot("01-before", self.stage, MINI)[0], 0)
        code, out, err = self.shot("02-still", self.stage, MINI)
        self.assertEqual((code, err), (0, ""))
        self.assertEqual(out, "%s/02-still.png\n%s/02-still.tree.txt\nno tree changes from 01-before to 02-still, frames ignored\n"
                         % (self.evidence, self.evidence), "the same bytes are the right frame when nothing changed")


@unittest.skipUnless(sys.platform == "darwin", "the tiler is a Swift script and runs on macOS only")
class VerifySheet(unittest.TestCase):
    def setUp(self):
        self.run = "sheettest-%d" % os.getpid()
        self.evidence = Path(tempfile.mkdtemp())
        self.dir = self.evidence / self.run
        self.dir.mkdir(parents=True, exist_ok=True)
        for captured, name in enumerate(["02-b", "01-a", "03-c"]):
            write_png(self.dir / ("%s.png" % name), 120, 260, (32, 96, 160))
            tree = self.dir / ("%s.tree.txt" % name)
            tree.write_text("AXApplication\t\tWorkoutTracker\t\t@0,0 402x874\n")
            os.utime(tree, (captured + 1, captured + 1))

    def tearDown(self):
        shutil.rmtree(self.evidence, ignore_errors=True)

    def test_the_sheet_numbers_every_shot_of_the_run_in_capture_order(self):
        code, out, err = verify_sh("sheet", run=self.run, evidence=self.evidence)
        self.assertEqual(code, 0, err)
        self.assertEqual(len(out.splitlines()), 1, "three shots are one page")
        fields = out.rstrip("\n").split("\t")
        self.assertEqual(len(fields), 5, out)
        self.assertEqual(fields[0], str(self.dir / "_sheet.png"), "one sheet per run, beside the shots")
        self.assertEqual(fields[2], "3 images")
        self.assertEqual(fields[4], "1. 02-b  2. 01-a  3. 03-c", "capture order, not name order")

    def test_a_second_sheet_of_the_same_shots_is_the_same_bytes(self):
        self.assertEqual(verify_sh("sheet", run=self.run, evidence=self.evidence)[0], 0)
        first = (self.dir / "_sheet.png").read_bytes()
        self.assertEqual(verify_sh("sheet", run=self.run, evidence=self.evidence)[0], 0)
        self.assertEqual((self.dir / "_sheet.png").read_bytes(), first, "rerunning converges")

    def test_a_run_with_no_shots_says_how_to_take_one(self):
        empty = self.dir.with_name("%s-empty" % self.run)
        empty.mkdir(parents=True, exist_ok=True)
        code, out, err = verify_sh("sheet", run=empty.name, evidence=self.evidence)
        self.assertEqual(code, 1)
        self.assertEqual(out, "")
        self.assertIn("shot NAME", err, "the way out of an empty run")


@unittest.skipUnless(sys.platform == "darwin", "crop cuts with the Swift tiler and reads colours with sips, both macOS only")
class VerifyCrop(unittest.TestCase):
    SURROUND, PILL = (240, 240, 240), (32, 96, 160)

    def setUp(self):
        self.run = "croptest-%d" % os.getpid()
        self.evidence = Path(tempfile.mkdtemp())
        self.dir = self.evidence / self.run
        self.dir.mkdir(parents=True, exist_ok=True)
        shutil.copy(BEFORE_TREE, self.dir / "01-before.tree.txt")
        write_png(self.dir / "01-before.png", 804, 1748, self.SURROUND, box_frame=(196, 1062, 412, 132), box_colour=self.PILL)
        self.crop = self.dir / "01-before-crop-90_523_222x82.png"

    def tearDown(self):
        shutil.rmtree(self.evidence, ignore_errors=True)

    def colours(self, png, points):
        probe = Path(tempfile.mkdtemp())
        try:
            bmp = probe / "probe.bmp"
            subprocess.run(["sips", "-s", "format", "bmp", str(png), "--out", str(bmp)],
                           stdout=subprocess.DEVNULL, check=True)
            data = bmp.read_bytes()
        finally:
            shutil.rmtree(probe, ignore_errors=True)
        offset, = struct.unpack_from("<I", data, 10)
        width, height = struct.unpack_from("<ii", data, 18)
        depth, = struct.unpack_from("<H", data, 28)
        stride = (width * depth // 8 + 3) // 4 * 4
        found = []
        for x, y in points:
            row = y if height < 0 else height - 1 - y
            at = offset + row * stride + x * depth // 8
            found.append(tuple(data[at:at + 3][::-1]))
        return found

    def test_a_crop_by_id_is_the_shots_own_pixels_around_the_element(self):
        self.assertEqual(verify_sh("crop", "01-before", "weight-pill", run=self.run, evidence=self.evidence),
                         (0, "%s\t444x164\n" % self.crop, ""), "8 points around the pill at 2 pixels a point")
        surround, pill = self.SURROUND, self.PILL
        self.assertEqual(self.colours(self.crop, [(15, 16), (16, 15), (16, 16), (427, 147), (428, 147), (427, 148)]),
                         [surround, surround, pill, pill, surround, surround],
                         "the pill starts 16 pixels in from the top left and ends 16 from the bottom right")

    def test_a_crop_at_the_top_left_corner_starts_there(self):
        write_png(self.dir / "01-before.png", 804, 1748, self.SURROUND, box_frame=(0, 0, 8, 8), box_colour=self.PILL)
        corner = self.dir / "01-before-crop-0_0_10x10.png"
        self.assertEqual(verify_sh("crop", "01-before", "0", "0", "10", "10", run=self.run, evidence=self.evidence),
                         (0, "%s\t20x20\n" % corner, ""))
        self.assertEqual(self.colours(corner, [(0, 0), (7, 7), (8, 8)]), [self.PILL, self.PILL, self.SURROUND],
                         "sips centres a crop whose offset is 0 0, which would show the surround alone")

    def test_a_crop_is_not_a_shot(self):
        self.assertEqual(verify_sh("crop", "01-before", "weight-pill", run=self.run, evidence=self.evidence)[0], 0)
        code, out, err = verify_sh("sheet", run=self.run, evidence=self.evidence)
        self.assertEqual(code, 0, err)
        self.assertEqual(out.split("\t")[4], "1. 01-before\n", "the sheet tiles the shot alone")
        self.assertEqual(verify_sh("diff", "01-before", self.crop.stem, run=self.run, evidence=self.evidence), (
            1, "", "no shot %s in %s; shots: 01-before \n" % (self.crop.stem, self.dir)))
        code, out, err = verify_sh("shot", self.crop.stem, run=self.run, evidence=self.evidence)
        self.assertEqual((code, out), (2, ""), "the underscore makes a crop's name illegal for a shot: %s" % err)

    def test_the_same_region_by_points_converges_on_one_file(self):
        self.assertEqual(verify_sh("crop", "01-before", "weight-pill", run=self.run, evidence=self.evidence)[0], 0)
        first = self.crop.read_bytes()
        self.assertEqual(verify_sh("crop", "01-before", "90", "523", "222", "82", run=self.run, evidence=self.evidence),
                         (0, "%s\t444x164\n" % self.crop, ""))
        self.assertEqual(sorted(p.name for p in self.dir.iterdir() if "-crop-" in p.name), [self.crop.name])
        self.assertEqual(self.crop.read_bytes(), first, "rerunning converges")

    def test_a_missing_shot_lists_the_runs_shots(self):
        self.assertEqual(verify_sh("crop", "09-nope", "0", "0", "10", "10", run=self.run, evidence=self.evidence),
                         (1, "", "no shot 09-nope in %s; shots: 01-before \n" % self.dir))
        (self.dir / "02-half.png").write_bytes(b"png")
        self.assertEqual(verify_sh("crop", "02-half", "weight-pill", run=self.run, evidence=self.evidence)[0], 1,
                         "a PNG whose tree never landed is not a shot")


class BurstFrames(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        second = 1000000000
        for name, at in [("f00.png", 999.900), (".drive-returned", 1000.000),
                         ("f01.png", 1000.142), ("f02.png", 1000.373)]:
            (self.dir / name).write_bytes(b"png")
            os.utime(self.dir / name, ns=(int(at * second), int(at * second)))

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_frames_are_named_by_when_they_were_captured(self):
        done = subprocess.run(
            [sys.executable, str(SKILL / "frames.py"), str(self.dir)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
        )
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(
            [Path(line).name for line in done.stdout.splitlines()],
            ["before.png", "+0142ms.png", "+0373ms.png"],
            "capture order, timed from the drive command's return",
        )
        self.assertEqual(
            sorted(path.name for path in self.dir.glob("*.png")),
            ["+0142ms.png", "+0373ms.png", "before.png"],
            "renamed on disk, because the tiler labels a cell with its file stem",
        )

    def test_two_frames_in_one_millisecond_stop_the_burst_and_lose_nothing(self):
        second = 1000000000
        (self.dir / "f03.png").write_bytes(b"a second frame")
        os.utime(self.dir / "f03.png", ns=(int(1000.373 * second), int(1000.373 * second)))
        done = subprocess.run(
            [sys.executable, str(SKILL / "frames.py"), str(self.dir)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
        )
        self.assertNotEqual(done.returncode, 0, "one cell must never stand for two moments")
        self.assertIn("+0373ms.png", done.stderr)
        self.assertEqual(len(list(self.dir.glob("*.png"))), 4, "no frame was overwritten")
