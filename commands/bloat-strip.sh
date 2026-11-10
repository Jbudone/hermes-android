#!/usr/bin/env bash
# bloat-strip — freeze (disable) or remove (uninstall-for-user) selected apps.
# Everything is REVERSIBLE and journalled.
#
#   bloat-strip.sh --dry-run --freeze <pkg>...      preview
#   bloat-strip.sh --yes  --freeze <pkg>...         apply (reversible: enable)
#   bloat-strip.sh --yes  --remove <pkg>...         apply (reversible: install-existing)
#   bloat-strip.sh --restore <ledger.jsonl>         undo everything in a ledger
#
# Plan mode — go straight from a saved `bloat-audit --json` report:
#   bloat-strip.sh --plan audit.json                      preview the plan
#   bloat-strip.sh --plan audit.json --yes --freeze       apply it
#   bloat-strip.sh --plan audit.json --include-unused --min-mb 50
#
# Safety: a hard blocklist of critical packages is never touched, everything
# already disabled is skipped, and every action is recorded so you can undo it.
set -o pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname -- "$HERE")"
# shellcheck source=../lib/android-ops.sh
. "$ROOT/lib/android-ops.sh"

DRY=1; MODE=""; TARGETS=(); RESTORE=""
PLAN=""; PLAN_OUT=""; MIN_MB=0; INCLUDE_UNUSED=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --yes|-y) DRY=0 ;;
    --freeze) MODE=freeze ;;
    --remove) MODE=remove ;;
    --restore) RESTORE="$2"; shift ;;
    --plan) PLAN="$2"; shift ;;
    --plan-out) PLAN_OUT="$2"; shift ;;
    --min-mb) MIN_MB="$2"; shift ;;
    --include-unused) INCLUDE_UNUSED=1 ;;
    -h|--help) sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) ao_die "unknown flag: $1" ;;
    *) TARGETS+=("$1") ;;
  esac; shift
done

# Never strip these, whatever the input says.
BLOCK_RE='^(com\.android\.systemui|com\.android\.settings|com\.android\.phone|com\.android\.shell|com\.android\.providers\.settings|com\.google\.android\.gms|com\.google\.android\.gsf|com\.google\.android\.permissioncontroller|com\.android\.launcher3|android|com\.termux|net\.dinglisch\.android\.taskerm|com\.topjohnwu\.magisk)$'

RUNDIR="${TMPDIR:-/tmp}/ao-run/$(ao_target | tr ':/' '__')"
mkdir -p "$RUNDIR"
LEDGER="${RUNDIR}/bloat-strip-ledger.jsonl"
J() { printf '{"ts":%s,"mode":"%s","package":"%s","applied":%s%s}\n' \
        "$(date +%s)" "$1" "$2" "$3" "${4:+,$4}" >> "$LEDGER"; }

blocked() { printf '%s' "$1" | grep -Eq "$BLOCK_RE"; }

