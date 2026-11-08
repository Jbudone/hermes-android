#!/data/data/com.termux/files/usr/bin/bash
# perf-guard.sh [--fix] — check phone performance; notify on findings.
#
# Run it from a Tasker profile (e.g. every few hours, or on screen-off) or a
# Termux:Widget shortcut. With --fix it also applies the safe remediations.
set -e
export PATH="/data/data/com.termux/files/usr/bin:$PATH"
HB="$HOME/hermes-android/bin/hermes-android"
[ -x "$HB" ] || { echo "toolkit missing at $HB"; exit 2; }

report="$("$HB" perf 2>&1)"
high="$(printf '%s\n' "$report" | grep -c '\[.*HIGH' || true)"
med="$(printf '%s\n' "$report" | grep -c '\[.* MED' || true)"

if [ "$high" -gt 0 ]; then
  termux-notification --title "⚠ Phone perf: $high high-priority issue(s)" \
    --content "$(printf '%s\n' "$report" | grep 'HIGH' | head -3 | sed 's/\x1b\[[0-9;]*m//g')" \
    --priority high 2>/dev/null || true
elif [ "$med" -gt 0 ]; then
  termux-notification --title "Phone perf: $med warning(s)" \
    --content "$(printf '%s\n' "$report" | grep ' MED' | head -3 | sed 's/\x1b\[[0-9;]*m//g')" 2>/dev/null || true
fi

if [ "${1:-}" = "--fix" ]; then
  "$HB" perf-fix --yes trim-caches kill-bg anim-fast 2>&1 | tail -5
fi

printf '%s\n' "$report"
