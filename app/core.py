"""What Reserve concludes, with no I/O in it, so it can be tested on its own.

A sample is the battery once a minute; a bucket is ten minutes of what each app did with the CPU and the GPU. From
those this works out the day's level, when the laptop charged or slept, how much battery went where, how long what is
left will last, and the few things worth telling you about. Everything here is an estimate built from measured
inputs, and the words it produces say so.
"""
from __future__ import annotations

import math

# A sample on disk: [t, pct*10, mW (positive while draining), status, ac, brightness %, lid open, dGPU awake,
# charge µAh, voltage mV]. Compact on purpose: a month of minutes stays under 2 MB.
STATUS = {"Discharging": "D", "Charging": "C", "Full": "F", "Not charging": "N", "Unknown": "U"}
SLEEP_GAP = 150          # seconds between samples that count as the laptop asleep
BUCKET = 600             # seconds of app activity per bucket
GPU_WEIGHT = 1.0         # a millisecond of GPU time weighs as much as one of CPU time
LEVEL_POINTS = 288       # points in a level chart
NAME_MAX = 40


def pack_sample(s: dict) -> list:
    return [int(s["t"]), int(round(s["pct"] * 10)), int(s["mw"]), STATUS.get(s["status"], "U"), 1 if s["ac"] else 0,
            int(s["br"]), 1 if s["lid"] else 0, 1 if s["gpu"] else 0, int(s["uah"]), int(s["mv"])]


def unpack_sample(row) -> dict | None:
    """A sample read back, or None when the row is not one (a torn line, a hand edit)."""
    if not isinstance(row, list) or len(row) != 10:
        return None
    try:
        t, p10, mw, st, ac, br, lid, gpu, uah, mv = row
        if not all(isinstance(v, int) and not isinstance(v, bool) for v in (t, p10, mw, ac, br, lid, gpu, uah, mv)):
            return None
        if st not in STATUS.values() or not 0 <= p10 <= 1000 or abs(mw) > 500_000:
            return None
        return {"t": t, "pct": p10 / 10, "mw": mw, "st": st, "ac": ac == 1, "br": br, "lid": lid == 1,
                "gpu": gpu == 1, "uah": uah, "mv": mv}
    except (TypeError, ValueError):
        return None


# The kernel names a process by its executable, cut to 15 characters. These read better as the apps people know.
DISPLAY = {"quickshell": "Omarchy shell", "Hyprland": "Hyprland", "Xwayland": "Xwayland (older apps)",
           "brave": "Brave", "zed": "Zed", "zed-editor": "Zed", "firefox": "Firefox", "chromium": "Chromium",
           "cs2": "Counter-Strike 2", "steamwebhelper": "Steam", "steam": "Steam", "omagram": "Omagram",
           "pipewire": "Sound (PipeWire)", "wireplumber": "Sound (PipeWire)", "foot": "Terminal", "warp": "Warp",
           "claude": "Claude Code", "node": "Node.js", "python3": "Python", "code": "VS Code", "obs": "OBS Studio",
           "mpv": "mpv", "spotify": "Spotify", "telegram-deskto": "Telegram", "Discord": "Discord", "geary": "Geary"}


def display_name(name: str) -> str:
    """How an app is shown: its known name, or its process name with a capital first letter."""
    if name in DISPLAY:
        return DISPLAY[name]
    return name[:1].upper() + name[1:] if name else name


def clean_name(name: str) -> str:
    """An app's name as the kernel gives it (comm), made safe to show."""
    keep = "".join(ch for ch in str(name) if ch.isprintable() and ch not in "<>&\"'")
    return keep.strip()[:NAME_MAX] or "unknown"


