#!/usr/bin/env python3
"""Body Radar replay and Beta 3 analysis.

Standard library only. Reads exports in place and never writes into them.

Inputs
  --oura DIR    Oura export folder (the folder that holds "App Data", or
                "App Data" itself). Nightly source: sleepmodel.csv.
  --apple CSV   Apple Watch daily CSV (date, avg_heart_rate_bpm,
                resting_heart_rate_bpm, respiratory_rate_brpm,
                sleeping_wrist_temp_c, hrv_sdnn_ms, steps).
  --body JSON   Body's "Export Body Radar Replay" file (schemaVersion 1).

Every Oura and Apple number is a proxy for Body's real inputs:
  * Oura HRV is RMSSD; it is scored with Body's SDNN floor (5 ms) as a
    labeled cross statistic experiment.
  * Oura temperature_deviation is already normalized against Oura's own
    reference; it is re-baselined with Body's 0.2 floor as a proxy.
  * The Apple CSV holds daily aggregates (resting HR stands in for sleeping
    HR, daily SDNN for sleep window SDNN), not Body's sleep window inputs.

Subcommands: inventory, replay, compare, grid, oura-extras.
Run "python3 Scripts/body_radar_replay.py <subcommand> -h" for options.
"""

import argparse
import csv
import hashlib
import json
import math
import os
import sys
from collections import Counter, OrderedDict
from datetime import date, timedelta

csv.field_size_limit(sys.maxsize)

# ---------------------------------------------------------------------------
# Beta 2 constants, mirrored from BodyMetricsKit (BodyRadarCalculator.Tuning,
# VitalsCalculator, ReadinessScoreCalculator). Keep these in sync by hand.
# ---------------------------------------------------------------------------

SIGNALS = ("hr", "rr", "temp", "hrv")
SIGNAL_TITLES = {"hr": "HR", "rr": "RR", "temp": "Temp", "hrv": "HRV"}
FAMILIES = {"autonomic": ("hr", "hrv"), "respiratory": ("rr",), "thermal": ("temp",)}

BASELINE_DAYS = 56           # window [D-56, D)
RECENT_EXCLUSION_DAYS = 3    # drop [D-3, D) when >= 28 older values remain
RECENT_EXCLUSION_MINIMUM = 28
MINIMUM_BASELINE = 14
RECENCY_WINDOW = 14          # [D-13, D]
RECENCY_MINIMUM = 7
MINIMUM_SIGNALS = 2
MAD_SCALE = 1.4826
BAND_MULTIPLIER = 2.0        # one d unit is two robust spreads
DEVIATION_CAP = 3.0

BETA2_FLOORS = {"hr": 3.0, "rr": 0.6, "temp": 0.2, "hrv": 5.0}
LOW_FLOORS = {"hr": 1.5, "rr": 0.3, "temp": 0.1, "hrv": 5.0}


def params(**overrides):
    """Beta 2 scoring parameters, optionally overridden."""
    base = {
        "floors": dict(BETA2_FLOORS),
        "weights": {"hr": 1.0, "rr": 1.0, "temp": 1.5, "hrv": 1.0},
        "dead_zone": 0.5,
        "flag": 1.0,
        "minor": 0.75,
        "major": 2.0,
        "major_flags": 2,
        "rr_abs": False,             # candidate B
        "gate": False,               # candidate G
        "family_minimum": 0.25,      # G (a)
        "persistence": 0.75,         # G (b), equals minor
    }
    base.update(overrides)
    return base


RULES = {
    "beta2": params(),
    "b": params(rr_abs=True),
    "g": params(gate=True),
    "bg": params(rr_abs=True, gate=True),
}
RULE_NAMES = {"beta2": "Beta 2", "b": "B", "g": "G", "bg": "B+G"}
DEFAULT_LABELS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "body_radar_labels.csv")

ALERT_STATES = ("minorSigns", "majorSigns")
SCORED_STATES = ("noSigns",) + ALERT_STATES
STATE_SHORT = {
    "noSigns": "No", "minorSigns": "Minor", "majorSigns": "Major",
    "calibrating": "Calib", "insufficientData": "Insuff", "missingSleep": "Missing",
}
LABEL_TO_STATE = {"no signs": "noSigns", "minor": "minorSigns", "major": "majorSigns"}


def parse_day(text):
    return date.fromisoformat(text.strip()[:10])


def fmt(value, digits=3):
    if value is None:
        return "-"
    if isinstance(value, float):
        return f"{value:.{digits}f}"
    return str(value)


def median(values):
    ordered = sorted(values)
    count = len(ordered)
    if count == 0:
        return 0.0
    middle = count // 2
    if count % 2 == 0:
        return (ordered[middle - 1] + ordered[middle]) / 2
    return ordered[middle]


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def print_table(headers, rows, out=sys.stdout):
    """Plain aligned text table (pipe separated, readable as Markdown)."""
    rows = [[str(cell) for cell in row] for row in rows]
    widths = [len(h) for h in headers]
    for row in rows:
        for index, cell in enumerate(row):
            widths[index] = max(widths[index], len(cell))
    def line(cells):
        return "| " + " | ".join(c.ljust(widths[i]) for i, c in enumerate(cells)) + " |"
    print(line(headers), file=out)
    print("| " + " | ".join("-" * w for w in widths) + " |", file=out)
    for row in rows:
        print(line(row), file=out)


# ---------------------------------------------------------------------------
# Timelines
#
# A timeline is {"name", "nights": {day: Night}, "days": {day: note}} where a
# Night is {"values": {signal: float}, "excluded": {signal: reason},
# "raw": {...}}. A day that is in "days" but not in "nights" has no qualifying
# night; its note says why. Per-signal admission: a valid channel on a partial
# night enters later baselines; an invalid sentinel is dropped with a reason.
# ---------------------------------------------------------------------------


def oura_app_dir(path):
    path = os.path.expanduser(path)
    candidate = os.path.join(path, "App Data")
    return candidate if os.path.isdir(candidate) else path


def read_semicolon_csv(path):
    with open(path, newline="") as handle:
        return list(csv.DictReader(handle, delimiter=";"))


def number(text):
    if text is None:
        return None
    text = str(text).strip()
    if text == "" or text.lower() in ("none", "null", "nan"):
        return None
    try:
        value = float(text)
    except ValueError:
        return None
    return value if math.isfinite(value) else None


