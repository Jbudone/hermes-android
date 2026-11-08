#!/usr/bin/env bash
# tasker-signal — broadcast a Hermes event that Tasker "Intent Received"
# profiles can react to. This is the Hermes -> Tasker direction.
#
#   tasker-signal.sh <EVENT> [data]
#
# In Tasker: Profile → Event → System → Intent Received → Action:
#     net.hermes.phone.EVENT
# Then match on %event / %data inside the linked task.
set -o pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname -- "$HERE")"
# shellcheck source=../lib/android-ops.sh
. "$ROOT/lib/android-ops.sh"

[ $# -ge 1 ] || ao_die "usage: tasker-signal.sh <EVENT> [data]"
event="$1"; data="${2:-}"
cmd="am broadcast -a net.hermes.phone.EVENT --es event \"$event\""
[ -n "$data" ] && cmd="$cmd --es data \"$data\""
ao_sh "$cmd" >/dev/null 2>&1 && ao_ok "signalled: $event ${data:+($data)}" || ao_warn "broadcast failed"
