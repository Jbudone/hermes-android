#!/usr/bin/env bash
# bloat-audit — find removable / unused / heavy apps and preset OEM bloat.
#
#   bloat-audit.sh [--json] [--dir DIR] [--min-mb N]
#
# Writes raw dumps into a run dir and analyses them, so the classifier is unit
# testable offline.
set -o pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname -- "$HERE")"
# shellcheck source=../lib/android-ops.sh
. "$ROOT/lib/android-ops.sh"

JSON=0; DIR=""; MIN_MB=0; ANALYZE_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1 ;;
    --dir) DIR="$2"; shift ;;
    --min-mb) MIN_MB="$2"; shift ;;
    --analyze-only) ANALYZE_ONLY=1 ;;
    -h|--help) sed -n '2,6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) ao_die "unknown arg: $1" ;;
  esac; shift
done

if [ -z "$DIR" ]; then DIR="${TMPDIR:-/tmp}/ao-run/$(ao_target | tr ':/' '__')/bloat-$(date +%Y%m%d-%H%M%S)"; fi
mkdir -p "$DIR"

# --------------------------------------------------------------------- collect
if [ "$ANALYZE_ONLY" = 0 ]; then
ao_info "collecting package inventory -> $DIR"
ao_sh_quiet 'pm list packages --user 0 -3'         >"$DIR/pkgs-3p.txt"    2>/dev/null  # third-party
ao_sh_quiet 'pm list packages --user 0 -s'         >"$DIR/pkgs-system.txt" 2>/dev/null # system
ao_sh_quiet 'pm list packages --user 0 -d'         >"$DIR/pkgs-disabled.txt" 2>/dev/null
ao_sh_quiet 'pm list packages --user 0 -e'         >"$DIR/pkgs-enabled.txt" 2>/dev/null
ao_sh_quiet 'dumpsys diskstats'                   >"$DIR/diskstats.txt"  2>/dev/null
ao_sh_quiet 'dumpsys usagestats'                  >"$DIR/usagestats.txt" 2>/dev/null
ao_sh_quiet 'dumpsys package packages'            >"$DIR/package.txt"    2>/dev/null
fi

if [ ! -s "$DIR/pkgs-3p.txt" ] && [ ! -s "$DIR/pkgs-system.txt" ]; then
  ao_die "could not read package list (device unreachable?)"
fi

# --------------------------------------------------------------------- analyze
python3 - "$DIR" "$JSON" "$MIN_MB" <<'PY'
import os,re,json,sys,collections,time
d,as_json,min_mb=sys.argv[1],sys.argv[2]=="1",int(sys.argv[3])

def lines(f):
    p=os.path.join(d,f)
    return open(p,encoding="utf-8",errors="replace").read().splitlines() if os.path.exists(p) else []

def pkgs(f):
    out=set()
    for l in lines(f):
        l=l.strip()
        if l.startswith("package:"): out.add(l.split(":",1)[1].strip())
    return out

third=pkgs("pkgs-3p.txt"); system=pkgs("pkgs-system.txt")
disabled=pkgs("pkgs-disabled.txt"); enabled=pkgs("pkgs-enabled.txt")
allpkg=third|system

# --- sizes from dumpsys diskstats (Android 14+ emits JSON-quoted name arrays
#     and separate App / Data / Cache size arrays; sum them per package) ---
sizes={}
appsize=[]; datasize=[]; cachesize=[]; names=[]
for l in lines("diskstats.txt"):
    if l.startswith("Package Names:"):
        names=re.findall(r'"([^"]+)"', l) or [x.strip() for x in l.split(":",1)[1].strip().strip("[]").split(",") if x.strip()]
    elif l.startswith("App Data Sizes:"):
        datasize=[int(x) for x in re.findall(r"\d+", l.split(":",1)[1])]
    elif l.startswith("App Sizes:"):
        appsize=[int(x) for x in re.findall(r"\d+", l.split(":",1)[1])]
    elif l.startswith("Cache Sizes:"):
        cachesize=[int(x) for x in re.findall(r"\d+", l.split(":",1)[1])]