def unpack_bucket(obj) -> dict | None:
    if not isinstance(obj, dict):
        return None
    t, length = obj.get("t"), obj.get("dt")
    if not isinstance(t, int) or not isinstance(length, int) or not 0 < length <= 3 * BUCKET:
        return None
    out = {"t": t, "dt": length, "bat": {}, "ac": {}}
    for side in ("bat", "ac"):
        apps = obj.get(side)
        if not isinstance(apps, dict):
            continue
        for name, pair in list(apps.items())[:200]:
            if (isinstance(pair, list) and len(pair) == 2
                    and all(isinstance(v, int) and not isinstance(v, bool) and 0 <= v <= length * 1000 * 512 for v in pair)):
                out[side][clean_name(name)] = pair
    return out


# ---------------------------------------------------------------- the shape of a day

def spans(samples: list[dict]) -> dict:
    """Charging and sleeping, as lists of [start, end] in seconds."""
    charging, sleeping = [], []
    for prev, cur in zip(samples, samples[1:]):
        if cur["t"] - prev["t"] > SLEEP_GAP:
            sleeping.append([prev["t"], cur["t"]])
        elif prev["st"] == "C":
            if charging and charging[-1][1] == prev["t"]:
                charging[-1][1] = cur["t"]
            else:
                charging.append([prev["t"], cur["t"]])
    return {"charging": charging, "sleeping": sleeping}


