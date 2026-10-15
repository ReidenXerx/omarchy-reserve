# Reserve

The battery screen your phone has, for your [Omarchy](https://omarchy.org)
laptop: how the day went, which apps used the charge, how long what is left
will last, how healthy the battery is, and a plain-words reason when it drained
faster than it should.

## What only Reserve does

- **Usage by app, on a laptop.** Each app's share of the battery since you
  unplugged, or for today, worked out from the CPU and graphics time it used,
  the way phones do it. The kernel reports time per app, not watts, so the
  shares are estimates, and the panel says so. What the laptop uses doing
  nothing (the screen, the idle system) is its own line instead of being
  smeared across the apps.
- **It names the cause.** An NVIDIA GPU left awake on battery, a night asleep
  that drained more than it should (healthy sleep here loses well under 1% an
  hour), one app that took most of the charge. Each comes with what to do.
- **Measuring never costs you battery.** It never wakes the dedicated GPU to
  ask how it is: its runtime power status is read from sysfs, never through
  `nvidia-smi`. One sample a minute takes about 15 to 25 ms of CPU.
- **Health over months, not just today.** Capacity against the battery's
  design, cycles and temperature, with a daily capacity log so slow wear shows
  long before it bites.
- **Charging, explained.** The real wattage of a USB-C charger, and whether a
  charge limit is holding the battery where it is. A charger under 90 W, which
  holds a gaming GPU back, says so.

## Using it

Put the widget on your bar: a battery with a heart. Its tooltip has the level
and the time left; a click opens the panel.

| In the panel | What it shows |
|---|---|
| **The top line** | The level, and the time left at the recent rate (the last twenty minutes, so one busy moment does not swing it) |
| **The chart** | The last 24 hours, with charging and sleep marked |
| **Battery use** | Since unplugged, or today: each app's share, and the screen and system |
| **Dots** | The things worth knowing about |
| **Health** | Capacity, cycles, temperature, and the charger |

## Where the data comes from, and where it goes

A small sampler (`bin/reserve run`) reads `/sys/class/power_supply`, the
backlight, the lid, the NVIDIA GPU's runtime status, `/proc/<pid>/stat` for
CPU time and `/proc/<pid>/fdinfo` for GPU time, once a minute, and only for
your own processes. It runs no programs. The shell starts it and it stops with
the shell.

History stays on your laptop, in `~/.local/state/reserve`, a private directory:
30 days of minutes (about 2 MB) and a year of hourly summaries. Nothing is sent
anywhere and nothing needs root.

## Install

```bash
omarchy plugin add https://github.com/ReidenXerx/omarchy-reserve.git --enable
```

Then add the Reserve widget to your bar and restart the shell with
`omarchy-restart-shell`.

## Requirements

Omarchy's Quickshell-based shell, Python 3, and a laptop battery.

## Tests

```bash
python3 -I tests/core_test.py
```

## Licence

MIT

## Support

Reserve is free and always will be. If it earns a place on your bar, you can
support its development at [donatello.to/DuduPhudu](https://donatello.to/DuduPhudu).