for i,n in enumerate(names):
    a  = appsize[i]   if i < len(appsize)   else 0
    dd = datasize[i]  if i < len(datasize)  else 0
    c  = cachesize[i] if i < len(cachesize) else 0
    sizes[n]=a+dd+c

# --- last-used from dumpsys usagestats (Android 12+ = an event log:
#     time="..." type=ACTIVITY_RESUMED package=...) ---
last={}
for l in lines("usagestats.txt"):
    m=re.search(r'time="([^"]+)".*?type=(\w+).*?package=([A-Za-z0-9_.]+)', l)
    if not m: continue
    ts,tp,pkg=m.group(1),m.group(2),m.group(3)
    if tp not in ("ACTIVITY_RESUMED","MOVE_TO_FOREGROUND"): continue
    try:
        e=int(time.mktime(time.strptime(ts,"%Y-%m-%d %H:%M:%S")))
    except Exception:
        continue
    if e>last.get(pkg,0): last[pkg]=e
now=int(time.time())
def age_days(p):
    t=last.get(p)
    return None if not t else (now-t)//86400

# --- OEM / carrier / junk bloat patterns (heuristic, safe to extend) ---
BLOAT={
 "facebook":("social junk","com.facebook."),
 "meta":("social junk","com.facebook.appmanager"),
 "carrier":("carrier apps","com.android.carrier"),
 "samsung-suggested":("OEM content","com.samsung.android.app.suggest"),
 "samsung-bixby":("assistant bloat","com.samsung.android.bixby"),
 "samsung-notes":("duplicate apps","com.samsung.android.app.notes"),
 "games":("preinstalled games","com.gameloft."),
 "netflix-oem":("OEM media","com.netflix.partner"),
 "ms-office":("duplicate office","com.microsoft.office"),
 "linkedin-oem":("OEM social","com.linkedin.android.oem"),
 "gmail-via-oem":("dup mail","com.google.android.gm.zen"),
}
def classify(p):
    tags=[]
    if p in third: tags.append("3rd-party")
    if p in disabled: tags.append("DISABLED")
    for k,(label,pat) in BLOAT.items():
        if p.startswith(pat) or p==pat: tags.append("BLOAT:"+label)
    return tags

rows=[]
for p in sorted(allpkg):
    size=sizes.get(p,0)
    if size and size//1048576 < min_mb and min_mb>0: continue
    tags=classify(p)
    a=age_days(p)
    unused = (a is not None and a>=90 and p in third)
    if unused: tags.append("UNUSED:%dd"%a)
    if not tags and p in system and size==0: continue
    rows.append({"package":p,"mb":round(size/1048576,1),"days_unused":a,
                 "disabled":p in disabled,"third_party":p in third,"tags":tags})

rows.sort(key=lambda r:r["mb"],reverse=True)
bloat=[r for r in rows if any(t.startswith("BLOAT") for t in r["tags"])]
unused=[r for r in rows if any(t.startswith("UNUSED") for t in r["tags"])]

if as_json:
    print(json.dumps({"run_dir":d,"third_party":sorted(third),"disabled":sorted(disabled),
                      "bloat_candidates":bloat,"unused_candidates":unused,
                      "all":rows},indent=2))
    sys.exit(0)

def show(title,items):
    print(); print(title); print("─"*72)
    if not items: print("  (none)") ; return
    for r in items[:40]:
        print("  %-46s %7.1f MB  %s" % (r["package"], r["mb"], ",".join(r["tags"])))

print("Bloat audit — %d packages (%d third-party, %d disabled)   [run: %s]" % (len(allpkg),len(third),len(disabled),d))
show("BLOAT CANDIDATES (OEM/carrier/preset junk)",bloat)
show("UNUSED CANDIDATES (3rd-party, not used in 90+ days)",unused)
print()
print("Largest installed packages:")
print("─"*72)
for r in rows[:20]:
    kind="3p" if r["third_party"] else "sys"
    print("  %-46s %7.1f MB  [%s]" % (r["package"], r["mb"], kind))
print()
print("Next: 'hermes-android bloat-strip --dry-run' to review removals (reversible).")
PY