restore() {
  local f="$1"
  [ -f "$f" ] || ao_die "ledger not found: $f"
  ao_info "restoring from $f"
  while IFS= read -r line; do
    pkg="$(printf '%s' "$line" | sed -n 's/.*"package":"\([^"]*\)".*/\1/p')"
    mode="$(printf '%s' "$line" | sed -n 's/.*"mode":"\([^"]*\)".*/\1/p')"
    [ -z "$pkg" ] && continue
    if [ "$mode" = freeze ]; then ao_sh "pm enable --user 0 $pkg" >/dev/null 2>&1 && ao_ok "enabled $pkg" || ao_warn "could not enable $pkg"
    else ao_sh "cmd package install-existing --user 0 $pkg" >/dev/null 2>&1 && ao_ok "reinstalled $pkg" || ao_warn "could not reinstall $pkg"; fi
  done < "$f"
}

if [ -n "$RESTORE" ]; then restore "$RESTORE"; exit 0; fi
[ -z "$MODE" ] && ao_die "choose --freeze or --remove (see --help)"
if [ -n "$PLAN" ] && [ "${#TARGETS[@]}" -gt 0 ]; then
  ao_die "--plan already carries the package list; drop the extra arguments"
fi
if [ -z "$PLAN" ] && [ "${#TARGETS[@]}" -eq 0 ]; then
  ao_die "no packages given (or pass --plan <bloat-audit --json output>)"
fi

# ------------------------------------------------------------------- plan mode
if [ -n "$PLAN" ]; then
  [ -f "$PLAN" ] || ao_die "plan source not found: $PLAN"
  PLAN_OUT="${PLAN_OUT:-$RUNDIR/bloat-plan-$(date +%Y%m%d-%H%M%S).json}"
  # Resolve candidates -> concrete package list; write the reviewable plan.
  mapfile -t TARGETS < <(python3 - "$PLAN" "$PLAN_OUT" "$MODE" "$MIN_MB" "$INCLUDE_UNUSED" "$DRY" <<'PY'
import json, sys, time
src, out, mode, min_mb, include_unused, dry = sys.argv[1:7]
min_mb = int(min_mb); include_unused = include_unused == "1"
try:
    audit = json.load(open(src, encoding="utf-8"))
except Exception as e:
    print("error: cannot parse %s: %s" % (src, e), file=sys.stderr); sys.exit(1)
if "bloat_candidates" not in audit:
    print("error: %s is not `bloat-audit --json` output (no bloat_candidates)" % src, file=sys.stderr)
    sys.exit(1)
groups = [("BLOAT", audit.get("bloat_candidates") or [])]
if include_unused:
    groups.append(("UNUSED", audit.get("unused_candidates") or []))
picked, seen, skipped = [], set(), []
for label, rows in groups:
    for r in rows:
        pkg = r.get("package")
        if not pkg or pkg in seen: continue
        seen.add(pkg)
        if r.get("disabled"):
            skipped.append({"package": pkg, "why": "already disabled"}); continue
        if (r.get("mb") or 0) < min_mb:
            skipped.append({"package": pkg, "why": "below --min-mb %d" % min_mb}); continue
        picked.append({"package": pkg, "mb": r.get("mb", 0), "tags": r.get("tags", []),
                       "reason": label})
picked.sort(key=lambda r: -(r["mb"] or 0))
plan = {"schema": "hermes-android/bloat-plan", "version": 1, "created": int(time.time()),
        "source": src, "mode": mode, "dry_run": dry == "1",
        "min_mb": min_mb, "include_unused": include_unused,
        "packages": picked, "skipped": skipped}
with open(out, "w", encoding="utf-8") as f:
    json.dump(plan, f, indent=2)
    f.write("\n")
for r in picked:
    print(r["package"])
print("plan-file: %s" % out, file=sys.stderr)
print("selected: %d candidate(s), %d skipped (already disabled / below --min-mb)" %
      (len(picked), len(skipped)), file=sys.stderr)
PY
  )
  # mapfile keeps a trailing "plan-file:" only on stderr, so TARGETS is clean.
fi

echo
echo "bloat-strip [$MODE] $([ "$DRY" = 1 ] && echo '(DRY RUN)' || echo '(APPLYING)') on $(ao_model)"
[ -n "$PLAN" ] && echo "plan: $PLAN_OUT"
for pkg in "${TARGETS[@]}"; do
  if blocked "$pkg"; then ao_warn "SKIP (protected): $pkg"; continue; fi
  if [ "$MODE" = freeze ]; then cmd="pm disable-user --user 0 $pkg"; else cmd="pm uninstall -k --user 0 $pkg"; fi
  if [ "$DRY" = 1 ]; then
    printf '  would %s: %s\n      adb shell %s\n' "$MODE" "$pkg" "$cmd"; J "$MODE" "$pkg" false; continue
  fi
  printf '  • %s %s\n' "$MODE" "$pkg"
  if ao_sh "$cmd" >/dev/null 2>&1; then ao_ok "done"; J "$MODE" "$pkg" true; else ao_warn "failed"; J "$MODE" "$pkg" false; fi
done
echo
echo "reversible ledger: $LEDGER"
echo "restore all later: hermes-android bloat-strip --restore $LEDGER"