def admit(value, zero_is_sentinel=True):
    """(value, reason): a usable finite value, or None and why not."""
    if value is None:
        return None, "empty"
    if zero_is_sentinel and value == 0:
        return None, "sentinel 0"
    return value, None


def load_oura(path):
    app = oura_app_dir(path)
    rows = read_semicolon_csv(os.path.join(app, "sleepmodel.csv"))
    by_day = {}
    for row in rows:
        by_day.setdefault(parse_day(row["day"]), []).append(row)

    nights, days = {}, {}
    first, last = min(by_day), max(by_day)
    day = first
    while day <= last:
        candidates = [r for r in by_day.get(day, []) if r["type"] == "long_sleep"]
        if not candidates:
            others = by_day.get(day, [])
            if others:
                kinds = ", ".join(sorted({r["type"] for r in others}))
                days[day] = f"no long_sleep row ({len(others)} {kinds} row(s))"
            else:
                days[day] = "missing night (no sleepmodel row)"
            day += timedelta(days=1)
            continue
        # Main night: the long_sleep row with the longest total sleep.
        row = max(candidates, key=lambda r: number(r["total_sleep_duration"]) or 0)
        readiness = json.loads(row["readiness"]) if row["readiness"].strip() else {}
        temperature = readiness.get("temperature_deviation")
        admitted = {
            "hr": admit(number(row["average_heart_rate"])),
            "rr": admit(number(row["average_breath"])),
            # A 0.0 deviation is a real reading, only a missing one is invalid.
            "temp": admit(number(temperature), zero_is_sentinel=False),
            "hrv": admit(number(row["average_hrv"])),
        }
        nights[day] = {
            "values": {s: v for s, (v, _) in admitted.items() if v is not None},
            "excluded": {s: r for s, (_, r) in admitted.items() if r is not None},
            "raw": {
                "lowest_hr": number(row["lowest_heart_rate"]),
                "total_sleep_s": number(row["total_sleep_duration"]),
                "bedtime_start": row["bedtime_start"],
                "rows_on_day": len(by_day[day]),
            },
        }
        days[day] = "main night" if not nights[day]["excluded"] else (
            "partial channels: " + ", ".join(
                f"{SIGNAL_TITLES[s]} {r}" for s, r in nights[day]["excluded"].items()))
        day += timedelta(days=1)
    return {"name": "Oura", "nights": nights, "days": days}


APPLE_COLUMNS = {
    "hr": "resting_heart_rate_bpm",
    "rr": "respiratory_rate_brpm",
    "temp": "sleeping_wrist_temp_c",
    "hrv": "hrv_sdnn_ms",
}


def load_apple(path):
    with open(os.path.expanduser(path), newline="") as handle:
        rows = list(csv.DictReader(handle))
    nights, days = {}, {}
    for row in rows:
        day = parse_day(row["date"])
        admitted = {s: admit(number(row.get(c))) for s, c in APPLE_COLUMNS.items()}
        nights[day] = {
            "values": {s: v for s, (v, _) in admitted.items() if v is not None},
            "excluded": {s: r for s, (_, r) in admitted.items() if r is not None},
            "raw": {"avg_hr": number(row.get("avg_heart_rate_bpm")), "steps": number(row.get("steps"))},
        }
        days[day] = "daily row" if not nights[day]["excluded"] else (
            "partial channels: " + ", ".join(
                f"{SIGNAL_TITLES[s]} {r}" for s, r in nights[day]["excluded"].items()))
    return {"name": "Apple", "nights": nights, "days": days}


BODY_KIND_ALIASES = {
    "sleepingheartrate": "hr", "heartrate": "hr", "hr": "hr",
    "respiratoryrate": "rr", "rr": "rr",
    "wristtemperature": "temp", "temperature": "temp", "temp": "temp",
    "heartratevariability": "hrv", "hrv": "hrv",
}


def load_body(paths):
    """Tolerant loader for BodyRadarReplay JSON (schemaVersion 1).

    Reads only recomputed[].day and each signal's value; everything else is
    optional. Later files override earlier ones for the same day. If a night
    carries rawEvidence (or evidence), it is kept for a parity column.
    """
    nights, days, metas, recorded = {}, {}, [], 0
    for path in sorted(os.path.expanduser(p) for p in paths):
        with open(path) as handle:
            payload = json.load(handle)
        metas.append((os.path.basename(path), payload.get("schemaVersion"), payload.get("meta") or {}))
        recorded += len(payload.get("recorded") or [])
        for entry in payload.get("recomputed") or []:
            if not isinstance(entry, dict) or not entry.get("day"):
                continue
            day = parse_day(entry["day"])
            signals = entry.get("signals") or {}
            if isinstance(signals, list):
                signals = {s.get("kind", ""): s for s in signals if isinstance(s, dict)}
            values, excluded = {}, {}
            for kind, payload_signal in signals.items():
                signal = BODY_KIND_ALIASES.get(str(kind).replace("_", "").lower())
                if signal is None:
                    continue
                raw = payload_signal.get("value") if isinstance(payload_signal, dict) else payload_signal
                value = number(raw)
                if value is None:
                    reason = payload_signal.get("exclusionReason") if isinstance(payload_signal, dict) else None
                    excluded[signal] = reason or "null"
                else:
                    values[signal] = value
            for signal in SIGNALS:
                if signal not in values and signal not in excluded:
                    excluded[signal] = "absent"
            recorded_evidence = entry.get("rawEvidence", entry.get("evidence"))
            # A row the app could not treat as a night (Missing Sleep, or a nap-only
            # today marked notNight) stays in days but never becomes a night, so the
            # offline availability counts match the export.
            raw_state = entry.get("rawState") or entry.get("state")
            not_night = raw_state == "missingSleep" or (
                values == {} and excluded and all(r == "notNight" for r in excluded.values()))
            if not_night:
                days[day] = "exported row without a qualifying night (Missing Sleep)"
                nights.pop(day, None)
                continue
            nights[day] = {
                "values": values,
                "excluded": excluded,
                "raw": {"exported_evidence": number(recorded_evidence),
                        "exported_state": entry.get("state") or entry.get("gatedState")},
            }
            days[day] = "exported night"
    return {"name": "Body", "nights": nights, "days": days, "metas": metas, "recorded": recorded}


