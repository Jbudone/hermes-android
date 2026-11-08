#!/usr/bin/env bash
# insights — battery drain, wakelocks, storage and usage intelligence.
#
#   insights.sh [--json] [--dir DIR]
set -o pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname -- "$HERE")"
# shellcheck source=../lib/android-ops.sh
. "$ROOT/lib/android-ops.sh"

JSON=0; DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1 ;;
    --dir) DIR="$2"; shift ;;
    -h|--help) sed -n '2,5p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) ao_die "unknown arg: $1" ;;
  esac; shift
done
[ -z "$DIR" ] && DIR="${TMPDIR:-/tmp}/ao-run/$(ao_target | tr ':/' '__')/insights-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DIR"

ao_info "collecting -> $DIR"
ao_sh_quiet 'dumpsys batterystats --charged' >"$DIR/batterystats.txt" 2>/dev/null
ao_sh_quiet 'dumpsys batterystats'           >"$DIR/batterystats-full.txt" 2>/dev/null
ao_sh_quiet 'dumpsys power'                  >"$DIR/power.txt" 2>/dev/null
ao_sh_quiet 'dumpsys usagestats'             >"$DIR/usagestats.txt" 2>/dev/null
ao_sh_quiet 'dumpsys netstats detail'        >"$DIR/netstats.txt" 2>/dev/null
ao_sh_quiet 'df -h /data'                    >"$DIR/df.txt" 2>/dev/null
ao_sh_quiet 'dumpsys diskstats'              >"$DIR/diskstats.txt" 2>/dev/null

python3 - "$DIR" "$JSON" <<'PY'
import os,re,json,sys
d,as_json=sys.argv[1],sys.argv[2]=="1"
def txt(f):
    p=os.path.join(d,f)
    return open(p,encoding="utf-8",errors="replace").read() if os.path.exists(p) else ""
out={"run_dir":d,"battery":{},"wakelocks":[],"screen_time":{},"storage":{},"network":{}}

bs=txt("batterystats.txt") or txt("batterystats-full.txt")
for k,pat in [("capacity","Estimated capacity.*?(\\d+)%"),("time_on_battery","Time on battery:.*?([\\d]+h?[\\d]*m?)")]:
    m=re.search(pat,bs); 
    if m: out["battery"][k]=m.group(1)
m=re.search(r'Time on battery screen off:.*?([0-9hms ]+)',bs)
if m: out["screen_time"]["off"]=m.group(1).strip()
m=re.search(r'Time on battery:.*?([0-9hms ]+)',bs)
if m: out["screen_time"]["on"]=m.group(1).strip()

# wakelocks: "Wake lock <name>: <time> ..." full / partial
for m in re.finditer(r'Wake lock\s+(\S+):\s+([\dhm s]+)\s+partial',bs):
    name,val=m.group(1),m.group(2).strip()
    if val not in ("0","0s","0ms"): out["wakelocks"].append({"name":name,"activity":val})
# top partial waklocks block
for m in re.finditer(r'^\s*(\d[\d,]*)\s+(\S+)\s*$',bs,re.M):
    pass

# storage from df
for line in txt("df.txt").splitlines():
    if line.startswith("/dev") or " /data" in line or line.strip().endswith("/data"):
        cols=line.split()
        if len(cols)>=5:
            out["storage"]={"size":cols[1],"used":cols[2],"avail":cols[3],"pct":cols[4]}

# network totals from netstats
tot=[int(x) for x in re.findall(r'(?:rxBytes|txBytes)=(\d+)',txt("netstats.txt"))]
if tot: out["network"]["total_bytes"]=sum(tot)

if as_json:
    print(json.dumps(out,indent=2)); sys.exit(0)

b=out["battery"]; st=out["screen_time"]; s=out["storage"]; n=out["network"]
print(); print("Insights — %s   [run: %s]" % (os.uname().nodename, d)); print("─"*68)
print("Battery")
print("  capacity          %s" % b.get("capacity","?"))
print("  time on battery   %s" % st.get("on","?"))
print("  screen-off time   %s" % st.get("off","?"))
print()
print("Top wakelocks (partial)")
if out["wakelocks"]:
    for w in sorted(out["wakelocks"],key=lambda x:x["activity"],reverse=True)[:15]:
        print("  %-44s %s" % (w["name"][:44], w["activity"]))
else:
    print("  (none parsed — try: adb shell dumpsys batterystats | grep -i 'wake lock')")
print()
print("Storage (/data)")
print("  %s" % (("used %s of %s (%s)"%(s.get("used"),s.get("size"),s.get("pct"))) if s else "unknown"))
if n:
    gb=n["total_bytes"]/(1024**3)
    print("  network total    %.2f GiB since stats reset" % gb)
print()
PY
