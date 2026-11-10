#!/usr/bin/env bash
# perf-report — collect device performance telemetry and report findings.
#
#   perf-report.sh [--json] [--collect-only] [--dir DIR]
#
# Collection and analysis are deliberately split: raw dumps land in a run
# directory, analysis reads only from there. That makes the parsers unit
# testable offline against saved fixtures (see test/).
set -o pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname -- "$HERE")"
# shellcheck source=../lib/android-ops.sh
. "$ROOT/lib/android-ops.sh"

JSON=0; COLLECT_ONLY=0; ANALYZE_ONLY=0; DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1 ;;
    --collect-only) COLLECT_ONLY=1 ;;
    --analyze-only) ANALYZE_ONLY=1 ;;
    --dir) DIR="$2"; shift ;;
    -h|--help) sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) ao_die "unknown arg: $1" ;;
  esac; shift
done

if [ -z "$DIR" ]; then
  tgt="$(ao_target)"; DIR="${TMPDIR:-/tmp}/ao-run/$(printf '%s' "$tgt" | tr ':/' '__')/perf-$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$DIR"
echo "$DIR" > "${TMPDIR:-/tmp}/ao-run/last-perf-dir" 2>/dev/null || true

# --------------------------------------------------------------------- collect
collect() {
  ao_info "collecting telemetry -> $DIR"
  local top15="top -b -n 1 -o %CPU -m 15"
  ao_sh_quiet 'top -b -n 1 -o %CPU -m 15' >"$DIR/top.txt" 2>/dev/null
  [ -s "$DIR/top.txt" ] || ao_sh_quiet 'top -b -n 1 -m 20' >"$DIR/top.txt" 2>/dev/null
  ao_sh_quiet 'dumpsys cpuinfo'          >"$DIR/cpuinfo.txt"      2>/dev/null
  ao_sh_quiet 'cat /proc/meminfo'        >"$DIR/proc_meminfo.txt" 2>/dev/null
  ao_sh_quiet 'dumpsys meminfo'          >"$DIR/meminfo.txt"      2>/dev/null
  ao_sh_quiet 'dumpsys battery'          >"$DIR/battery.txt"      2>/dev/null
  ao_sh_quiet 'dumpsys thermalservice'   >"$DIR/thermal.txt"      2>/dev/null
  ao_sh_quiet 'dumpsys power'            >"$DIR/power.txt"        2>/dev/null
  ao_sh_quiet 'dumpsys diskstats'        >"$DIR/diskstats.txt"    2>/dev/null
  ao_sh_quiet 'df -h /data'              >"$DIR/df.txt"           2>/dev/null
  ao_sh_quiet 'logcat -b crash -d -t 200' >"$DIR/crash.txt"       2>/dev/null
  ao_sh_quiet 'logcat -d -t 400'         >"$DIR/logcat.txt"       2>/dev/null
  ao_sh_quiet 'dumpsys activity processes' >"$DIR/processes.txt"  2>/dev/null
  ao_sh_quiet 'settings get global window_animation_scale' >"$DIR/anim.txt" 2>/dev/null
  ao_sh_quiet 'getprop | grep -E "dalvik|hwui|debug.hwui"' >"$DIR/props.txt" 2>/dev/null
  ao_sh_quiet 'dumpsys gfxinfo' >"$DIR/gfxinfo.txt" 2>/dev/null
}
[ "$ANALYZE_ONLY" = 1 ] || collect