def without_signal(timeline, signal):
    """Copy of a timeline with one sensor removed everywhere."""
    nights = {}
    for day, night in timeline["nights"].items():
        values = {s: v for s, v in night["values"].items() if s != signal}
        excluded = dict(night["excluded"])
        excluded[signal] = "removed"
        nights[day] = {"values": values, "excluded": excluded, "raw": night["raw"]}
    return {"name": f"{timeline['name']} without {SIGNAL_TITLES[signal]}",
            "nights": nights, "days": timeline["days"]}


# ---------------------------------------------------------------------------
# Scoring, mirroring BodyRadarCalculator.Context.night(on:)
# ---------------------------------------------------------------------------


class Scorer:
    def __init__(self, timeline, rules):
        self.timeline = timeline
        self.rules = rules
        self.series = {s: {} for s in SIGNALS}
        for day, night in timeline["nights"].items():
            for signal, value in night["values"].items():
                self.series[signal][day] = value
        self.sorted_days = {s: sorted(self.series[s]) for s in SIGNALS}
        self._raw = {}

    def baseline(self, signal, day):
        days = self.sorted_days[signal]
        oldest = day - timedelta(days=BASELINE_DAYS)
        cutoff = day - timedelta(days=RECENT_EXCLUSION_DAYS)
        window = [d for d in days if oldest <= d < day]
        older = [d for d in window if d < cutoff]
        chosen = older if len(older) >= RECENT_EXCLUSION_MINIMUM else window
        if len(chosen) < MINIMUM_BASELINE:
            return None
        values = [self.series[signal][d] for d in chosen]
        center = median(values)
        raw_spread = MAD_SCALE * median([abs(v - center) for v in values])
        floor = self.rules["floors"][signal]
        return {"median": center, "raw_spread": raw_spread, "spread": max(raw_spread, floor),
                "floor": floor, "floor_bound": raw_spread < floor, "count": len(values)}

    def recent_count(self, signal, day):
        start = day - timedelta(days=RECENCY_WINDOW - 1)
        return sum(1 for d in self.sorted_days[signal] if start <= d <= day)

    def raw_night(self, day):
        """Beta 2 style verdict before the corroboration gate (memoized)."""
        if day in self._raw:
            return self._raw[day]
        result = self._score(day)
        self._raw[day] = result
        return result

    def _score(self, day):
        night = self.timeline["nights"].get(day)
        result = {"day": day, "signals": {}, "evidence": None, "flags": 0,
                  "raw_state": "missingSleep", "state": "missingSleep", "corroboration": None}
        if night is None:
            result["reason"] = self.timeline["days"].get(day, "no night")
            return result
        rules = self.rules
        calibrated, scored = 0, []
        for signal in SIGNALS:
            info = {"value": night["values"].get(signal)}
            baseline = self.baseline(signal, day) if self.series[signal] else None
            if baseline is None:
                info["reason"] = "noBaseline"
                result["signals"][signal] = info
                continue
            info.update(baseline)
            if self.recent_count(signal, day) < RECENCY_MINIMUM:
                info["reason"] = "sparseRecent"
                result["signals"][signal] = info
                continue
            calibrated += 1
            if info["value"] is None:
                info["reason"] = "noCurrentValue (" + night["excluded"].get(signal, "absent") + ")"
                result["signals"][signal] = info
                continue
            band = BAND_MULTIPLIER * baseline["spread"]
            d = (info["value"] - baseline["median"]) / band if band > 0 else 0.0
            d = max(-DEVIATION_CAP, min(DEVIATION_CAP, d))
            if signal == "hrv":
                directional = -d
            elif signal == "rr" and rules["rr_abs"]:
                directional = abs(d)
            else:
                directional = d
            info["d"] = d
            info["directional"] = directional
            info["contribution"] = rules["weights"][signal] * max(0.0, directional - rules["dead_zone"])
            info["flagged"] = directional > rules["flag"]
            info["reason"] = None
            scored.append(signal)
            result["signals"][signal] = info

        if calibrated < MINIMUM_SIGNALS:
            result["raw_state"] = result["state"] = "calibrating"
            return result
        if len(scored) < MINIMUM_SIGNALS:
            result["raw_state"] = result["state"] = "insufficientData"
            return result
        evidence = sum(result["signals"][s]["contribution"] for s in scored)
        flags = sum(1 for s in scored if result["signals"][s]["flagged"])
        if evidence >= rules["major"] and flags >= rules["major_flags"]:
            state = "majorSigns"
        elif evidence >= rules["minor"]:
            state = "minorSigns"
        else:
            state = "noSigns"
        result.update(evidence=evidence, flags=flags, raw_state=state, state=state)
        result["families"] = {
            family: sum(result["signals"][s].get("contribution", 0.0) for s in members
                        if result["signals"].get(s, {}).get("contribution") is not None)
            for family, members in FAMILIES.items()
        }
        return result

    def night(self, day):
        """Gated verdict: raw night plus one lookup of the previous raw night."""
        raw = self.raw_night(day)
        result = dict(raw)
        if raw["raw_state"] not in SCORED_STATES:
            return result
        corroborated_families = sum(
            1 for value in raw["families"].values() if value >= self.rules["family_minimum"])
        previous = self.raw_night(day - timedelta(days=1))
        if corroborated_families >= 2:
            corroboration = "sameNight"
        elif previous["raw_state"] in SCORED_STATES and previous["evidence"] >= self.rules["persistence"]:
            corroboration = "persistence"
        else:
            corroboration = "none"
        result["corroboration"] = corroboration
        if self.rules["gate"] and raw["raw_state"] in ALERT_STATES and corroboration == "none":
            result["state"] = "noSigns"
        return result


def score_timeline(timeline, rules, start=None, end=None):
    scorer = Scorer(timeline, rules)
    all_days = sorted(set(timeline["days"]) | set(timeline["nights"]))
    if not all_days:
        return OrderedDict()
    start = start or all_days[0]
    end = end or all_days[-1]
    results = OrderedDict()
    day = start
    while day <= end:
        results[day] = scorer.night(day)
        day += timedelta(days=1)
    return results


# ---------------------------------------------------------------------------
# Labels
# ---------------------------------------------------------------------------


