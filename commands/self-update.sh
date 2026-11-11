#!/usr/bin/env bash
# self-update.sh — pull the latest toolkit into ~/hermes-android on the device.
# Handy from a Termux:Widget shortcut or a Tasker plugin action so the phone can
# refresh itself without opening Termux by hand.
set -u
export PATH="/data/data/com.termux/files/usr/bin:$PATH"
H="$HOME/hermes-android"
if [ ! -d "$H/.git" ]; then
  echo "self-update: no git repo at $H"
  exit 1
fi
before="$(git -C "$H" rev-parse --short HEAD 2>/dev/null)"
if git -C "$H" pull --ff-only >/dev/null 2>&1; then
  st=ok
else
  st=fail
fi
after="$(git -C "$H" rev-parse --short HEAD 2>/dev/null)"
chmod +x "$H"/bin/* "$H"/commands/*.sh 2>/dev/null || true
printf 'self-update: %s %s -> %s\n' "$st" "$before" "$after"
