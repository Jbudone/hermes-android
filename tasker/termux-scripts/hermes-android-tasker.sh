#!/data/data/com.termux/files/usr/bin/bash
# hermes-android-tasker.sh <subcommand> [args...]
# A thin, stable entry point for Termux:Tasker: config the plugin once against
# this script, then drive any toolkit command by changing the Arguments field.
#
#   Arguments: perf
#   Arguments: bloat
#   Arguments: insights
#   Arguments: tasker-signal   battery_low   15
set -e
export PATH="/data/data/com.termux/files/usr/bin:$PATH"
HB="$HOME/hermes-android/bin/hermes-android"
[ -x "$HB" ] || { echo "toolkit missing at $HB"; exit 2; }
exec "$HB" "$@"