def load_labels(path):
    labels = OrderedDict()
    with open(os.path.expanduser(path), newline="") as handle:
        for row in csv.DictReader(handle):
            labels[parse_day(row["date"])] = {
                "label": row["label"].strip(),
                "state": LABEL_TO_STATE.get(row["label"].strip().lower()),
                "provenance": row["provenance"].strip(),
                "source": row["source_file"].strip(),
                "note": row.get("note", "").strip(),
            }
    return labels


# ---------------------------------------------------------------------------
# Summaries
# ---------------------------------------------------------------------------


def episodes(days):
    """Runs of consecutive calendar days."""
    runs = []
    for day in sorted(days):
        if runs and day - runs[-1][-1] == timedelta(days=1):
            runs[-1].append(day)
        else:
            runs.append([day])
    return runs


def short(day):
    return day.strftime("%b %d").replace(" 0", " ")


def describe_runs(runs):
    parts = []
    for run in runs:
        parts.append(short(run[0]) if len(run) == 1 else f"{short(run[0])} to {short(run[-1])}")
    return ", ".join(parts) if parts else "none"


def summarize(results):
    states = Counter(r["state"] for r in results.values())
    alerts = [d for d, r in results.items() if r["state"] in ALERT_STATES]
    held = [d for d, r in results.items()
            if r["raw_state"] in ALERT_STATES and r["state"] not in ALERT_STATES]
    runs = episodes(alerts)
    return {
        "scored": sum(states[s] for s in SCORED_STATES),
        "states": states,
        "alerts": alerts,
        "minor": states["minorSigns"],
        "major": states["majorSigns"],
        "episodes": runs,
        "isolated": sum(1 for run in runs if len(run) == 1),
        "held": held,
        "persistence": [d for d, r in results.items()
                        if r["state"] in ALERT_STATES and r.get("corroboration") == "persistence"],
    }


def agreement(results, labels):
    """Explicit and inferred label agreement, plus labeled dates not scored."""
    explicit, inferred, excluded = [], [], []
    for day, label in labels.items():
        result = results.get(day)
        if result is None or result["state"] not in SCORED_STATES:
            reason = "outside timeline" if result is None else STATE_SHORT[result["state"]]
            if result is not None and result["state"] == "missingSleep":
                reason = result.get("reason", "missing")
            excluded.append((day, label, reason))
            continue
        entry = (day, label, result)
        (explicit if label["provenance"] == "explicit" else inferred).append(entry)
    detected = [e for e in explicit if e[2]["state"] in ALERT_STATES]
    exact = [e for e in explicit if e[2]["state"] == e[1]["state"]]
    inferred_no = [e for e in inferred if e[1]["state"] == "noSigns"]
    inferred_ok = [e for e in inferred_no if e[2]["state"] == "noSigns"]
    return {
        "explicit": explicit, "detected": detected, "exact": exact,
        "inferred_no": inferred_no, "inferred_ok": inferred_ok,
        "inferred_alerts": [e[0] for e in inferred_no if e[2]["state"] in ALERT_STATES],
        "excluded": excluded,
    }


# ---------------------------------------------------------------------------
# Subcommand: inventory
# ---------------------------------------------------------------------------


def count_rows(path, delimiter):
    with open(path, newline="") as handle:
        return max(0, sum(1 for _ in csv.reader(handle, delimiter=delimiter)) - 1)


def spread_table(timeline):
    """Per scored night, per channel raw and effective spread (Beta 2 floors)."""
    results = score_timeline(timeline, RULES["beta2"])
    rows, binding = [], {s: [0, 0, []] for s in SIGNALS}
    for day, result in results.items():
        if result["state"] not in SCORED_STATES:
            continue
        cells = [day.isoformat()]
        for signal in SIGNALS:
            info = result["signals"].get(signal, {})
            if info.get("contribution") is None:
                cells.append("-")
                continue
            binding[signal][1] += 1
            binding[signal][2].append(info["raw_spread"])
            if info["floor_bound"]:
                binding[signal][0] += 1
            cells.append(f"{info['raw_spread']:.3f}/{info['spread']:.3f}{'*' if info['floor_bound'] else ''}")
        rows.append(cells)
    return rows, binding


def print_binding(name, binding):
    print(f"\nFloor binding, {name} (scored channel-nights where raw spread < floor):")
    table = []
    for signal in SIGNALS:
        bound, total, spreads = binding[signal]
        if total == 0:
            table.append([SIGNAL_TITLES[signal], BETA2_FLOORS[signal], "0/0", "-", "-"])
            continue
        table.append([SIGNAL_TITLES[signal], BETA2_FLOORS[signal], f"{bound}/{total}",
                      f"{median(spreads):.6f}", f"{min(spreads):.6f} to {max(spreads):.6f}"])
    print_table(["Signal", "Floor", "Floor binds", "Median raw spread", "Raw spread range"], table)


