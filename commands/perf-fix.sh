#!/usr/bin/env bash
# perf-fix — apply safe, reversible performance remediations.
#
#   perf-fix.sh --dry-run            show what would change (default)
#   perf-fix.sh --yes <action>...    apply named actions
#   perf-fix.sh --list               list available actions
#
# Every applied action is journalled to <run>/perf-fix-ledger.jsonl so the
# change is auditable and (where possible) reversible.
set -o pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname -- "$HERE")"
# shellcheck source=../lib/android-ops.sh
. "$ROOT/lib/android-ops.sh"

DRY=1; YES=0; LIST=0; ACTIONS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --yes|-y)  DRY=0; YES=1 ;;
    --list)    LIST=1 ;;
    -*) ao_die "unknown flag: $1" ;;
    *) ACTIONS+=("$1") ;;
  esac; shift
done

cat <<'ACTIONS'
Available perf actions (all via adb shell; all reversible unless noted):
  trim-caches     Free space by trimming all apps' caches (pm trim-caches)
  kill-bg         Kill background processes (am kill-all) — no data loss
  anim-fast       Set window/transition/animator scales to 0.5 (feels snappier)
  anim-default    Restore animation scales to 1.0
  compile-speed   AOT-compile ALL packages for speed (HEAVY: minutes; reversible)
  doze-now        Force the device into Doze now (dumpsys deviceidle force-idle)
  restrict <pkg>  Deny RUN_IN_BACKGROUND for a package (stops rogue background)
  unrestrict <pkg> Undo restrict for a package
ACTIONS
[ "$LIST" = 1 ] && exit 0

RUN="${TMPDIR:-/tmp}/ao-run/$(ao_target | tr ':/' '__')/fix-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN"
LEDGER="$RUN/perf-fix-ledger.jsonl"
J() { printf '%s\n' "{\"ts\":$(date +%s),\"action\":\"$1\",\"cmd\":\"$2\",\"applied\":$3}" >> "$LEDGER"; }

run() { # run <label> <cmd>
  local label="$1" cmd="$2"
  if [ "$DRY" = 1 ]; then
    printf '  would run: %s\n      (adb shell %s)\n' "$label" "$cmd"; J "$label" "$cmd" false; return 0
  fi
  printf '  • %s\n' "$label"
  if ao_sh "$cmd" >/dev/null 2>&1; then J "$label" "$cmd" true; ao_ok "done"
  else ao_warn "failed: $label"; J "$label" "$cmd" false; fi
}

[ "${#ACTIONS[@]}" -eq 0 ] && { [ "$DRY" = 1 ] && ACTIONS=(trim-caches kill-bg anim-fast); }

echo
echo "perf-fix $([ "$DRY" = 1 ] && echo '(DRY RUN — nothing changes)' || echo '(APPLYING)') on $(ao_model)"
echo "run dir: $RUN"

for a in "${ACTIONS[@]}"; do
  case "$a" in
    trim-caches) run "trim-caches (target 4GiB free)" "pm trim-caches 4294967296" ;;
    kill-bg)     run "kill background processes" "am kill-all" ;;
    anim-fast)   run "animation scales -> 0.5" "settings put global window_animation_scale 0.5 && settings put global transition_animation_scale 0.5 && settings put global animator_duration_scale 0.5" ;;
    anim-default)run "animation scales -> 1.0" "settings put global window_animation_scale 1.0 && settings put global transition_animation_scale 1.0 && settings put global animator_duration_scale 1.0" ;;
    compile-speed) run "AOT compile all packages (heavy)" "cmd package compile -m speed -a" ;;
    doze-now)    run "force Doze" "dumpsys deviceidle force-idle" ;;
    restrict\ *) pkg="${a#restrict }"; run "restrict background: $pkg" "cmd appops set $pkg RUN_IN_BACKGROUND deny && cmd appops set $pkg RUN_ANY_IN_BACKGROUND deny" ;;
    unrestrict\ *) pkg="${a#unrestrict }"; run "unrestrict background: $pkg" "cmd appops set $pkg RUN_IN_BACKGROUND allow && cmd appops set $pkg RUN_ANY_IN_BACKGROUND allow" ;;
    *) ao_warn "skipping unknown action: $a" ;;
  esac
done

echo
[ "$DRY" = 1 ] && { echo "Re-run with '--yes' and the actions you want, e.g.:"; echo "  hermes-android perf-fix --yes trim-caches kill-bg anim-fast"; }
echo "ledger: $LEDGER"