if [ "$COLLECT_ONLY" = 1 ]; then ao_ok "collected $(ls -1 "$DIR" | wc -l | tr -d ' ') files"; exit 0; fi
# ---------------------------------------------------------------------- analyze
# Each checker prints findings as: <sev>|<area>|<message>
#   sev ∈ HIGH MED LOW OK
findings() {
  # --- CPU: top consumers from dumpsys cpuinfo (% in $1, "pid/name:" in $2) ---
  if [ -s "$DIR/cpuinfo.txt" ]; then
    awk '
      $1 ~ /^[0-9.]+%$/ && $2 ~ /\// {
        pct=$1; sub(/%/,"",pct);
        name=$2; sub(/^[0-9]+\//,"",name); sub(/:$/,"",name);
        if (pct+0 >= 15) printf("%s|CPU|%s is using %s%% CPU\n", (pct+0>=40?"HIGH":(pct+0>=25?"MED":"LOW")), name, pct);
      }' "$DIR/cpuinfo.txt"
  fi
  # --- Memory ---
  if [ -s "$DIR/proc_meminfo.txt" ]; then
    awk -F'[: ]+' '
      /MemTotal/{t=$2} /MemAvailable/{a=$2}
      END{ if(t>0){ u=(t-a)*100/t; printf("%s|MEM|RAM used %.0f%% (%d MiB free-ish of %d MiB)\n",
             (u>=90?"HIGH":(u>=78?"MED":"LOW")), u, a/1024, t/1024)} }' "$DIR/proc_meminfo.txt"
  fi
  # total PSS line from dumpsys meminfo
  if [ -s "$DIR/meminfo.txt" ]; then
    awk '
      /Total RAM:/{t=$3; gsub(/[^0-9]/,"",t)}
      /Lost RAM:/{v=$3; gsub(/[^0-9]/,"",v)}
      END{ if(t!=""&&v!=""&&t+0>0){ p=v*100/t;
             if(p>5) printf("MED|MEM|Lost RAM is %.1f%% of total (fragmentation/leaks)\n", p);
             else printf("LOW|MEM|Lost RAM %.1f%% of total\n", p) } }' "$DIR/meminfo.txt"
  fi
  # --- Thermal ---
  if [ -s "$DIR/thermal.txt" ]; then
    awk '/Thermal Status/{st=$3} /mStatus/{} END{
        if($0!="") printf("LOW|THERM|thermal status %s\n", st)
    }' "$DIR/thermal.txt"
    awk '
      /Temperature\{/{
        # Temperature{mValue=NN.N, mType=N, mName=..., mStatus=N}
        if (match($0,/mValue=[0-9.]+/)) { v=substr($0,RSTART+7,RLENGTH-7);
          if (v+0>=60) printf("HIGH|THERM|thermal zone at %s C (throttling risk)\n", v);
          else if (v+0>=50) printf("MED|THERM|thermal zone at %s C (warm)\n", v); }
      }' "$DIR/thermal.txt"
  fi
  # --- Battery (only the "Current Battery Service state" block; Samsung appends
  #     a whole ACTION_BATTERY_CHANGED history after it, so cap the input) ---
  if [ -s "$DIR/battery.txt" ]; then
    head -30 "$DIR/battery.txt" | awk '
      /^[ \t]*level:/{lvl=$2} /^[ \t]*temperature:/{t=$2} /^[ \t]*health:/{h=$2} /^[ \t]*status:/{st=$2}
      END{
        if(lvl!="") printf("LOW|BATT|battery %s%%\n", lvl)
        if(t!="")  printf("%s|BATT|battery temp %.1f C\n",(t+0>=400?"MED":"LOW"),t/10)
        if(h=="2")      printf("OK|BATT|battery health good\n")
        else if(h!="")  printf("MED|BATT|battery health code %s (not good)\n",h)
      }'
  fi
  # --- Storage ---
  if [ -s "$DIR/df.txt" ]; then
    awk 'NR>1{ gsub(/%/,"",$5); if($5+0>=90) printf("HIGH|STOR|/data %s%% full\n",$5); else if($5+0>=80) printf("MED|STOR|/data %s%% full\n",$5); else printf("OK|STOR|/data %s%% used\n",$5) }' "$DIR/df.txt"
  fi
  # --- Crashes / ANRs in the last 400 log lines ---
  local crashes anrs
  crashes="$(grep -c -iE 'FATAL EXCEPTION|beginning of crash' "$DIR/crash.txt" "$DIR/logcat.txt" 2>/dev/null | awk -F: '{s+=$2}END{print s+0}')"
  anrs="$(awk '/ANR in /{n++} END{print n+0}' "$DIR/logcat.txt" 2>/dev/null)"
  [ "$crashes" -gt 0 ] && echo "MED|CRASH|$crashes crash signature(s) in recent logs"
  [ "$anrs" -gt 0 ] && echo "HIGH|ANR|$anrs ANR(s) in recent logs"
  # --- Frame times: per-app jank from dumpsys gfxinfo (cumulative since start) ---
  if [ -s "$DIR/gfxinfo.txt" ]; then
    python3 "$ROOT/lib/gfxinfo.py" --file "$DIR/gfxinfo.txt" --findings 2>/dev/null
  fi
  # --- Animation scale (perceived jank) ---
  if [ -s "$DIR/anim.txt" ]; then
    a="$(tr -d '\r' < "$DIR/anim.txt")"
    case "$a" in 0|0.0|0.5|0.25) ;; *) echo "LOW|UX|window_animation_scale=$a (1.0 default; lower feels snappier)";; esac
  fi
  # --- Background process count ---
  if [ -s "$DIR/processes.txt" ]; then
    local bg
    bg="$(grep -c 'Proc #' "$DIR/processes.txt" 2>/dev/null || echo 0)"
    [ "$bg" -gt 150 ] && echo "MED|MEM|$bg cached procs — heavy background pressure (One UI keeps 100-150 normally)"
  fi
}
FL="$DIR/findings.txt"; findings | awk '!seen[$0]++' > "$FL"

if [ "$JSON" = 1 ]; then
  python3 - "$FL" "$DIR" <<'PY'
import json,sys
fl,run=sys.argv[1],sys.argv[2]
items=[]
for line in open(fl):
    line=line.rstrip("\n")
    if not line or "|" not in line: continue
    sev,area,msg=line.split("|",2)
    items.append({"severity":sev,"area":area,"message":msg})
order={"HIGH":0,"MED":1,"LOW":2,"OK":3}
items.sort(key=lambda x:order.get(x["severity"],9))
print(json.dumps({"run_dir":run,"findings":items},indent=2))
PY
  exit 0
fi

echo
echo "Performance report — $(ao_model 2>/dev/null || echo device)  [run: $DIR]"
echo "──────────────────────────────────────────────────────────"
if [ ! -s "$FL" ]; then echo "  (no signals collected — is the device reachable?)"; exit 0; fi
while IFS='|' read -r sev area msg; do
  case "$sev" in
    HIGH) tag=$'\033[31mHIGH\033[0m' ;;
    MED)  tag=$'\033[33m MED\033[0m' ;;
    LOW)  tag=$'\033[36mLOW \033[0m' ;;
    *)    tag=$'\033[32m OK \033[0m' ;;
  esac
  printf '  [%s] %-6s %s\n' "$tag" "$area" "$msg"
done < "$FL"
echo "──────────────────────────────────────────────────────────"
echo "Next: 'hermes-android perf-fix --dry-run' to see safe remediations."