def cmd_inventory(args):
    if args.oura:
        app = oura_app_dir(args.oura)
        print(f"Oura export: {app}")
        print("(Only 'App Data' is inventoried. The Subscriptions folder holds account and payment files and is skipped.)\n")
        files = []
        for name in sorted(os.listdir(app)):
            path = os.path.join(app, name)
            if os.path.isfile(path) and name.endswith(".csv"):
                files.append([name, count_rows(path, ";"), os.path.getsize(path), sha256(path)])
        print_table(["File", "Data rows", "Bytes", "SHA-256"], files)
        empty = [f[0] for f in files if f[1] == 0]
        print(f"\nEmpty files ({len(empty)}): {', '.join(empty)}")
        events = os.path.join(os.path.dirname(app), "Partner Event Store", "events.ndjson")
        if os.path.exists(events):
            print(f"Partner Event Store/events.ndjson: {os.path.getsize(events)} bytes")

        rows = read_semicolon_csv(os.path.join(app, "sleepmodel.csv"))
        types = Counter(r["type"] for r in rows)
        long_days = {r["day"] for r in rows if r["type"] == "long_sleep"}
        all_days = sorted({r["day"] for r in rows})
        print(f"\nsleepmodel.csv: {len(rows)} data rows; types {dict(types)}; "
              f"{types['long_sleep']} long_sleep rows on {len(long_days)} dates; "
              f"days {all_days[0]} to {all_days[-1]}")

        oura = load_oura(args.oura)
        complete = [d for d, n in oura["nights"].items() if len(n["values"]) == 4]
        print(f"Main nights: {len(oura['nights'])}; complete four-signal main nights: {len(complete)}")
        print("\nExclusion inventory, Oura (every day that is not a complete main night):")
        table = []
        for day in sorted(oura["days"]):
            note = oura["days"][day]
            if note == "main night":
                continue
            other = [r for r in rows if parse_day(r["day"]) == day and r["type"] != "long_sleep"]
            detail = "; ".join(
                f"{r['type']} {int(number(r['total_sleep_duration']) or 0)}s "
                f"RR {r['average_breath'] or '-'} HR {r['average_heart_rate'] or '-'} HRV {r['average_hrv'] or '-'}"
                for r in other)
            if day in oura["nights"]:
                values = oura["nights"][day]["values"]
                detail = "valid: " + ", ".join(f"{SIGNAL_TITLES[s]} {v}" for s, v in values.items())
            table.append([day.isoformat(), note, detail or "-"])
        print_table(["Day", "Status", "Detail"], table)

        results = score_timeline(oura, RULES["beta2"])
        states = Counter(r["state"] for r in results.values())
        print(f"\nBeta 2 sufficiency on Oura main nights: scored {sum(states[s] for s in SCORED_STATES)}; "
              + ", ".join(f"{STATE_SHORT[k]} {v}" for k, v in sorted(states.items())))

        tz_rows = read_semicolon_csv(os.path.join(app, "timezone.csv"))
        print("\nTime zones (timezone.csv, identifiers and offsets retained):")
        table = []
        for index, row in enumerate(tz_rows):
            until = tz_rows[index + 1]["timestamp"][:10] if index + 1 < len(tz_rows) else "export end"
            table.append([row["timestamp"], row["identifier"], row["offset"],
                          f"UTC{int(row['offset']) / 3600:+.0f}", until])
        print_table(["Recorded (UTC)", "Identifier", "Offset s", "Offset", "Until"], table)
        offsets = Counter(n["raw"]["bedtime_start"][-6:] for n in oura["nights"].values())
        print("Main nights by bedtime_start offset: " + ", ".join(f"{k} {v}" for k, v in sorted(offsets.items())))

        spreads, binding = spread_table(oura)
        print_binding("Oura proxy", binding)
        if args.spread_days:
            print("\nPer-day spread, Oura (raw/effective, * = floor bound):")
            print_table(["Day"] + [SIGNAL_TITLES[s] for s in SIGNALS], spreads)

    if args.apple:
        path = os.path.expanduser(args.apple)
        apple = load_apple(path)
        print(f"\nApple CSV: {path}")
        print(f"SHA-256 {sha256(path)}; {count_rows(path, ',')} data rows; "
              f"{min(apple['nights'])} to {max(apple['nights'])}")
        missing = Counter()
        for night in apple["nights"].values():
            for signal in night["excluded"]:
                missing[signal] += 1
        print("Blank channel-days: " + ", ".join(f"{SIGNAL_TITLES[s]} {missing[s]}" for s in SIGNALS))
        results = score_timeline(apple, RULES["beta2"])
        states = Counter(r["state"] for r in results.values())
        print(f"Beta 2 sufficiency on Apple daily rows: scored {sum(states[s] for s in SCORED_STATES)}; "
              + ", ".join(f"{STATE_SHORT[k]} {v}" for k, v in sorted(states.items())))
        spreads, binding = spread_table(apple)
        print_binding("Apple proxy", binding)
        if args.spread_days:
            print("\nPer-day spread, Apple (raw/effective, * = floor bound):")
            print_table(["Day"] + [SIGNAL_TITLES[s] for s in SIGNALS], spreads)


# ---------------------------------------------------------------------------
# Subcommand: replay
# ---------------------------------------------------------------------------


def night_rows(results, labels=None, start=None, end=None):
    rows = []
    for day, result in results.items():
        if (start and day < start) or (end and day > end):
            continue
        cells = [day.isoformat()]
        for signal in SIGNALS:
            info = result["signals"].get(signal)
            if info is None:
                cells.append("-")
            elif info.get("contribution") is None:
                value = fmt(info.get("value"), 2)
                cells.append(f"{value} [{info.get('reason')}]")
            else:
                arrow = "+" if info["d"] > 0 else ""
                cells.append(f"{info['value']:.2f} m{info['median']:.2f} s{info['spread']:.2f} "
                             f"d{arrow}{info['d']:.2f} c{info['contribution']:.2f}"
                             + ("!" if info["flagged"] else ""))
        cells.append(fmt(result["evidence"], 3))
        cells.append(result["flags"] if result["evidence"] is not None else "-")
        cells.append(STATE_SHORT[result["raw_state"]])
        cells.append(result.get("corroboration") or "-")
        verdict = STATE_SHORT[result["state"]]
        if result.get("reason") and result["state"] == "missingSleep":
            verdict += f" ({result['reason']})"
        cells.append(verdict)
        if labels is not None:
            label = labels.get(day)
            cells.append(f"{label['label']} ({label['provenance'][0]})" if label else "")
        rows.append(cells)
    return rows


NIGHT_HEADERS = (["Day"] + [f"{SIGNAL_TITLES[s]} value m(edian) s(pread) d c(ontribution)" for s in SIGNALS]
                 + ["Raw evidence", "Flags", "Raw", "Corroboration", "Verdict"])


def load_timelines(args):
    timelines = []
    if getattr(args, "oura", None):
        timelines.append(load_oura(args.oura))
    if getattr(args, "apple", None):
        timelines.append(load_apple(args.apple))
    if getattr(args, "body", None):
        timelines.append(load_body(args.body))
    if not timelines:
        sys.exit("Give at least one of --oura, --apple, --body.")
    return timelines


