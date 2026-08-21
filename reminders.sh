#!/bin/bash
set -euo pipefail

case "${1:-}" in
delete)
  unit="${2:-}"
  label="${3:-Reminder}"
  [[ $unit == omarchy-reminder-* && $unit =~ ^[A-Za-z0-9_.@:-]+$ ]] || exit 2

  systemctl --user stop "$unit.timer" "$unit.service" >/dev/null 2>&1 || true
  rm -f "${XDG_RUNTIME_DIR:-/tmp}/omarchy-reminders/$unit.message"
  omarchy-shell -q omarchy.indicators refresh >/dev/null 2>&1 || true
  omarchy-notification-send -g 󰢌 "Reminder cancelled" "$label"
  ;;
*)
  echo "Usage: reminders.sh delete <unit> [label]" >&2
  exit 2
  ;;
esac
