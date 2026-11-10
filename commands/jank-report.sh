#!/usr/bin/env bash
# jank-report — per-app frame-time / jank analysis from `dumpsys gfxinfo`.
#
#   jank-report.sh [--json] [--top N] [--min-frames N] [--dir DIR]
#   jank-report.sh --analyze-only [--dir DIR]      re-analyse a saved dump
#   jank-report.sh --reset <pkg>...                clear frame counters first
#
# Counters are cumulative since each process started (often since boot), so a
# freshly-reset app gives a windowed measurement:
#   jank-report.sh --reset com.discord && use the app && jank-report.sh
#
# Collection and analysis are split; the parser is lib/gfxinfo.py and is
# tested offline against test/fixtures/gfxinfo/.
set -o pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname -- "$HERE")"
# shellcheck source=../lib/android-ops.sh
. "$ROOT/lib/android-ops.sh"

JSON=0; ANALYZE_ONLY=0; DIR=""; TOP=15; MIN_FRAMES=200; RESET=()
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1 ;;
    --analyze-only) ANALYZE_ONLY=1 ;;
    --dir) DIR="$2"; shift ;;
    --top) TOP="$2"; shift ;;
    --min-frames) MIN_FRAMES="$2"; shift ;;
    --reset) shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do RESET+=("$1"); shift; done; continue ;;
    -h|--help) sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) ao_die "unknown arg: $1" ;;
    *) ao_die "unexpected argument: $1 (--reset takes the package names)" ;;
  esac; shift
done

if [ -z "$DIR" ]; then
  tgt="$(ao_target)"; DIR="${TMPDIR:-/tmp}/ao-run/$(printf '%s' "$tgt" | tr ':/' '__')/jank-$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$DIR"

if [ "${#RESET[@]}" -gt 0 ]; then
  for pkg in "${RESET[@]}"; do
    ao_sh_quiet "dumpsys gfxinfo $pkg reset" >/dev/null
    ao_info "reset frame counters: $pkg"
  done
fi

if [ "$ANALYZE_ONLY" = 0 ]; then
  ao_info "collecting gfxinfo -> $DIR/gfxinfo.txt"
  ao_sh_quiet 'dumpsys gfxinfo' >"$DIR/gfxinfo.txt" 2>/dev/null
fi
[ -s "$DIR/gfxinfo.txt" ] || ao_die "no gfxinfo data in $DIR (device unreachable, or --reset/collect never ran)"

if [ "$JSON" = 1 ]; then
  exec python3 "$ROOT/lib/gfxinfo.py" --file "$DIR/gfxinfo.txt" \
       --min-frames "$MIN_FRAMES" --top "$TOP" --json
fi

echo
echo "Jank report — $(ao_model 2>/dev/null || echo device)  [run: $DIR]"
python3 "$ROOT/lib/gfxinfo.py" --file "$DIR/gfxinfo.txt" --min-frames "$MIN_FRAMES" --top "$TOP"
echo
echo "Counters are cumulative since each process started — reset an app with"
echo "'jank-report --reset <pkg>' before measuring it in isolation."
echo "Next: 'hermes-android perf-fix' for safe remediations that reduce jank."