def cmd_replay(args):
    labels = load_labels(args.labels) if args.labels else None
    start = parse_day(args.start) if args.start else None
    end = parse_day(args.end) if args.end else None
    rules = RULES[args.rules]
    for timeline in load_timelines(args):
        results = score_timeline(timeline, rules)
        print(f"\n## {timeline['name']} replay, rules {RULE_NAMES[args.rules]}")
        if timeline["name"] == "Body":
            for name, schema, meta in timeline["metas"]:
                print(f"{name}: schemaVersion {schema}; meta keys {sorted(meta)}")
            print(f"recorded nights in export: {timeline['recorded']} (not rescored)")
            first = min(timeline["nights"]) if timeline["nights"] else None
            if first:
                print(f"Warm-up: earliest exported night {first}; baselines need 56 days before a comparison date.")
        headers = NIGHT_HEADERS + (["Label"] if labels is not None else [])
        rows = night_rows(results, labels if timeline["name"] == "Oura" else None, start, end)
        if timeline["name"] != "Oura" and labels is not None:
            headers = NIGHT_HEADERS
        if timeline["name"] == "Body":
            headers = headers + ["Exported evidence", "Delta"]
            for row, (day, result) in zip(rows, [(d, r) for d, r in results.items()
                                                  if not ((start and d < start) or (end and d > end))]):
                night = timeline["nights"].get(day)
                exported = night["raw"]["exported_evidence"] if night else None
                delta = (result["evidence"] - exported) if (exported is not None and result["evidence"] is not None) else None
                row.extend([fmt(exported, 4), fmt(delta, 6)])
        if args.csv:
            writer = csv.writer(sys.stdout)
            writer.writerow(headers)
            writer.writerows(rows)
        else:
            print_table(headers, rows)
        summary = summarize(results)
        print(f"\nScored {summary['scored']}; alerts {len(summary['alerts'])} "
              f"(Minor {summary['minor']}, Major {summary['major']}); "
              f"episodes {len(summary['episodes'])} ({summary['isolated']} single-night); "
              f"held by the gate {len(summary['held'])}")
        print("Alerts: " + describe_runs(summary["episodes"]))
        if summary["held"]:
            print("Held: " + ", ".join(short(d) for d in summary["held"]))
        if rules["gate"] and summary["persistence"]:
            print("Alerts via persistence: " + ", ".join(short(d) for d in summary["persistence"]))


# ---------------------------------------------------------------------------
# Subcommand: compare
# ---------------------------------------------------------------------------


def cmd_compare(args):
    labels = load_labels(args.labels)
    variants = args.rules or ["beta2", "b", "g", "bg"]
    explicit = [d for d, l in labels.items() if l["provenance"] == "explicit"]
    inferred = [d for d, l in labels.items() if l["provenance"] != "explicit"]
    print(f"Labels: {len(explicit)} explicit, {len(inferred)} inferred ({args.labels})")

    for timeline in load_timelines(args):
        name = timeline["name"]
        print(f"\n## {name}" + ("" if name == "Oura" else " (labels are Oura's verdicts; cross-device context only)"))
        runs = {}
        table = []
        for variant in variants:
            results = score_timeline(timeline, RULES[variant])
            runs[variant] = results
            summary = summarize(results)
            agree = agreement(results, labels)
            states = summary["states"]
            table.append([
                RULE_NAMES[variant],
                summary["scored"],
                f"{states['calibrating']}/{states['insufficientData']}/{states['missingSleep']}",
                f"{len(summary['alerts'])} ({summary['minor']}/{summary['major']})",
                f"{len(summary['episodes'])} ({summary['isolated']} single)",
                len(summary["held"]),
                f"{len(agree['detected'])}/{len(agree['explicit'])}",
                f"{len(agree['exact'])}/{len(agree['explicit'])}",
                f"{len(agree['inferred_ok'])}/{len(agree['inferred_no'])}",
            ])
        print_table(["Rules", "Scored", "Calib/Insuff/Missing", "Alerts (Minor/Major)", "Episodes",
                     "Held", "Explicit alerted", "Explicit exact", "Inferred No agree"], table)

        for variant in variants:
            summary = summarize(runs[variant])
            agree = agreement(runs[variant], labels)
            print(f"\n{RULE_NAMES[variant]} alerts: {describe_runs(summary['episodes'])}")
            if summary["held"]:
                print(f"  held: {', '.join(short(d) for d in summary['held'])}")
            if RULES[variant]["gate"] and summary["persistence"]:
                print(f"  via persistence: {', '.join(short(d) for d in summary['persistence'])}")
            print(f"  alerts on inferred No-signs dates: {', '.join(short(d) for d in agree['inferred_alerts']) or 'none'}")

        agree = agreement(runs[variants[0]], labels)
        print("\nLabeled dates excluded by eligibility:")
        print_table(["Day", "Label", "Provenance", "Reason"],
                    [[d.isoformat(), l["label"], l["provenance"], reason] for d, l, reason in agree["excluded"]])

        print("\nExplicit label dates (raw evidence and verdict per rules):")
        rows = []
        for day in explicit:
            row = [day.isoformat(), labels[day]["label"]]
            for variant in variants:
                result = runs[variant].get(day)
                if result is None:
                    row.append("-")
                else:
                    row.append(f"{fmt(result['evidence'], 3)} {STATE_SHORT[result['state']]}")
            rows.append(row)
        print_table(["Day", "Oura"] + [RULE_NAMES[v] for v in variants], rows)

        print("\nPer-sensor removal (alerts / scored; alert dates added or lost versus all sensors):")
        rows = []
        for variant in variants:
            base = set(summarize(runs[variant])["alerts"])
            for signal in SIGNALS:
                reduced = score_timeline(without_signal(timeline, signal), RULES[variant])
                summary = summarize(reduced)
                now = set(summary["alerts"])
                added = sorted(now - base)
                lost = sorted(base - now)
                rows.append([RULE_NAMES[variant], f"without {SIGNAL_TITLES[signal]}",
                             f"{len(now)} / {summary['scored']}",
                             ", ".join(short(d) for d in added) or "-",
                             ", ".join(short(d) for d in lost) or "-"])
        print_table(["Rules", "Removed", "Alerts / scored", "Added", "Lost"], rows)

    if args.body_chart:
        chart = load_labels(args.body_chart)
        print(f"\nBody chart inferences ({args.body_chart}) versus the Apple proxy:")
        if not args.apple:
            print("  (needs --apple)")
            return
        apple = load_apple(args.apple)
        rows = []
        for day, label in chart.items():
            row = [day.isoformat(), label["label"]]
            for variant in variants:
                result = score_timeline(apple, RULES[variant]).get(day)
                row.append(f"{fmt(result['evidence'], 3)} {STATE_SHORT[result['state']]}" if result else "-")
            rows.append(row)
        print_table(["Day", "Body chart"] + [RULE_NAMES[v] for v in variants], rows)


