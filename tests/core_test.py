#!/usr/bin/python3 -I
"""Reserve's conclusions and its file handling, on made-up days with known answers."""
from __future__ import annotations

import json
import os
import pathlib
import sys
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "app"))
import core  # noqa: E402
import store  # noqa: E402

T0 = int(time.mktime((2026, 10, 16, 8, 0, 0, 0, 0, -1)))


def sample(t, pct, mw, status="D", ac=False, gpu=False, lid=True, uah=5_000_000, mv=16_000):
    return {"t": t, "pct": pct, "mw": mw, "st": status, "ac": ac, "br": 60, "lid": lid, "gpu": gpu, "uah": uah, "mv": mv}


def minutes(start, count, pct=80, drop=0.1, mw=12_000):
    """`count` minutes on battery from `start`, losing `drop` percent a minute at `mw`."""
    return [sample(start + 60 * i, pct - i * drop, mw) for i in range(count)]


class Packing(unittest.TestCase):
    def test_a_sample_survives_the_round_trip_and_bad_rows_do_not(self):
        row = core.pack_sample({"t": T0, "pct": 64.5, "mw": 11800, "status": "Discharging", "ac": False, "br": 70,
                                "lid": True, "gpu": False, "uah": 5_100_000, "mv": 15_900})
        s = core.unpack_sample(json.loads(json.dumps(row)))
        self.assertEqual((s["pct"], s["mw"], s["st"], s["ac"], s["uah"]), (64.5, 11800, "D", False, 5_100_000))
        for bad in ([1, 2], "x", [T0, 2000, 0, "D", 0, 0, 1, 0, 0, 0], [T0, 500, 0, "Q", 0, 0, 1, 0, 0, 0],
                    [T0, 500, True, "D", 0, 0, 1, 0, 0, 0], [T0, 500, 9_000_000, "D", 0, 0, 1, 0, 0, 0]):
            self.assertIsNone(core.unpack_sample(bad), bad)

    def test_buckets_are_checked_and_names_cleaned(self):
        b = core.unpack_bucket({"t": T0, "dt": 600, "bat": {"brave": [1000, 50], "<b>x</b>": [5, 0], "bad": [1, -1]},
                                "ac": {"zed": [10, 0]}})
        self.assertEqual(set(b["bat"]), {"brave", "bx/b"})
        self.assertIsNone(core.unpack_bucket({"t": T0, "dt": 99999}))
        self.assertIsNone(core.unpack_bucket([]))


class Day(unittest.TestCase):
    def test_charging_and_sleep_spans(self):
        s = minutes(T0, 10) + [sample(T0 + 3600, 79, -30_000, "C", True)] + \
            [sample(T0 + 3600 + 60 * i, 79 + i, -30_000, "C", True) for i in range(1, 5)]
        sp = core.spans(s)
        self.assertEqual(sp["sleeping"], [[T0 + 540, T0 + 3600]])
        self.assertEqual(sp["charging"], [[T0 + 3600, T0 + 3600 + 240]])

    def test_the_level_chart_is_bounded_and_keeps_gaps(self):
        s = minutes(T0, 600) + minutes(T0 + 600 * 60 + 3600, 600)
        series = core.level_series(s, T0, T0 + 86400, points=100)
        self.assertLessEqual(len(series), 210)
        self.assertIn(None, [p[1] for p in series], "the sleep stays a gap")
        self.assertEqual(series[-1][0], s[-1]["t"])

    def test_since_unplugged(self):
        s = [sample(T0 + 60 * i, 80, -100, "N", True) for i in range(5)] + minutes(T0 + 300, 30, pct=80)
        self.assertEqual(core.last_unplug(s), {"t": T0 + 300, "pct": 80})
        self.assertIsNone(core.last_unplug(minutes(T0, 5)))


class Energy(unittest.TestCase):
    def test_drain_counts_battery_minutes_only(self):
        s = minutes(T0, 61, mw=12_000)              # an hour at 12 W
        self.assertAlmostEqual(core.drain_mwh(s, T0, T0 + 3600), 12_000, delta=1)
        s2 = minutes(T0, 31, mw=12_000) + minutes(T0 + 1800 + 7200, 31, mw=12_000)
        self.assertAlmostEqual(core.drain_mwh(s2, T0, T0 + 99999), 12_000, delta=1, msg="sleep is not drain")
        charging = [sample(T0 + 60 * i, 50, -40_000, "C", True) for i in range(61)]
        self.assertEqual(core.drain_mwh(charging, T0, T0 + 3600), 0)

    def test_sleep_cost(self):
        s = [sample(T0, 80, 9000), sample(T0 + 8 * 3600, 72, 9000)]
        c = core.sleep_cost(s)[0]
        self.assertEqual((c["hours"], c["lost"], c["perHour"]), (8.0, 8.0, 1.0))

    def test_apps_share_what_is_left_above_the_floor(self):
        # An hour at 20 W on battery whose quietest minutes ran at 8 W: 8 Wh is the floor, 12 Wh is shared 3:1.
        s = [sample(T0 + 60 * i, 80, 8_000 if i < 10 else 20_000) for i in range(61)]
        s = [dict(x, mw=20_000) for x in s]
        for x in s[:7]:
            x["mw"] = 8_000
        buckets = [{"t": T0 + 600 * k, "dt": 600, "bat": {"brave": [3000, 0], "zed": [500, 500]}, "ac": {}} for k in range(6)]
        u = core.usage_by_app(s, buckets, T0, T0 + 3600)
        names = [a["name"] for a in u["apps"]]
        self.assertEqual(names, ["Brave", "Zed"], "shown by the names people know")
        self.assertAlmostEqual(u["apps"][0]["mwh"] / u["apps"][1]["mwh"], 3.0, delta=0.01)
        total_share = sum(a["share"] for a in u["apps"]) + u["baseShare"]
        self.assertAlmostEqual(total_share, 100, delta=0.5)
        self.assertGreater(u["baseShare"], 0)

    def test_time_left_uses_the_recent_rate(self):
        s = minutes(T0, 30, mw=10_000)
        for x in s:
            x["uah"], x["mv"] = 5_000_000, 16_000           # 80 Wh left
        left = core.time_left(s)
        self.assertAlmostEqual(left["hours"], 8.0, delta=0.05)
        self.assertIsNone(core.time_left(minutes(T0, 3)))
        self.assertIsNone(core.time_left([sample(T0, 50, -1, "C", True)]))


