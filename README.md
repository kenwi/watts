# Power draw (`local.watts`)

Omarchy bar widget that shows live battery power draw in watts.

Reads `/sys/class/power_supply/BAT0` on a configurable interval and shows charge
state, watts, optional capacity and time remaining on the bar, plus a live hover
tooltip with the full detail.

## Features

- Live power draw label (`↑ 12.3 W` charging, `↓ 8.1 W` discharging)
- Click opens a metrics menu: enable/disable each field and drag to reorder
- Available bar metrics: Charge arrow, Watts, Battery %, Time remaining
- Optional: hide metrics when idle/full, with optional idle battery icon
- Configurable update interval (default 5s)
- Configurable left/right bar padding (px) to nudge the label on the bar
- Charge limiter: toggle and set end-threshold % (defaults to the current kernel value)
- Hover tooltip with status, capacity %, watts, and time remaining / until full
- Tooltip stays open while hovering and updates live with each sample
- Toggle with `omarchy bar set local.watts enabled false` (or `true`)

## Sampling and update rate

Two clocks are involved:

1. **Plugin sample interval** (`intervalSec`, default `5`) - how often this widget
   re-reads sysfs. Change it in the metrics menu or with
   `omarchy bar set local.watts intervalSec 10`. Range is 1-300 seconds. Left click
   also triggers an immediate refresh.
2. **Kernel / ACPI battery driver** - how often `/sys/class/power_supply/BAT0`
   values such as `power_now` and `energy_now` actually change. There is no fixed
   poll file for BAT0; updates depend on the hardware and driver. Values may move
   within a second under changing load, or stay flat when draw is steady.

The bar never refreshes faster than `intervalSec`, and it cannot show a change
the kernel has not written to sysfs yet. Time remaining is estimated from the
latest sample (`energy_now` / `power_now` while discharging, or remaining
capacity to full while charging), so it inherits the same limits.

## Metrics menu

Left-click the widget to open **Bar metrics**. Each row has:

- **⠿ handle** - drag to change order
- **On / Off** - include or hide that metric on the bar (at least one must stay on)

Also:

- **Update interval (seconds)** - how often sysfs is sampled (1-300, default 5)
- **Left / right padding (px)** - empty space around the label on the bar (0-400;
  default matches theme spacing, usually ~8)
- **Charge limiter** - cap charging at a percentage (writes
  `charge_control_end_threshold`). Defaults to whatever the kernel already has
  (for example 80% from a boot service). Off sets the limit to 100%. Changing the
  value prompts for elevation via `pkexec` and updates
  `/etc/systemd/system/battery-charge-limit.service` so it survives reboot.
- **Charge limit (%)** - target when the limiter is on (50-100)
- **Only while charging / discharging** - when on, hide metrics while idle or full
- **Idle battery icon** - when the option above is on, show a clickable battery
  icon while idle/full (default on). Turn off to hide the widget completely when
  idle; re-enable later with `omarchy bar set local.watts idleIcon on` or while
  charging/discharging.

Examples:

| Configuration | Bar label |
|---------------|-----------|
| Arrow + watts | `↓ 8.1 W` |
| Watts only | `8.1 W` |
| Arrow, watts, % | `↓ 8.1 W · 60%` |
| %, then watts | `60% · 8.1 W` |
| Full | `↓ 8.1 W · 60% · 1h 12m` |

Settings are persisted in `shell.json` as a plain string (so they survive
plugin reloads after Omarchy updates):

```json
{
  "id": "local.watts",
  "metrics": "arrow:on,watts:on,capacity:on,time:off",
  "activeOnly": "on",
  "idleIcon": "on",
  "intervalSec": 5,
  "padLeft": 8,
  "padRight": 8,
  "chargeLimit": "on",
  "chargeLimitPct": 80
}
```

Metric ids: `arrow`, `watts`, `capacity`, `time`. Each is followed by `:on` or `:off`.
Order in the string is the bar order. The charge arrow joins its neighbor with a
space (`↓ 8.1 W`); other metrics use ` · `. `activeOnly` and `idleIcon` are `on`
or `off`. `intervalSec` is 1-300. `padLeft` / `padRight` are pixels (0-400).
Unset padding keeps the theme default (`Style.space(8)`). Unset `chargeLimit` /
`chargeLimitPct` follow the live sysfs end-threshold (limiter on when it is
below 100%).

Older configs without `arrow`, nested-array `metrics`, and the previous `display`
setting (`watts` / `time` / `full`) still migrate automatically.

Time remaining is omitted from the bar when power draw is 0 or the battery is
neither charging nor discharging.

## Requirements

- Laptop battery exposed as `BAT0` under `/sys/class/power_supply/`
- Sysfs files: `status`, `capacity`, `power_now`, `energy_now`, `energy_full`
- Optional charge limiter: `charge_control_end_threshold` (write needs `pkexec`)
- Horizontal bar only (hidden on vertical bars and when no battery is found)

## Install

Symlink or copy into the user plugin directory, then enable and place on the bar:

```bash
ln -s ~/Work/omarchy-plugins/local.watts ~/.config/omarchy/plugins/local.watts
omarchy plugin enable local.watts
omarchy bar put local.watts --section left
```

From git (if published as a standalone plugin repo):

```bash
omarchy plugin add <git-url> --enable
omarchy bar put local.watts
```

Saved plugin files reload automatically. Force a rescan with
`omarchy-shell shell rescanPlugins` if needed. If the plugin is a symlink,
prefer `omarchy restart shell` after edits so QML definitely reloads.

## Layout

| File | Role |
|------|------|
| `manifest.json` | Plugin id, bar-widget metadata, entry point |
| `BarWidget.qml` | Sysfs probe, metrics menu, live tooltip, settings |
| `Model.js` | Metric catalog, normalize/migrate, label formatting |
| `set-charge-limit.sh` | Root helper to set end-threshold + systemd unit |
| `README.md` | This file |
