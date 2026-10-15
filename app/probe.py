"""Reading the laptop: the battery, the charger, the screen, the lid, the NVIDIA GPU, and what each app did.

Only sysfs and /proc, read directly and in small bounded pieces; nothing here runs a program. The NVIDIA GPU is
asked whether it is awake through its runtime power status, which does not wake it, and never through nvidia-smi,
which does.
"""
from __future__ import annotations

import os

POWER = "/sys/class/power_supply"
CLK_TCK = os.sysconf("SC_CLK_TCK") if hasattr(os, "sysconf") else 100


def small(path: str, limit: int = 256) -> str:
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
    except OSError:
        return ""
    try:
        return os.read(fd, limit).decode("utf-8", "replace").strip()
    except OSError:
        return ""
    finally:
        os.close(fd)


def number(path: str) -> int | None:
    try:
        return int(small(path, 64))
    except ValueError:
        return None


def battery_dir() -> str | None:
    """The laptop's own battery: type Battery, and not a device's (a mouse's battery has scope Device)."""
    try:
        names = sorted(os.listdir(POWER))
    except OSError:
        return None
    for name in names:
        d = os.path.join(POWER, name)
        if small(os.path.join(d, "type")) == "Battery" and small(os.path.join(d, "scope")) != "Device":
            return d
    return None


def battery() -> dict | None:
    d = battery_dir()
    if not d:
        return None
    f = lambda n: os.path.join(d, n)  # noqa: E731
    status = small(f("status")) or "Unknown"
    volts_uv = number(f("voltage_now")) or 0
    if os.path.exists(f("power_now")):
        mw = (number(f("power_now")) or 0) / 1000
    else:
        mw = (number(f("current_now")) or 0) * volts_uv / 1e9
    if os.path.exists(f("charge_now")):
        uah = number(f("charge_now")) or 0
        full, design = number(f("charge_full")), number(f("charge_full_design"))
    else:
        # Energy-reporting batteries: µWh, turned into µAh at the present voltage.
        v = volts_uv / 1e6 or 1
        uah = int((number(f("energy_now")) or 0) / v)
        full = int((number(f("energy_full")) or 0) / v)
        design = int((number(f("energy_full_design")) or 0) / v)
    pct = number(f("capacity"))
    temp = number(f("temp"))
    return {
        "pct": float(pct if pct is not None else 0),
        "status": status,
        "mw": int(round(mw)) * (-1 if status == "Charging" else 1),
        "uah": int(uah),
        "mv": int(volts_uv / 1000),
        "full": full, "design": design,
        "cycles": number(f("cycle_count")),
        "temperature": round(temp / 10, 1) if temp is not None else None,
        "health": small(f("health"), 64),
        "model": " ".join(x for x in (small(f("manufacturer"), 64), small(f("model_name"), 64)) if x),
        "year": number(f("manufacture_year")),
    }


def on_ac() -> bool:
    try:
        names = os.listdir(POWER)
    except OSError:
        return False
    for name in names:
        d = os.path.join(POWER, name)
        if small(os.path.join(d, "type")) == "Mains" and small(os.path.join(d, "online")) == "1":
            return True
    return False


def usb_pd() -> dict | None:
    """The USB-C source the laptop is drawing from, when there is one: its voltage and current limits."""
    try:
        names = os.listdir(POWER)
    except OSError:
        return None
    for name in sorted(names):
        d = os.path.join(POWER, name)
        if not name.startswith("ucsi-source") or small(os.path.join(d, "online")) != "1":
            continue
        uv, ua = number(os.path.join(d, "voltage_max")), number(os.path.join(d, "current_max"))
        if uv and ua:
            return {"volts": uv / 1e6, "amps": ua / 1e6}
    return None


def brightness() -> int:
    base = "/sys/class/backlight"
    try:
        names = sorted(os.listdir(base))
    except OSError:
        return 100
    for name in names:
        cur, top = number(os.path.join(base, name, "brightness")), number(os.path.join(base, name, "max_brightness"))
        if cur is not None and top:
            return int(round(100 * cur / top))
    return 100


def lid_open() -> bool:
    base = "/proc/acpi/button/lid"
    try:
        names = os.listdir(base)
    except OSError:
        return True
    for name in names:
        if "closed" in small(os.path.join(base, name, "state")):
            return False
    return True


def nvidia_awake() -> bool:
    """Whether an NVIDIA display controller is powered up, from its runtime PM status (reading it wakes nothing)."""
    base = "/sys/bus/pci/devices"
    try:
        names = os.listdir(base)
    except OSError:
        return False
    for name in names:
        d = os.path.join(base, name)
        if small(os.path.join(d, "vendor")) == "0x10de" and small(os.path.join(d, "class")).startswith("0x03"):
            if small(os.path.join(d, "power", "runtime_status")) == "active":
                return True
    return False


def processes() -> dict:
    """Every process of this user: {(pid, start): (name, cpu ticks)}."""
    out = {}
    uid = os.getuid()
    try:
        entries = os.listdir("/proc")
    except OSError:
        return out
    for pid in entries:
        if not pid.isdigit():
            continue
        try:
            if os.stat("/proc/" + pid).st_uid != uid:
                continue
        except OSError:
            continue
        raw = small(f"/proc/{pid}/stat", 1024)
        close = raw.rfind(")")
        if close < 0:
            continue
        name = raw[raw.find("(") + 1:close]
        fields = raw[close + 2:].split()
        try:
            ticks = int(fields[11]) + int(fields[12])
            start = int(fields[19])
        except (IndexError, ValueError):
            continue
        out[(int(pid), start)] = (name, ticks)
    return out


def gpu_clients(pids) -> dict:
    """GPU time per DRM client of these processes: {client: (pid, ns)}. Only file descriptors that point at a GPU
    device are read, which keeps a look to about a dozen milliseconds."""
    out = {}
    for pid in pids:
        fd_dir = f"/proc/{pid}/fd"
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        for fd in fds:
            try:
                if not os.readlink(f"{fd_dir}/{fd}").startswith("/dev/dri/"):
                    continue
            except OSError:
                continue
            cid, pdev, ns = None, "", 0
            for line in small(f"/proc/{pid}/fdinfo/{fd}", 4096).splitlines():
                if line.startswith("drm-client-id:"):
                    cid = line.split(":", 1)[1].strip()
                elif line.startswith("drm-pdev:"):
                    pdev = line.split(":", 1)[1].strip()
                elif line.startswith("drm-engine-") and line.endswith(" ns"):
                    try:
                        ns += int(line.split(":", 1)[1].split()[0])
                    except (ValueError, IndexError):
                        pass
            if cid:
                out[pdev + "/" + cid] = (pid, ns)
    return out
