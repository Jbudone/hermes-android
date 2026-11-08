#!/usr/bin/env bash
# run-tests.sh — offline test suite for the Hermes Android toolkit.
# Everything here runs without a phone: shell syntax, the Tasker XML generator,
# and the telemetry/inventory parsers against saved fixtures.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname -- "$HERE")"
FIX="$HERE/fixtures"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  \033[31m✗\033[0m %s\n' "$1"; }
expect_contains() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing: $2)" ;; esac; }

echo "== 1. shell syntax =="
for f in "$ROOT"/lib/*.sh "$ROOT"/bin/hermes-android "$ROOT"/commands/*.sh; do
  if bash -n "$f" 2>/dev/null; then ok "syntax $(basename "$f")"; else bad "syntax $(basename "$f")"; fi
done

echo "== 2. python compiles =="
if python3 -m py_compile "$ROOT/tasker/gen_tsk.py" "$HERE/validate_xml.py" 2>/dev/null; then ok "py_compile"; else bad "py_compile"; fi

echo "== 3. Tasker XML generation =="
TMP="$(mktemp -d)"
out="$TMP/hermes-ask.tsk.xml"
if python3 "$ROOT/tasker/gen_tsk.py" --name "Hermes Ask" \
     --intent net.dinglisch.android.taskerm.ACTION_TASK \
     --extras "task_name: Morning Report" --target 1 --wait 2 --out "$out" >/dev/null 2>&1; then ok "gen_tsk produced a file"; else bad "gen_tsk run"; fi
if v="$(python3 "$HERE/validate_xml.py" "$out" 877 30 2>&1)"; then ok "XML valid + codes 877,30 present"; else bad "XML validation: $v"; fi
expect_contains "$(cat "$out" 2>/dev/null)" "net.dinglisch.android.taskerm.ACTION_TASK" "intent action in XML"
expect_contains "$(cat "$out" 2>/dev/null)" "task_name: Morning Report" "extra serialised"

echo "== 4. perf-report analyser (offline fixtures) =="
PD="$TMP/perf"; mkdir -p "$PD"; cp "$FIX"/perf/* "$PD"/
prout="$("$ROOT/commands/perf-report.sh" --analyze-only --dir "$PD" 2>&1)"
expect_contains "$prout" "com.example.heavy" "detects CPU hog"
expect_contains "$prout" "HIGH" "flags high severity"
expect_contains "$prout" "47.2" "detects hot thermal zone"
expect_contains "$prout" "91%" "detects /data pressure"
expect_contains "$prout" "ANR" "detects ANRs"

echo "== 5. bloat-audit analyser (offline fixtures) =="
BA="$TMP/bloat"; mkdir -p "$BA"; cp "$FIX"/bloat/* "$BA"/
bout="$("$ROOT/commands/bloat-audit.sh" --analyze-only --json --dir "$BA" 2>/dev/null)"
expect_contains "$bout" "com.facebook.katana" "flags facebook bloat"
expect_contains "$bout" "com.samsung.android.bixby.agent" "flags bixby bloat"
expect_contains "$bout" "com.unused.dinosaur" "flags unused app"
expect_contains "$bout" "300.0" "reads app sizes (300 MB game)"

echo "== 6. adb mdns + address parsers =="
mdnsres="$( ( . "$ROOT/lib/android-ops.sh"; ao_parse_mdns < "$FIX/mdns.txt" ) )"
expect_contains "$mdnsres" "37959 34123" "parses pairing=37959 connect=34123"
splitres="$( ( . "$ROOT/lib/android-ops.sh"; ao_split_addr "172.27.110.73:44569" ) )"
expect_contains "$splitres" "172.27.110.73 44569" "splits IP:port address"
bareport="$( ( . "$ROOT/lib/android-ops.sh"; ao_split_addr "38959" ) )"
expect_contains "$bareport" "- 38959" "bare port has no host (not 38959:38959)"

echo "== 7. pairing flow (fake adb) =="
FAKE="$HERE/fake-adb/adb"; chmod +x "$FAKE"
run_pair() { # run_pair <pairport> <code> <connport> <logfile>
  : > "$4"
  printf '172.27.110.73\n%s\n%s\n%s\n' "$1" "$2" "$3" \
    | AO_ADB="$FAKE" FAKE_ADB_LOG="$4" bash "$ROOT/bootstrap/adb-wireless-setup.sh" >/dev/null 2>&1
}
PLOG="$TMP/pair.log"
run_pair 43867 517162 36895 "$PLOG"
expect_contains "$(cat "$PLOG")" "pair 172.27.110.73:43867 517162" "correct ports -> pairs on IP:pairport"
expect_contains "$(cat "$PLOG")" "connect 172.27.110.73:36895" "correct ports -> connects on IP:connectport"
PLOG2="$TMP/pair-swapped.log"
run_pair 36895 517162 43867 "$PLOG2"
expect_contains "$(cat "$PLOG2")" "pair 172.27.110.73:43867 517162" "swapped ports -> still pairs on the right one"
expect_contains "$(cat "$PLOG2")" "connect 172.27.110.73:36895" "swapped ports -> connects on the right one"
PLOG3="$TMP/pair-bare.log"
: > "$PLOG3"
out3="$(printf '38959\n36895\n123456\n36895\n' | AO_ADB="$FAKE" FAKE_ADB_LOG="$PLOG3" bash "$ROOT/bootstrap/adb-wireless-setup.sh" 2>&1)"
expect_contains "$out3" "looks like a port, not an IP" "bare port in the IP field is rejected"

rm -rf "$TMP"
echo
printf 'tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
