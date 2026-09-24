"""Regression tests for the BodyRadarReplay JSON importer. Run: python3 -m unittest Scripts.test_body_radar_replay"""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import body_radar_replay as replay  # noqa: E402


def _signal(kind, value, reason=None):
    return {"kind": kind, "value": value, "exclusionReason": reason, "valueReason": reason}


def _night(day, hr, rr, temp, hrv):
    return {"day": day, "rawState": "noSigns", "state": "noSigns", "rawEvidence": 0.0,
            "signals": [_signal("sleepingHeartRate", hr), _signal("respiratoryRate", rr),
                        _signal("wristTemperature", temp), _signal("heartRateVariability", hrv)]}


class LoadBodyTests(unittest.TestCase):
    def _write(self, recomputed):
        path = os.path.join(tempfile.mkdtemp(), "BodyRadarReplay-test.json")
        with open(path, "w") as handle:
            json.dump({"schemaVersion": 1, "meta": {}, "recomputed": recomputed, "recorded": []}, handle)
        return path

    def test_missing_sleep_row_stays_out_of_nights(self):
        recomputed = [_night(f"2026-08-{d:02d}", 55, 14, 35.7, 60) for d in range(1, 21)]
        missing = {"day": "2026-08-21", "rawState": "missingSleep", "state": "missingSleep",
                   "rawEvidence": None, "signals": [_signal(k, None, "notNight") for k in
                   ("sleepingHeartRate", "respiratoryRate", "wristTemperature", "heartRateVariability")]}
        timeline = replay.load_body([self._write(recomputed + [missing])])
        day = replay.parse_day("2026-08-21")
        self.assertNotIn(day, timeline["nights"])
        self.assertIn(day, timeline["days"])
        self.assertEqual(len(timeline["nights"]), 20)
        self.assertEqual(replay.Scorer(timeline, "bg").night(day)["state"], "missingSleep")

    def test_nap_only_today_marked_not_night_stays_out_of_nights(self):
        row = {"day": "2026-08-21", "rawState": "noSigns", "state": "noSigns", "rawEvidence": None,
               "signals": [_signal(k, None, "notNight") for k in
                           ("sleepingHeartRate", "respiratoryRate", "wristTemperature", "heartRateVariability")]}
        timeline = replay.load_body([self._write([row])])
        self.assertEqual(timeline["nights"], {})
        self.assertIn(replay.parse_day("2026-08-21"), timeline["days"])

    def test_scored_row_is_a_night(self):
        timeline = replay.load_body([self._write([_night("2026-08-21", 55, 14, 35.7, 60)])])
        day = replay.parse_day("2026-08-21")
        self.assertEqual(timeline["nights"][day]["values"], {"hr": 55, "rr": 14, "temp": 35.7, "hrv": 60})


if __name__ == "__main__":
    unittest.main()
