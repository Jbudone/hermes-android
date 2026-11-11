#!/usr/bin/env bash
# keepalive.sh — keep the on-device agent alive in the background.
#
# Run it from a Tasker profile (Event -> System -> Device Boot, and/or periodic)
# via the Termux:Tasker plugin, with Arguments = "keepalive" (single token, so
# it survives the plugin's space-splitting). It:
#   1. acquires a Termux wake-lock (best effort),
#   2. records a heartbeat file (proof the agent ran),
#   3. re-asserts the daily digest job if it has gone missing.
# Prints a one-line status, which lands in Tasker's %stdout.
set -u
export PATH="/data/data/com.termux/files/usr/bin:$PATH"

STATE="$HOME/.hermes-android-keepalive"
mkdir -p "$STATE" 2>/dev/null || true

lock=off
if command -v termux-wake-lock >/dev/null 2>&1; then
  if termux-wake-lock 2>/dev/null; then lock=on; fi
fi

date '+%F %T' > "$STATE/heartbeat" 2>/dev/null || true

digest=skip
if command -v termux-job-scheduler >/dev/null 2>&1; then
  if termux-job-scheduler --pending 2>/dev/null | grep -q 1001; then
    digest=present
  else
    termux-job-scheduler --script "$HOME/.termux/tasker/digest.sh" \
      --period-ms 86400000 --persisted true --network any --job-id 1001 \
      >/dev/null 2>&1 && digest=re-added || digest=failed
  fi
fi

printf 'keepalive: wake-lock=%s digest=%s at %s\n' "$lock" "$digest" "$(date '+%F %T')"