def level_series(samples: list[dict], start: int, end: int, points: int = LEVEL_POINTS) -> list[list]:
    """The level from `start` to `end`, at most `points` points, as [t, pct]; a gap stays a gap (None)."""
    inside = [s for s in samples if start <= s["t"] <= end]
    if not inside:
        return []
    step = max(60, (end - start) // points)
    out, last_t = [], None
    for s in inside:
        if last_t is not None and s["t"] - last_t > SLEEP_GAP:
            out.append([last_t + 1, None])
        if not out or out[-1][1] is None or s["t"] - out[-1][0] >= step:
            out.append([s["t"], s["pct"]])
        last_t = s["t"]
    if out[-1][0] != inside[-1]["t"]:
        out.append([inside[-1]["t"], inside[-1]["pct"]])
    return out


def last_unplug(samples: list[dict]) -> dict | None:
    """When the charger last came out, and the level then: the start of the current run on battery."""
    for prev, cur in zip(reversed(samples[:-1]), reversed(samples[1:])):
        if prev["ac"] and not cur["ac"]:
            return {"t": cur["t"], "pct": cur["pct"]}
    return None


# ---------------------------------------------------------------- energy

def drain_mwh(samples: list[dict], start: int, end: int) -> float:
    """Energy drawn from the battery between two times (mWh): power integrated over each minute on battery.
    Minutes asleep are left out; what sleep cost is measured separately, from the charge before and after."""
    total = 0.0
    for prev, cur in zip(samples, samples[1:]):
        if cur["t"] <= start or prev["t"] >= end:
            continue
        gap = cur["t"] - prev["t"]
        if gap > SLEEP_GAP or prev["ac"] or prev["mw"] <= 0:
            continue
        a, b = max(prev["t"], start), min(cur["t"], end)
        total += prev["mw"] * (b - a) / 3600
    return total


def sleep_cost(samples: list[dict]) -> list[dict]:
    """Each sleep and what it cost: hours asleep and percent lost, with the rate."""
    out = []
    for prev, cur in zip(samples, samples[1:]):
        gap = cur["t"] - prev["t"]
        if gap <= SLEEP_GAP or prev["ac"] or cur["ac"]:
            continue
        lost = max(0.0, prev["pct"] - cur["pct"])
        hours = gap / 3600
        out.append({"start": prev["t"], "end": cur["t"], "hours": round(hours, 2), "lost": round(lost, 1),
                    "perHour": round(lost / hours, 2) if hours > 0 else 0})
    return out


def baseline_mw(samples: list[dict]) -> float:
    """The laptop's floor on battery: the 10th percentile of power with the lid open. What the screen and the idle
    system cost whatever the apps do."""
    values = sorted(s["mw"] for s in samples if not s["ac"] and s["lid"] and s["mw"] > 0)
    if not values:
        return 0.0
    return float(values[int(len(values) * 0.1)])


def usage_by_app(samples: list[dict], buckets: list[dict], start: int, end: int) -> dict:
    """How much battery went where since `start`.

    Each ten-minute bucket's energy on battery is split in two: the floor (screen and idle system) for the time it
    covers, and the rest, shared among apps by their CPU and GPU time in that bucket. Shares are of the energy used,
    and they are estimates: the kernel reports time, not watts, per app.
    """
    floor = baseline_mw(samples)
    total = drain_mwh(samples, start, end)
    apps: dict[str, dict] = {}
    base = 0.0
    for b in buckets:
        if b["t"] + b["dt"] <= start or b["t"] >= end:
            continue
        energy = drain_mwh(samples, b["t"], b["t"] + b["dt"])
        if energy <= 0:
            continue
        on_battery = _seconds_on_battery(samples, b["t"], b["t"] + b["dt"])
        floor_part = min(energy, floor * on_battery / 3600)
        base += floor_part
        weights = {n: c + GPU_WEIGHT * g for n, (c, g) in b["bat"].items() if c + g > 0}
        weight_sum = sum(weights.values())
        if weight_sum <= 0:
            base += energy - floor_part
            continue
        for name, wgt in weights.items():
            # Grouped under the name people know, so Steam's helper and Steam are one line.
            shown = display_name(name)
            a = apps.setdefault(shown, {"name": shown, "mwh": 0.0, "cpuMs": 0, "gpuMs": 0})
            a["mwh"] += (energy - floor_part) * wgt / weight_sum
            a["cpuMs"] += b["bat"][name][0]
            a["gpuMs"] += b["bat"][name][1]
    listed = sorted(apps.values(), key=lambda a: -a["mwh"])
    for a in listed:
        a["share"] = round(100 * a["mwh"] / total, 1) if total > 0 else 0
        a["mwh"] = round(a["mwh"], 1)
    return {"totalMwh": round(total, 1), "baseMwh": round(base, 1),
            "baseShare": round(100 * base / total, 1) if total > 0 else 0, "apps": listed[:30]}


def _seconds_on_battery(samples: list[dict], start: int, end: int) -> int:
    seconds = 0
    for prev, cur in zip(samples, samples[1:]):
        if cur["t"] <= start or prev["t"] >= end or cur["t"] - prev["t"] > SLEEP_GAP or prev["ac"]:
            continue
        seconds += min(cur["t"], end) - max(prev["t"], start)
    return seconds


def time_left(samples: list[dict], window: int = 1200) -> dict | None:
    """Hours left at the recent rate: the average power over the last twenty minutes on battery, so one busy
    moment does not swing it."""
    if not samples or samples[-1]["ac"]:
        return None
    now = samples[-1]
    energy = drain_mwh(samples, now["t"] - window, now["t"])
    seconds = _seconds_on_battery(samples, now["t"] - window, now["t"])
    if seconds < 300 or energy <= 0:
        return None
    rate = energy / (seconds / 3600)
    left_mwh = now["uah"] / 1000 * now["mv"] / 1000
    return {"hours": round(left_mwh / rate, 2), "rateMw": round(rate), "leftMwh": round(left_mwh)}


def gpu_on_battery(samples: list[dict], start: int, end: int) -> int:
    """Seconds the dedicated GPU was awake while on battery."""
    seconds = 0
    for prev, cur in zip(samples, samples[1:]):
        if cur["t"] <= start or prev["t"] >= end or cur["t"] - prev["t"] > SLEEP_GAP or prev["ac"] or not prev["gpu"]:
            continue
        seconds += min(cur["t"], end) - max(prev["t"], start)
    return seconds


# ---------------------------------------------------------------- health

def health(info: dict) -> dict:
    """Capacity against design, cycles, temperature and the kernel's word for it, from the live battery."""
    full, design = info.get("full") or 0, info.get("design") or 0
    return {"capacity": round(100 * full / design, 1) if design > 0 else None, "cycles": info.get("cycles"),
            "temperature": info.get("temperature"), "health": info.get("health") or "", "model": info.get("model") or "",
            "year": info.get("year")}


def capacity_trend(days: list[dict]) -> list[list]:
    """[date, capacity %] from the daily health log, one point a day (the day's last reading), oldest first."""
    by_day: dict[str, float] = {}
    for d in days:
        if isinstance(d, dict) and isinstance(d.get("d"), str) and isinstance(d.get("cap"), (int, float)):
            by_day[d["d"][:10]] = round(float(d["cap"]), 1)
    return [[day, by_day[day]] for day in sorted(by_day)][-400:]


# ---------------------------------------------------------------- what to tell you

def insights(samples: list[dict], usage: dict, start: int, end: int) -> list[dict]:
    """The few things worth saying, each with what to do. Ordered by how much battery is at stake."""
    out = []
    awake = gpu_on_battery(samples, start, end)
    if awake >= 600:
        out.append({"kind": "dgpu", "seconds": awake,
                    "text": f"The NVIDIA GPU was awake {spell(awake)} on battery. Something kept it up; GPU who will name it."})
    for s in sleep_cost(samples):
        if s["start"] >= start and s["hours"] >= 2 and s["perHour"] >= 1.5:
            out.append({"kind": "sleep", "seconds": int(s["hours"] * 3600),
                        "text": f"Asleep for {spell(int(s['hours'] * 3600))}, it lost {s['lost']:.0f}% ({s['perHour']:.1f}% an hour). "
                                "Healthy sleep here loses well under 1% an hour."})
    if usage["apps"] and usage["apps"][0]["share"] >= 35:
        top = usage["apps"][0]
        out.append({"kind": "app", "seconds": 0,
                    "text": f"{top['name']} used about {top['share']:.0f}% of the battery since {clock(start)}."})
    return out


def spell(seconds: int) -> str:
    minutes = int(round(seconds / 60))
    if minutes < 60:
        return f"{minutes} min"
    return f"{minutes // 60} h {minutes % 60:02d} min" if minutes % 60 else f"{minutes // 60} h"


def clock(t: int) -> str:
    import time
    return time.strftime("%H:%M", time.localtime(t))


def charger(info: dict) -> dict | None:
    """The USB-C power contract when on PD: watts offered, from the port's voltage and current limits."""
    if not info:
        return None
    volts, amps = info.get("volts"), info.get("amps")
    if not volts or not amps:
        return None
    watts = volts * amps
    note = ""
    if watts < 90:
        note = "Under 90 W: the GPU is held back in games on this charger."
    return {"watts": round(watts), "note": note}


def report(samples: list[dict], buckets: list[dict], now: int, since: str, info: dict, health_days: list[dict],
           pd: dict | None) -> dict:
    """Everything the panel shows, in one bounded answer."""
    samples = sorted(samples, key=lambda s: s["t"])
    day_start = _local_midnight(now)
    if since == "unplug":
        u = last_unplug(samples)
        start = u["t"] if u else day_start
        label = (f"Since unplugged at {clock(u['t'])} ({u['pct']:.0f}%)" if u else "Today")
    else:
        start, label = day_start, "Today"
    chart_start = now - 24 * 3600
    usage = usage_by_app(samples, buckets, start, now)
    current = samples[-1] if samples else None
    return {
        "now": now,
        "since": start,
        "sinceLabel": label,
        "current": current,
        "level": level_series(samples, chart_start, now),
        "chartStart": chart_start,
        "spans": {k: [x for x in v if x[1] >= chart_start] for k, v in spans(samples).items()},
        "usage": usage,
        "timeLeft": time_left(samples),
        "health": health(info),
        "trend": capacity_trend(health_days),
        "charger": charger(pd),
        "insights": insights(samples, usage, start, now),
    }


def _local_midnight(t: int) -> int:
    import time
    lt = time.localtime(t)
    return int(time.mktime((lt.tm_year, lt.tm_mon, lt.tm_mday, 0, 0, 0, 0, 0, -1)))
