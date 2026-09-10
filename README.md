# Power draw (`local.watts`)

Omarchy bar widget that shows live battery power draw in watts.

Samples `/sys/class/power_supply/BAT0` every 5 seconds and shows charge state,
watts, optional capacity and time remaining on the bar, plus a live hover
tooltip with the full detail.

## Features

- Live power draw label (`↑ 12.3 W` charging, `↓ 8.1 W` discharging)
- Click opens a metrics menu: enable/disable each field and drag to reorder
- Available bar metrics: Charge arrow, Watts, Battery %, Time remaining
- Hover tooltip with status, capacity %, watts, and time remaining / until full
- Tooltip stays open while hovering and updates live with each sample
- Toggle with `omarchy bar set local.watts enabled false` (or `true`)

## Metrics menu

Left-click the widget to open **Bar metrics**. Each row has:

- **⠿ handle** - drag to change order
- **On / Off** - include or hide that metric on the bar (at least one must stay on)

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
  "metrics": "arrow:on,watts:on,capacity:on,time:off"
}
```

Metric ids: `arrow`, `watts`, `capacity`, `time`. Each is followed by `:on` or `:off`.
Order in the string is the bar order. The charge arrow joins its neighbor with a
space (`↓ 8.1 W`); other metrics use ` · `.

Older configs without `arrow`, nested-array `metrics`, and the previous `display`
setting (`watts` / `time` / `full`) still migrate automatically.

Time is estimated from `energy_now` / `power_now` while discharging, or
remaining capacity to full while charging. It is omitted from the bar when
power draw is 0 or the battery is neither charging nor discharging.

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
| `BarWidget.qml` | Sysfs probe, metrics menu, live tooltip, settings |
| `Model.js` | Metric catalog, normalize/migrate, label formatting |
| `README.md` | This file |
