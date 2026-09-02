# Power draw (`local.watts`)

Omarchy bar widget that shows live battery power draw in watts.

Samples `/sys/class/power_supply/BAT0` every 5 seconds and renders charge state, watts, and an estimated time remaining tooltip.

## Features

- Live power draw label (`↑ 12.3 W` charging, `↓ 8.1 W` discharging)
- Tooltip with status, capacity %, watts, and time remaining / until full
- Left click refreshes immediately
- Toggle with `omarchy bar set local.watts enabled false` (or `true`)

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

Saved plugin files reload automatically. Force a rescan with `omarchy-shell shell rescanPlugins` if needed.

## Layout

| File | Role |
|------|------|
| `manifest.json` | Plugin id, bar-widget metadata, entry point |
| `BarWidget.qml` | Sysfs probe, label, tooltip, enable setting |
