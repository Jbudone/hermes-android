#!/usr/bin/env bash
# bloat-strip — freeze (disable) or remove (uninstall-for-user) selected apps.
# Everything is REVERSIBLE and journalled.
#
#   bloat-strip.sh --dry-run --freeze <pkg>...      preview
#   bloat-strip.sh --yes  --freeze <pkg>...         apply (reversible: enable)
#   bloat-strip.sh --yes  --remove <pkg>...         apply (reversible: install-existing)
#   bloat-strip.sh --restore <ledger.jsonl>         undo everything in a ledger
#
# Safety: a hard blocklist of critical packages is never touched, and every
# action is recorded so you can always undo it.
set -o pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname -- "$HERE")"
# shellcheck source=../lib/android-ops.sh
. "$ROOT/lib/android-ops.sh"

DRY=1; MODE=""; TARGETS=(); RESTORE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --yes|-y) DRY=0 ;;
    --freeze) MODE=freeze ;;
    --remove) MODE=remove ;;
    --restore) RESTORE="$2"; shift ;;
    -h|--help) sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) ao_die "unknown flag: $1" ;;
    *) TARGETS+=("$1") ;;
  esac; shift
done

# Never strip these, whatever the input says.
BLOCK_RE='^(com\.android\.systemui|com\.android\.settings|com\.android\.phone|com\.android\.shell|com\.android\.providers\.settings|com\.google\.android\.gms|com\.google\.android\.gsf|com\.google\.android\.permissioncontroller|com\.android\.launcher3|android|com\.termux|net\.dinglisch\.android\.taskerm|com\.topjohnwu\.magisk)$'

RUNDIR="${TMPDIR:-/tmp}/ao-run/$(ao_target | tr ':/' '__')"
mkdir -p "$RUNDIR"
LEDGER="${RUNDIR}/bloat-strip-ledger.jsonl"
J() { printf '{"ts":%s,"mode":"%s","package":"%s","applied":%s}\n' "$(date +%s)" "$1" "$2" "$3" >> "$LEDGER"; }

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
[ "${#TARGETS[@]}" -eq 0 ] && ao_die "no packages given"

echo
echo "bloat-strip [$MODE] $([ "$DRY" = 1 ] && echo '(DRY RUN)' || echo '(APPLYING)') on $(ao_model)"
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
[ "$DRY" = 1 ] && echo "undo anytime with: hermes-android bloat-strip --restore $LEDGER"
echo "restore all later: hermes-android bloat-strip --restore $LEDGER"
