# Power draw (`local.watts`)

Omarchy bar widget that shows live battery power draw in watts.

Samples `/sys/class/power_supply/BAT0` every 5 seconds and shows charge state,
watts, optional capacity and time remaining on the bar, plus a live hover
tooltip with the full detail.

## Features

- Live power draw label (`↑ 12.3 W` charging, `↓ 8.1 W` discharging)
- Click to cycle bar display modes (persisted in `shell.json`):
  1. Watts - `↓ 8.1 W`
  2. Watts + time - `↓ 8.1 W · 1h 12m`
  3. Watts + charge + time - `↓ 8.1 W · 60% · 1h 12m`
- Hover tooltip with status, capacity %, watts, and time remaining / until full
- Tooltip stays open while hovering and updates live with each sample
- Left click also refreshes immediately
- Toggle with `omarchy bar set local.watts enabled false` (or `true`)

## Display mode

| Mode | Bar label | Setting value |
|------|-----------|---------------|
| Watts | `↓ 8.1 W` | `watts` (default) |
| Watts + time | `↓ 8.1 W · 1h 12m` | `time` |
| Watts + % + time | `↓ 8.1 W · 60% · 1h 12m` | `full` |

Set from the CLI:

```bash
omarchy bar set local.watts display time
omarchy bar set local.watts display full
omarchy bar set local.watts display watts
```

Time is estimated from `energy_now` / `power_now` while discharging, or
remaining capacity to full while charging. It is omitted when power draw is 0
or the battery is neither charging nor discharging.

## Requirements

- Laptop battery exposed as `BAT0` under `/sys/class/power_supply/`
- Sysfs files: `status`, `capacity`, `power_now`, `energy_now`, `energy_full`
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
| `BarWidget.qml` | Sysfs probe, display modes, live tooltip, settings |
| `README.md` | This file |
