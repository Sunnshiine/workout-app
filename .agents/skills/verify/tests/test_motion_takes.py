from motion_support import *  # noqa: F401,F403


class Takes(unittest.TestCase):
    def test_the_lane_is_the_eight_takes_of_the_original_in_order(self):
        self.assertEqual([(t.name, t.tail, t.setup.name) for t in cardstill.TAKES], [
            ("single-log-rest-start", 3, "LAUNCH"),
            ("node-tap", 2, "NONE"),
            ("review-open", 2, "NONE"),
            ("review-close", 2, "NONE"),
            ("superset-log-switch", 3, "LAUNCH_AND_PAIR"),
            ("partner-tap", 2, "NONE"),
            ("partner-tap-back", 2, "NONE"),
            ("superset-rest-end", 14, "AFTER_REST"),
        ])

    def test_each_take_drives_its_verb_and_only_the_rest_end_only_watches(self):
        self.assertEqual([t.drive for t in cardstill.TAKES], [
            ("tap", "--id", "log-active-set-button"),
            ("tap", "--label", cardstill.SetNode(3)),
            ("tap", "--label", cardstill.SetNode(1)),
            ("tap", "--label", cardstill.SetNode(1)),
            ("tap", "--id", "log-active-set-button"),
            ("tap", "--id", "superset-partner-name"),
            ("tap", "--id", "superset-partner-name"),
            (),
        ])

    def test_a_set_node_resolves_to_its_label_in_the_tree(self):
        tree = ("AXButton\tlog-active-set-button\tLog 237.5 x 5 @6\t\t@20,700 362x50\n"
                "AXButton\t\tSet 1, 185 x 5, logged\t\t@20,300 40x40\n"
                "AXButton\t\tSet 3, 195 x 5\t\t@120,300 40x40\n")
        self.assertEqual(cardstill.node_label(tree, 3), "Set 3, 195 x 5")
        self.assertEqual(cardstill.node_label(tree, 1), "Set 1, 185 x 5, logged")
        self.assertEqual(cardstill.node_label(tree, 2), None)

    def test_record_and_launch_output_name_the_take_and_the_evidence_directory(self):
        record = "/e/lane-head/node-tap.mp4\n/e/lane-head/node-tap.take\ntake node-tap VALID 4.71 s, ...\n"
        launch = "launched session as pid 4121 on SIM (animations on)\napp 804e750cad00\nevidence /e/lane-head\n"
        self.assertEqual(cardstill.recorded_take(record), Path("/e/lane-head/node-tap.take"))
        self.assertEqual(cardstill.recorded_take("gave up after 540 s waiting for the load to fall to 50 before recording\n"), None)
        self.assertEqual(cardstill.evidence_dir(launch), Path("/e/lane-head"))

    def test_each_take_lands_on_the_screen_its_drive_leads_to_and_not_on_the_one_before(self):
        before_after = [
            (LAUNCHED, LOGGED), (LOGGED, NODE_3), (NODE_3, REVIEW), (REVIEW, COLLAPSED),
            (PAIRED, SWITCHED), (SWITCHED, PARTNER), (PARTNER, SWITCHED), (SWITCHED, RESTED),
        ]
        landed, stayed = [], []
        for spec, (before, after) in zip(cardstill.TAKES, before_after):
            landed.append(cardstill.landing_miss(spec, ended_on(after)))
            stayed.append(cardstill.landing_miss(spec, ended_on(before)))
        self.assertEqual(landed, [None] * 8)
        self.assertEqual(stayed, [
            'the take ended without "Set 2 of 3"',
            'the take ended without "Set 3 of 3"',
            "the take ended without logged-set-capsule",
            "the take ended with logged-set-capsule still on screen",
            'the take ended without stage-exercise-name "BB RDL"',
            'the take ended without stage-exercise-name "Back Squat"',
            'the take ended without stage-exercise-name "BB RDL"',
            "the take ended with rest-pill still on screen",
        ])
        self.assertEqual(cardstill.landing_miss(cardstill.TAKES[3], ended_on(LOGGED)),
                         'the take ended without "Set 3 of 3"', "a closed review on another Set did not land")
        self.assertEqual(cardstill.landing_miss(cardstill.TAKES[7], ended_on(screen(SQUAT, card_heading(2, 3)))),
                         'the take ended without stage-exercise-name "BB RDL"', "a rest that ended off the partner")

    def test_a_take_with_no_end_tree_beside_its_stamp_did_not_show_it_landed(self):
        self.assertEqual(cardstill.landing_miss(cardstill.TAKES[1], Path(tempfile.mkdtemp()) / "node-tap.take"),
                         "record left no node-tap.end.txt to check the take landed")


