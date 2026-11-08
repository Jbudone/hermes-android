#!/data/data/com.termux/files/usr/bin/bash
# briefing.sh — a "daily briefing" Tasker building block: ask Hermes for a short
# phone-health digest and surface it as a notification. Wire it to a time
# profile (e.g. 07:30) or a widget.
set -e
export PATH="/data/data/com.termux/files/usr/bin:$PATH"
HB="$HOME/hermes-android/bin/hermes-android"

insights="$("$HB" insights 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"
answer="$(hermes chat -q "Here is my phone's raw insights output. In 3 short bullet points, tell me anything that needs my attention today:

$insights" 2>&1 | tail -20)"

termux-notification --title "📱 Phone briefing" --content "$answer" 2>/dev/null || true
printf '%s\n' "$answer"
