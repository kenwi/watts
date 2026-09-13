#!/bin/sh
# Apply a BAT0 charge-end threshold and persist it via systemd.
# Usage: set-charge-limit.sh <percent>
#   percent: 1-100 (100 = charge to full)
set -eu

pct="${1:-}"
case "$pct" in
  ''|*[!0-9]*)
    echo "usage: $0 <percent 1-100>" >&2
    exit 2
    ;;
esac
if [ "$pct" -lt 1 ] || [ "$pct" -gt 100 ]; then
  echo "percent must be 1-100" >&2
  exit 2
fi

bat="/sys/class/power_supply/BAT0"
end="$bat/charge_control_end_threshold"
stop="$bat/charge_stop_threshold"

if [ ! -e "$end" ]; then
  echo "charge_control_end_threshold not available" >&2
  exit 1
fi

# Some ThinkPads reject end < start; keep start below end when present.
start="$bat/charge_control_start_threshold"
if [ -e "$start" ]; then
  cur_start="$(cat "$start" 2>/dev/null || echo 0)"
  case "$cur_start" in
    ''|*[!0-9]*) cur_start=0 ;;
  esac
  if [ "$cur_start" -ge "$pct" ]; then
    # Drop start so end can be lowered (0 is always valid when supported).
    printf '%s\n' 0 > "$start" 2>/dev/null || true
  fi
fi

printf '%s\n' "$pct" > "$end"
if [ -e "$stop" ]; then
  printf '%s\n' "$pct" > "$stop" 2>/dev/null || true
fi

unit="/etc/systemd/system/battery-charge-limit.service"
cat > "$unit" <<EOF
[Unit]
Description=Limit battery charge to ${pct} percent (longevity)
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo ${pct} > /sys/class/power_supply/BAT0/charge_control_end_threshold'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable battery-charge-limit.service >/dev/null
systemctl restart battery-charge-limit.service >/dev/null

printf '%s\n' "$pct"
