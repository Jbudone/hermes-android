#!/usr/bin/env bash
# tasker-run — run a named Tasker task from Hermes (or from a Termux script).
#
#   tasker-run.sh "My Task Name" [par1] [par2]
#
# Requires Tasker: Preferences → Misc → "Allow External Access" ON.
# Uses Tasker's documented external-access intent.
set -o pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname -- "$HERE")"
# shellcheck source=../lib/android-ops.sh
. "$ROOT/lib/android-ops.sh"

[ $# -ge 1 ] || ao_die 'usage: tasker-run.sh "Task Name" [par1] [par2]'
name="$1"; p1="${2:-}"; p2="${3:-}"

cmd="am broadcast -a net.dinglisch.android.taskerm.ACTION_TASK --es task_name \"$name\""
[ -n "$p1" ] && cmd="$cmd --es par1 \"$p1\""
[ -n "$p2" ] && cmd="$cmd --es par2 \"$p2\""

ao_info "running Tasker task: $name"
ao_sh "$cmd" >/dev/null 2>&1 || ao_die "broadcast failed (is Tasker 'Allow External Access' enabled?)"
ao_ok "sent: $name"