class Words(unittest.TestCase):
    def test_insights_name_the_cause(self):
        s = [sample(T0 + 60 * i, 80 - i * 0.2, 25_000, gpu=True) for i in range(40)]
        s += [sample(T0 + 40 * 60 + 9 * 3600, 55, 9_000)]      # 17% in 9 h asleep
        u = {"apps": [{"name": "cs2", "share": 70.0}]}
        kinds = [i["kind"] for i in core.insights(s, u, T0, T0 + 86400)]
        self.assertEqual(kinds, ["dgpu", "sleep", "app"])
        self.assertIn("GPU who", core.insights(s, u, T0, T0 + 86400)[0]["text"])

    def test_charger_wattage_and_its_warning(self):
        self.assertEqual(core.charger({"volts": 20.0, "amps": 3.25}), {"watts": 65, "note": core.charger({"volts": 20, "amps": 3.25})["note"]})
        self.assertIn("GPU", core.charger({"volts": 20.0, "amps": 3.25})["note"])
        self.assertEqual(core.charger({"volts": 20.0, "amps": 5.0})["note"], "")
        self.assertIsNone(core.charger(None))

    def test_health_and_trend(self):
        h = core.health({"full": 7_806_000, "design": 7_737_000, "cycles": 112, "temperature": 29.8, "health": "Good"})
        self.assertEqual((h["capacity"], h["cycles"]), (100.9, 112))
        self.assertIsNone(core.health({})["capacity"])
        self.assertEqual(core.capacity_trend([{"d": "2026-10-16", "cap": 100.9}, {"bad": 1}]), [["2026-10-16", 100.9]])
        # A sampler restarted three times in a day logs three lines; the trend has one point for it.
        log = [{"d": "2026-10-16", "cap": 100.9}, {"d": "2026-10-16", "cap": 100.8}, {"d": "2026-10-15", "cap": 101.0}]
        self.assertEqual(core.capacity_trend(log), [["2026-10-15", 101.0], ["2026-10-16", 100.8]])

    def test_the_report_holds_together(self):
        s = [sample(T0 + 60 * i, 80 - i * 0.05, 12_000) for i in range(120)]
        r = core.report(s, [], T0 + 7200, "unplug", {"full": 1, "design": 1}, [], None)
        self.assertEqual(r["sinceLabel"], "Today")
        self.assertLessEqual(len(r["level"]), core.LEVEL_POINTS + 2)
        json.dumps(r)


class Files(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.old = os.environ.get("XDG_STATE_HOME")
        os.environ["XDG_STATE_HOME"] = self.tmp.name

    def tearDown(self):
        if self.old is None:
            os.environ.pop("XDG_STATE_HOME", None)
        else:
            os.environ["XDG_STATE_HOME"] = self.old
        self.tmp.cleanup()

    def test_appends_are_private_and_read_back(self):
        store.append("samples", "2026-10-16.jsonl", [1, 2])
        store.append("samples", "2026-10-16.jsonl", [3, 4])
        self.assertEqual(store.read_lines("samples", "2026-10-16.jsonl"), [[1, 2], [3, 4]])
        root = os.path.join(self.tmp.name, "reserve")
        self.assertEqual(os.stat(root).st_mode & 0o777, 0o700)
        self.assertEqual(os.stat(os.path.join(root, "samples", "2026-10-16.jsonl")).st_mode & 0o777, 0o600)

    def test_a_planted_link_is_neither_followed_nor_written(self):
        store.append("samples", "seed.jsonl", [0])
        target = os.path.join(self.tmp.name, "elsewhere")
        os.symlink(target, os.path.join(self.tmp.name, "reserve", "samples", "2026-10-17.jsonl"))
        with self.assertRaises(OSError):
            store.append("samples", "2026-10-17.jsonl", [1])
        self.assertFalse(os.path.exists(target))
        self.assertEqual(store.read_lines("samples", "2026-10-17.jsonl"), [])

    def test_a_shared_directory_is_refused(self):
        os.makedirs(os.path.join(self.tmp.name, "reserve"), mode=0o777)
        os.chmod(os.path.join(self.tmp.name, "reserve"), 0o777)
        with self.assertRaises(store.Unsafe):
            store.append("samples", "x.jsonl", [1])

    def test_reads_have_a_ceiling(self):
        store.append("samples", "big.jsonl", ["x" * 100])
        self.assertEqual(store.read_lines("samples", "big.jsonl", ceiling=10), [])

    def test_old_files_are_pruned_by_their_date(self):
        import datetime as dt
        for name in ("2026-08-01.jsonl", "2026-10-10.jsonl", "notes.txt"):
            store.append("samples", name, [1])
        gone = store.prune("samples", 30, dt.date(2026, 10, 16))
        self.assertEqual(gone, 1)
        left = sorted(os.listdir(os.path.join(self.tmp.name, "reserve", "samples")))
        self.assertEqual(left, ["2026-10-10.jsonl", "notes.txt"])


if __name__ == "__main__":
    unittest.main(verbosity=0)