def ended_on(tree):
    take_path = Path(tempfile.mkdtemp()) / "x.take"
    take_path.with_suffix(".end.txt").write_text(tree)
    return take_path


FAKE_VERIFY = """#!/bin/sh
echo "$VERIFY_RUN $*" >> "{dir}/calls"
case $1 in
  launch) [ ! -e "{dir}/alive" ] || exit 75; touch "{dir}/alive"; echo "evidence {dir}/$VERIFY_RUN" ;;
  stop) rm -f "{dir}/alive" ;;
  tree)
    if [ -e "{dir}/tree.fails" ]; then rm "{dir}/tree.fails"; exit 1; fi
    cat "{dir}/tree"; [ ! -e "{dir}/tree.next" ] || mv "{dir}/tree.next" "{dir}/tree" ;;
  record)
    [ -e "{dir}/stamp.take" ] || exit 75
    mkdir -p "{dir}/$VERIFY_RUN"
    cp "{dir}/stamp.take" "{dir}/$VERIFY_RUN/$2.take"
    echo "$VERIFY_RUN $2 ${WORKOUT_ADMIT_WAIT:-unset}" >> "{dir}/admit"
    [ ! -e "{dir}/end/$VERIFY_RUN/$2" ] || cp "{dir}/end/$VERIFY_RUN/$2" "{dir}/$VERIFY_RUN/$2.end.txt"
    echo "{dir}/$VERIFY_RUN/$2.take" ;;
esac
"""