# ---------------------------------------------------------------------------
# Subcommand: grid
# ---------------------------------------------------------------------------

GRID = {
    "floors": ("beta2", "low"),
    "dead_zone": (0.25, 0.5),
    "rr_abs": (False, True),
    "temp_weight": (1.0, 1.5),
    "k": (1, 2, 3, 4, 5, 7),
    "aggregator": ("sum", "ewma"),
    "lag": (0, 1, 2),
    "minor": (0.5, 0.75, 1.0, 1.5, 2.0),
    "major": (2.0, 3.0, 4.0, 6.0),
}


def aggregate(raw, days, aggregator, k):
    """Aggregate raw evidence over calendar days; unscored days add 0.

    sum:  sum of raw evidence over [D-k+1, D].
    ewma: e(D) = lam * e(D-1) + (1 - lam) * x(D), lam = 1 - 1/k, decaying
          once per calendar day (an unscored day has x = 0).
    """
    out = {}
    if aggregator == "sum":
        for day in days:
            out[day] = sum(raw.get(day - timedelta(days=i), 0.0) for i in range(k))
    else:
        lam = 1 - 1 / k
        level = 0.0
        for day in days:
            level = lam * level + (1 - lam) * raw.get(day, 0.0)
            out[day] = level
    return out


def cmd_grid(args):
    labels = load_labels(args.labels)
    oura = load_oura(args.oura)
    base = score_timeline(oura, RULES["beta2"])
    days = list(base)
    eligible = {d for d, r in base.items() if r["state"] in SCORED_STATES}
    labeled = [(d, l) for d, l in labels.items() if d in eligible and l["state"]]
    explicit = [d for d, l in labeled if l["provenance"] == "explicit"]
    inferred_no = [d for d, l in labeled if l["provenance"] != "explicit" and l["state"] == "noSigns"]
    label_state = {d: l["state"] for d, l in labeled}

    # Raw evidence per evidence-shaping combination.
    evidence_sets = {}
    for floors in GRID["floors"]:
        floor_values = BETA2_FLOORS if floors == "beta2" else LOW_FLOORS
        for dz in GRID["dead_zone"]:
            for rr_abs in GRID["rr_abs"]:
                for tw in GRID["temp_weight"]:
                    rules = params(floors=dict(floor_values), dead_zone=dz, rr_abs=rr_abs,
                                   weights={"hr": 1.0, "rr": 1.0, "temp": tw, "hrv": 1.0})
                    results = score_timeline(oura, rules)
                    evidence_sets[(floors, dz, rr_abs, tw)] = {
                        d: r["evidence"] for d, r in results.items() if r["state"] in SCORED_STATES}

    threshold_pairs = [(mi, ma) for mi in GRID["minor"] for ma in GRID["major"] if ma > mi]
    temporal = [(1, "sum")] + [(k, agg) for k in GRID["k"] if k > 1 for agg in GRID["aggregator"]]
    candidates = []
    for key, raw in evidence_sets.items():
        for k, agg in temporal:
            series = aggregate(raw, days, agg, k)
            for lag in GRID["lag"]:
                shifted = {d: series.get(d - timedelta(days=lag), 0.0) for d in days}
                for minor, major in threshold_pairs:
                    def verdict(day):
                        value = shifted[day]
                        return "majorSigns" if value >= major else "minorSigns" if value >= minor else "noSigns"
                    predictions = {d: verdict(d) for d in eligible}
                    agree = sum(1 for d, s in label_state.items() if predictions[d] == s)
                    hits = sum(1 for d in explicit if predictions[d] in ALERT_STATES)
                    exact = sum(1 for d in explicit if predictions[d] == label_state[d])
                    no_alerts = sum(1 for d in inferred_no if predictions[d] in ALERT_STATES)
                    total = sum(1 for s in predictions.values() if s in ALERT_STATES)
                    no_alert_days = [d for d in inferred_no if predictions[d] in ALERT_STATES]
                    candidates.append({
                        "floors": key[0], "dead_zone": key[1], "rr_abs": key[2], "temp_weight": key[3],
                        "aggregator": agg if k > 1 else "single", "k": k, "lag": lag,
                        "minor": minor, "major": major, "agree": agree, "explicit_hits": hits,
                        "explicit_exact": exact, "no_alerts": no_alerts, "total_alerts": total,
                        "no_alert_days": " ".join(d.isoformat() for d in no_alert_days),
                    })

    print(f"Labeled eligible dates: {len(labeled)} ({len(explicit)} explicit, {len(inferred_no)} inferred No signs)")
    print(f"Candidates: {len(candidates)} = {len(evidence_sets)} evidence variants x {len(temporal)} "
          f"temporal operators x {len(GRID['lag'])} lags x {len(threshold_pairs)} threshold pairs")
    print("Ranges: " + "; ".join(f"{k} {list(v)}" for k, v in GRID.items()))
    print("Definitions: evidence per night as Beta 2 with the listed floors, dead zone, RR abs and temp weight; "
          "sum = calendar-day window [D-k+1, D], unscored days add 0; EWMA lam = 1 - 1/k decays per calendar day; "
          "k = 1 is one operator; verdict on D uses the aggregate at D - lag; Major = aggregate >= Major "
          "(no flag count), Minor = aggregate >= Minor; scored only on Beta 2 eligible nights.")
    print("Objective: exact agreement (No/Minor/Major) on labeled eligible dates; ties: fewer alerts on "
          "inferred No-signs dates, then more explicit hits, then fewer total alerts.")

    def rank(c):
        return (-c["agree"], c["no_alerts"], -c["explicit_hits"], c["total_alerts"])

    headers = ["Rank", "Floors", "DZ", "RR abs", "Temp w", "Agg", "k", "Lag", "Minor", "Major",
               "Agree", "Explicit hits", "Explicit exact", "Alerts on No", "Total alerts"]

    def row(i, c):
        return [i, c["floors"], c["dead_zone"], "yes" if c["rr_abs"] else "no", c["temp_weight"],
                c["aggregator"], c["k"], c["lag"], c["minor"], c["major"],
                f"{c['agree']}/{len(labeled)}", f"{c['explicit_hits']}/{len(explicit)}",
                f"{c['explicit_exact']}/{len(explicit)}", f"{c['no_alerts']}/{len(inferred_no)}",
                c["total_alerts"]]

    ordered = sorted(candidates, key=rank)
    print(f"\nReference: always No signs agrees on {len(inferred_no)}/{len(labeled)}; "
          f"best candidate agreement {ordered[0]['agree']}/{len(labeled)}")
    print(f"\nTop {args.top} by objective:")
    print_table(headers, [row(i + 1, c) for i, c in enumerate(ordered[:args.top])])

    all_hit = [c for c in candidates if c["explicit_hits"] == len(explicit)]
    print(f"\nCandidates that alert on all {len(explicit)} explicit dates: {len(all_hit)}")
    if all_hit:
        best = sorted(all_hit, key=lambda c: (c["no_alerts"], -c["agree"], c["total_alerts"]))
        print(f"Fewest alerts on inferred No-signs dates among them: {best[0]['no_alerts']} "
              f"(first listed: {best[0]['no_alert_days']})")
        print_table(headers, [row(i + 1, c) for i, c in enumerate(best[:args.top])])
    exact_all = [c for c in candidates if c["explicit_exact"] == len(explicit)]
    print(f"Candidates matching all explicit levels exactly: {len(exact_all)}"
          + (f"; fewest alerts on inferred No-signs dates: {min(c['no_alerts'] for c in exact_all)}" if exact_all else ""))
    for hits in range(len(explicit), -1, -1):
        subset = [c for c in candidates if c["explicit_hits"] == hits]
        if subset:
            print(f"  explicit hits {hits}: {len(subset)} candidates, "
                  f"fewest alerts on No {min(c['no_alerts'] for c in subset)}")

    if args.out:
        with open(args.out, "w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(candidates[0]))
            writer.writeheader()
            writer.writerows(ordered)
        print(f"\nAll candidates written to {args.out}")


# ---------------------------------------------------------------------------
# Subcommand: oura-extras
# ---------------------------------------------------------------------------


def show(mapping, key):
    """A contributor value; JSON null prints as "null", an absent key as "-"."""
    if key not in mapping:
        return "-"
    return "null" if mapping[key] is None else mapping[key]


def cmd_oura_extras(args):
    app = oura_app_dir(args.oura)
    readiness = {parse_day(r["day"]): r for r in read_semicolon_csv(os.path.join(app, "dailyreadiness.csv"))}
    stress = {parse_day(r["day"]): r for r in read_semicolon_csv(os.path.join(app, "dailystress.csv"))}
    spo2 = {parse_day(r["day"]): r for r in read_semicolon_csv(os.path.join(app, "dailyspo2.csv"))}
    labels = load_labels(args.labels) if args.labels else {}
    oura = load_oura(args.oura)
    beta2 = score_timeline(oura, RULES["beta2"])
    ranges = args.range or ["2026-08-14:2026-08-25", "2026-08-29:2026-09-08"]
    for window in ranges:
        start, end = (parse_day(p) for p in window.split(":"))
        print(f"\n## {start} to {end}")
        rows = []
        day = start
        while day <= end:
            r = readiness.get(day)
            contributors = json.loads(r["contributors"]) if r and r["contributors"].strip() else {}
            s = stress.get(day, {})
            o = spo2.get(day, {})
            label = labels.get(day)
            result = beta2.get(day)
            rows.append([
                day.isoformat(),
                r["score"] if r else "-",
                show(contributors, "hrv_balance"),
                show(contributors, "resting_heart_rate"),
                show(contributors, "body_temperature"),
                (r["temperature_deviation"] or "-") if r else "-",
                (r["temperature_trend_deviation"] or "-") if r else "-",
                s.get("day_summary") or "-",
                s.get("stress_high", "-"),
                s.get("recovery_high", "-"),
                o.get("breathing_disturbance_index") or "-",
                fmt(result["evidence"], 2) if result else "-",
                f"{label['label']} ({label['provenance'][0]})" if label else "",
            ])
            day += timedelta(days=1)
        print_table(["Day", "Readiness", "HRV balance", "RHR contrib", "Body temp contrib", "Temp dev",
                     "Temp trend dev", "Stress summary", "Stress high s", "Recovery high s", "BDI",
                     "Beta 2 evidence", "Oura label"], rows)


# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("inventory", help="files, hashes, exclusions, spread and floor binding, time zones")
    p.add_argument("--oura")
    p.add_argument("--apple")
    p.add_argument("--spread-days", action="store_true", help="print the per-day spread table")
    p.set_defaults(func=cmd_inventory)

    p = sub.add_parser("replay", help="per-night table under one rules variant")
    p.add_argument("--rules", choices=sorted(RULES), default="beta2")
    p.add_argument("--oura")
    p.add_argument("--apple")
    p.add_argument("--body", nargs="+", help="BodyRadarReplay-*.json files")
    p.add_argument("--labels", help="label CSV to annotate Oura rows")
    p.add_argument("--from", dest="start")
    p.add_argument("--to", dest="end")
    p.add_argument("--csv", action="store_true")
    p.set_defaults(func=cmd_replay)

    p = sub.add_parser("compare", help="agreement, alerts, episodes and sensor removal per rules variant")
    p.add_argument("--labels", default=DEFAULT_LABELS)
    p.add_argument("--oura")
    p.add_argument("--apple")
    p.add_argument("--body", nargs="+")
    p.add_argument("--rules", nargs="+", choices=sorted(RULES))
    p.add_argument("--body-chart", help="Body chart inferred CSV (compared with the Apple proxy)")
    p.set_defaults(func=cmd_compare)

    p = sub.add_parser("grid", help="candidate search on the Oura proxy")
    p.add_argument("--oura", required=True)
    p.add_argument("--labels", default=DEFAULT_LABELS)
    p.add_argument("--top", type=int, default=25)
    p.add_argument("--out", help="write every candidate to this CSV")
    p.set_defaults(func=cmd_grid)

    p = sub.add_parser("oura-extras", help="HRV balance, temperature trend, stress and BDI tables")
    p.add_argument("--oura", required=True)
    p.add_argument("--labels")
    p.add_argument("--range", nargs="+", help="yyyy-mm-dd:yyyy-mm-dd windows")
    p.set_defaults(func=cmd_oura_extras)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
