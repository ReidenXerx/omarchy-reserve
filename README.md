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
  hour), one app that took most of the charge, said in plain words.
- **Measuring costs next to nothing.** It never wakes the dedicated GPU to ask
  how it is: its runtime power status is read from sysfs, never through
  `nvidia-smi`. One sample a minute takes about 40 ms of CPU with a few hundred
  processes running (it grows with how many you run).
- **It sees a charger that is not enough.** On battery means the battery is
  discharging, so a game that outruns a small USB-C charger is counted as the
  drain it is, not hidden behind "plugged in".
- **Health over months, not just today.** Capacity against the battery's
  design, cycles and temperature, with a daily capacity log so slow wear shows
  long before it bites.
- **Charging, explained.** The real wattage of a USB-C charger, and whether a
  charge limit is holding the battery where it is. A charger under 90 W, which
  holds a gaming GPU back, says so.

## Using it

Put the widget on your bar: it is a battery icon at your level, with a bolt
while it charges, so it can stand in for the stock one. Its tooltip has the
level and the time left; a click opens the panel.

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

History stays on your laptop, in `~/.local/state/reserve`, a directory of its
own that only you can read: 30 days of samples and app activity (about 5 MB),
and a daily capacity reading kept for the health trend. Nothing is sent
anywhere and nothing needs root.

## Install

```bash
omarchy plugin add https://github.com/ReidenXerx/omarchy-reserve.git --enable
```

Then add the Reserve widget to your bar and restart the shell with
`omarchy-restart-shell`.

## Remove

```bash
omarchy plugin remove reidenxerx.reserve
```

The sampler stops with it. Your history stays in `~/.local/state/reserve` until
you delete it.

## On KDE Plasma

Reserve also comes as a Plasma 6 widget, for the panel or the system tray,
with the same panel drawn in Plasma's own controls and colours. Install it from
the KDE Store (Add Widgets → Get New Widgets → search "Reserve"), or build it
here:

```bash
tools/build-plasma          # dist/reserve.plasmoid
kpackagetool6 -t Plasma/Applet -i dist/app.duduphudu.reserve
```

The level and charging state come from Plasma's power management. The widget
runs the same sampler for as long as Plasma runs, one per user however many
Reserve widgets you add, and it stops when you remove the widget. It sits
beside Plasma's Power and Battery widget rather than replacing it: charge
limits and power profiles stay there.

## Requirements

Omarchy's Quickshell-based shell, Python 3, and a laptop battery. On Plasma:
Plasma 6 and Python 3.

## Tests

```bash
python3 -I tests/core_test.py
```

## Licence

MIT

## Support

Reserve is free and always will be. If it earns a place on your bar, you can
support its development at [donatello.to/DuduPhudu](https://donatello.to/DuduPhudu).