class Film(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        fake = self.dir / "verify.sh"
        fake.write_text(FAKE_VERIFY.replace("{dir}", str(self.dir)))
        fake.chmod(0o755)
        (self.dir / "tree").write_text("AXButton\t\tSet 1, 185 x 5, logged\t\t@20,300 40x40\n"
                                       "AXButton\t\tSet 3, 195 x 5\t\t@120,300 40x40\n"
                                       "AXButton\tstage-queue-superset\tSuperset\t\t@334,432 44x44\n")
        self.saved = cardstill.VERIFY, cardstill.REST_END_AFTER_S, cardstill.PAIR_TAPS, cardstill.PAIR_WAIT_S
        cardstill.VERIFY, cardstill.REST_END_AFTER_S, cardstill.PAIR_WAIT_S = fake, 0.0, 0.0
        cardstill.PAIR_TAPS = tuple((ident, 0) for ident, _ in cardstill.PAIR_TAPS)
        cardstill.MERGED_ROW = (cardstill.MERGED_ROW[0], 0)

    def tearDown(self):
        cardstill.VERIFY, cardstill.REST_END_AFTER_S, cardstill.PAIR_TAPS, cardstill.PAIR_WAIT_S = self.saved

    def pair_taps(self, queue_tree):
        (self.dir / "tree").write_text((FIXTURES / queue_tree).read_text())
        with contextlib.redirect_stderr(io.StringIO()):
            cardstill.Side("lane-head", None).pair()
        return [c.split(" ", 1)[1] for c in (self.dir / "calls").read_text().splitlines() if " tap " in c]

    def test_an_app_after_ui_11_pairs_through_the_queue_s_superset_button(self):
        self.assertEqual(self.pair_taps("04-queue-superset.tree.txt"), [
            "tap --id stage-queue-button",
            "tap --id stage-queue-superset",
            "tap --id stage-queue-row-exercise-1",
        ])

    def test_an_app_before_ui_11_pairs_through_the_first_row_s_pair_button(self):
        self.assertEqual(self.pair_taps("03-queue.all.txt"), [
            "tap --id stage-queue-button",
            "tap --id stage-queue-pair-exercise-0",
            "tap --id stage-queue-row-exercise-1",
        ])

    def test_a_queue_that_stays_open_on_the_merged_row_gets_it_tapped_closed(self):
        row = "AXButton\tstage-queue-row-superset-0\tSuperset, Back Squat + BB RDL, Now\t\t@20,300 300x60\n"
        (self.dir / "tree").write_text((FIXTURES / "04-queue-superset.tree.txt").read_text() + row)
        with contextlib.redirect_stderr(io.StringIO()):
            cardstill.Side("lane-head", None).pair()
        taps = [c.split(" ", 1)[1] for c in (self.dir / "calls").read_text().splitlines() if " tap " in c]
        self.assertEqual(taps[-1], "tap --id stage-queue-row-superset-0")

    def test_pairing_opens_the_queue_then_reads_the_tree_until_the_sheet_shows_its_way_in(self):
        (self.dir / "tree.next").write_text((FIXTURES / "04-queue-superset.tree.txt").read_text())
        cardstill.PAIR_WAIT_S = 2.0
        self.pair_taps("01-before.tree.txt")
        self.assertEqual((self.dir / "calls").read_text().splitlines()[:4], [
            "lane-head tap --id stage-queue-button",
            "lane-head tree",
            "lane-head tree",
            "lane-head tap --id stage-queue-superset",
        ])

    def test_a_failed_tree_read_while_the_sheet_opens_is_read_again(self):
        (self.dir / "tree.fails").touch()
        cardstill.PAIR_WAIT_S = 2.0
        self.assertEqual(self.pair_taps("04-queue-superset.tree.txt")[1], "tap --id stage-queue-superset")

    def test_a_queue_with_neither_way_into_pairing_fails_the_setup_after_one_tap(self):
        with self.assertRaises(cardstill.SetupFailed) as raised:
            self.pair_taps("01-before.tree.txt")
        self.assertEqual(str(raised.exception),
                         "the queue showed neither stage-queue-superset (since UI-11 (#857)) nor "
                         "stage-queue-pair-exercise-0 (before UI-11, as every control whose card moves)")
        self.assertEqual([c for c in (self.dir / "calls").read_text().splitlines() if " tap " in c],
                         ["lane-head tap --id stage-queue-button"])

    def test_each_relaunch_stops_the_side_s_app_first_so_launch_is_never_refused(self):
        results = cardstill.Side("lane-control", "7fefd137").film()
        calls = (self.dir / "calls").read_text().splitlines()
        self.assertEqual([c for c in calls if " launch " in c or c.endswith(" stop")], [
            "lane-control stop",
            "lane-control stop",
            "lane-control launch --at 7fefd137 --animated session",
            "lane-control stop",
            "lane-control launch --at 7fefd137 --animated session",
            "lane-control stop",
        ])
        self.assertEqual([cardstill.measured(r).reason for r in results],
                         ["record exited 75"] * 7 + ["the Superset log take left no stamp to time the rest end from"])

    def test_every_take_on_both_sides_is_filmed_before_any_is_measured(self):
        (self.dir / "stamp.take").write_text("\n".join(take.take_lines(dataclasses.replace(TAKE, started=1000.0)) + [
            "screen_pt=200x400", "animations=on", "app="]) + "\n")
        calls = self.dir / "calls"

        def measure(video):
            with calls.open("a") as log:
                log.write(f"measure {video.parent.name}/{video.stem}\n")
            return cardframe.summarize(TAKE, [Sample(0.0, card(100), FLAT)], 0.0)

        self.addCleanup(setattr, cardframe, "measure", cardframe.measure)
        cardframe.measure = measure
        with mock.patch.dict(os.environ, {"SIM": "LANE", "VERIFY_RUN": "lane"}), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            code = cardstill.main(["--control", "7fefd137"])
        lines = calls.read_text().splitlines()
        kinds = ["measure" if line.startswith("measure ") else "record" for line in lines
                 if line.startswith("measure ") or line.split()[1] == "record"]
        self.assertEqual(kinds, ["record"] * 16 + ["measure"] * 16)
        self.assertEqual(lines[-1], "measure lane-head/superset-rest-end")
        self.assertEqual(code, 3)

    def test_only_the_after_rest_take_refuses_to_wait_for_the_host(self):
        (self.dir / "stamp.take").write_text("\n".join(take.take_lines(dataclasses.replace(TAKE, started=1000.0)) + [
            "screen_pt=200x400", "animations=on", "app="]) + "\n")
        self.addCleanup(setattr, cardframe, "measure", cardframe.measure)
        cardframe.measure = lambda video: cardframe.summarize(TAKE, [Sample(0.0, card(100), FLAT)], 0.0)
        env = {key: value for key, value in os.environ.items() if key != "WORKOUT_ADMIT_WAIT"}
        with mock.patch.dict(os.environ, dict(env, SIM="LANE", VERIFY_RUN="lane"), clear=True), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            cardstill.main(["--control", "7fefd137"])
        waits = [line.split() for line in (self.dir / "admit").read_text().splitlines()]
        self.assertEqual([wait for run, name, wait in waits if name != "superset-rest-end"], ["unset"] * 14)
        self.assertEqual([(run, wait) for run, name, wait in waits if name == "superset-rest-end"],
                         [("lane-control", "0"), ("lane-head", "0")])

    def lane(self, side, node_tap_ends_on):
        (self.dir / "stamp.take").write_text("\n".join(take.take_lines(dataclasses.replace(TAKE, started=1000.0)) + [
            "screen_pt=200x400", "animations=on", "app="]) + "\n")
        ends = [LOGGED, NODE_3, REVIEW, COLLAPSED, SWITCHED, PARTNER, SWITCHED, RESTED]
        for run in ("lane-control", "lane-head"):
            (self.dir / "end" / run).mkdir(parents=True)
            for spec, tree in zip(cardstill.TAKES, ends):
                (self.dir / "end" / run / spec.name).write_text(tree)
        (self.dir / "end" / side / "node-tap").write_text(node_tap_ends_on)

        def measure(video):
            moved = video.parent.name == "lane-control" and video.stem == "node-tap"
            return cardframe.summarize(TAKE, frames(*([card(80)] if moved else []), card(100), card(100)), 0.0)

        self.addCleanup(setattr, cardframe, "measure", cardframe.measure)
        cardframe.measure = measure
        out = io.StringIO()
        with mock.patch.dict(os.environ, {"SIM": "LANE", "VERIFY_RUN": "lane"}), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            code = cardstill.main(["--control", "7fefd137"])
        return code, out.getvalue().splitlines()[-1]

    def test_a_head_drive_that_left_the_screen_as_it_was_is_invalid_though_its_card_held_still(self):
        self.assertEqual(self.lane("lane-head", node_tap_ends_on=LOGGED), (
            3, 'cardstill INVALID: head node-tap: the take ended without "Set 3 of 3"'))

    def test_a_control_drive_that_did_not_land_is_invalid_though_its_card_moved(self):
        self.assertEqual(self.lane("lane-control", node_tap_ends_on=LOGGED), (
            3, 'cardstill INVALID: control node-tap: the take ended without "Set 3 of 3"'))

    def test_the_same_lane_passes_when_that_drive_landed(self):
        self.assertEqual(self.lane("lane-head", node_tap_ends_on=NODE_3), (
            0, "cardstill PASS: the head held the card still on every take; the control 7fefd137 moved it on 1"))
