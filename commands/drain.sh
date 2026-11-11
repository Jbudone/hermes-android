#!/usr/bin/env bash
# drain.sh — sample CPU over time and rank the processes that keep burning it.
#
# A single `top`/`dumpsys cpuinfo` snapshot is noise (it caught "30% systemui"
# once and ~5% the next). This averages N frames across a window so persistent
# offenders separate from spikes. Watch for kswapd0 (swap thrashing → memory
# pressure) and system_server/HeapTaskDaemon (GC churn) — those mean the fix is
# less resident memory, not another app restriction.
#
#   hermes-android drain                 # 6 frames x 10s, top 15
#   hermes-android drain --frames 12 --interval 5 --top 20
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/android-ops.sh
. "$HERE/../lib/android-ops.sh"

frames=6; interval=10; topn=15
while [ $# -gt 0 ]; do
  case "$1" in
    --frames)   frames="$2"; shift ;;
    --interval) interval="$2"; shift ;;
    --top)      topn="$2"; shift ;;
    -h|--help)  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) ao_die "unknown arg: $1 (try: drain [--frames N] [--interval S] [--top N])" ;;
  esac; shift
done

tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
ao_info "sampling CPU: $frames frames, ${interval}s apart" >&2
i=0
while [ "$i" -lt "$frames" ]; do
  ao_sh "dumpsys cpuinfo 2>/dev/null | sed -n '2,25p'" >> "$tmp" 2>/dev/null || true
  printf -- '----FRAME----\n' >> "$tmp"
  i=$((i+1))
  [ "$i" -lt "$frames" ] && sleep "$interval"
done

python3 - "$tmp" "$topn" <<'PY'
import re, sys, collections
path, topn = sys.argv[1], int(sys.argv[2])
frames = [f for f in open(path).read().split('----FRAME----') if f.strip()]
tot = collections.Counter(); mx = collections.Counter(); n = 0
for f in frames:
    n += 1
    for line in f.splitlines():
        m = re.match(r'\s*([\d.]+)%\s+\d+/([^:\s]+)', line)
        if m:
            pct = float(m.group(1)); nm = m.group(2)
            tot[nm] += pct; mx[nm] = max(mx[nm], pct)
print(f"CPU drain over {n} frame(s)")
print(f"{'process':44s} {'avg%':>6} {'max%':>6}")
for nm, _ in tot.most_common(topn):
    print(f"{nm:44s} {tot[nm]/n:6.1f} {mx[nm]:6.1f}")
if any(k.startswith('kswapd') for k in tot):
    print("\nnote: kswapd is active — the phone is swapping; reduce resident memory.")
PY
