#!/usr/bin/env bash
# doctor — verify the whole stack end to end before anything else runs.
set -o pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname -- "$HERE")"
# shellcheck source=../lib/android-ops.sh
. "$ROOT/lib/android-ops.sh"

fails=0
chk() { # chk <label> <result-string> ; result "ok:..."/"warn:..."/"fail:..."
  local label="$1" r="$2"
  case "$r" in
    ok:*)   printf '  \033[32m✓\033[0m %-26s %s\n' "$label" "${r#ok:}" ;;
    warn:*) printf '  \033[33m!\033[0m %-26s %s\n' "$label" "${r#warn:}"; ;;
    fail:*) printf '  \033[31m✗\033[0m %-26s %s\n' "$label" "${r#fail:}"; fails=$((fails+1)) ;;
  esac
}

echo "Hermes Android toolkit — doctor"
echo

# --- local toolchain ---
if ao_have "$AO_ADB"; then
  chk "adb (local)" "ok:$("$AO_ADB" version | head -1)"
else
  chk "adb (local)" "fail:not found — host: platform-tools; device: pkg install android-tools"
fi

if ao_have python3; then chk "python3" "ok:$(python3 --version 2>&1)"; else chk "python3" "warn:missing (needed for tasker-gen)"; fi

if ao_on_android; then chk "running on" "ok:Android device (Termux)"; else chk "running on" "ok:host PC"; fi

# --- device ---
if tgt="$(ao_target 2>/dev/null)"; then
  chk "adb target" "ok:$tgt"
  st="$(ao_sh_quiet true; echo $?)"
  if [ "$st" = 0 ]; then chk "shell" "ok:reachable"; else chk "shell" "fail:adb shell failed"; fi
  chk "device" "ok:$(ao_model) (Android $(ao_android_ver), SDK $(ao_sdk))"
  if ao_have_root; then chk "root" "ok:su available"; else chk "root" "warn:none (limited but useful; see docs/ROOT.md)"; fi
  # termux-api?
  if ao_on_android; then
    if ao_have termux-battery-status; then chk "termux-api" "ok:installed"; else chk "termux-api" "warn:install Termux:API app + 'pkg install termux-api'"; fi
    if [ -d "$HOME/.termux/tasker" ]; then chk "tasker scripts" "ok:$HOME/.termux/tasker"; else chk "tasker scripts" "warn:mkdir -p ~/.termux/tasker"; fi
    if ao_have am; then chk "am broadcast" "ok:available (Tasker bridge)"; else chk "am broadcast" "warn:missing"; fi
  fi
  # secure settings writable (adb shell holds WRITE_SECURE_SETTINGS)
  if ao_settings put global ao_doctor_probe 1 >/dev/null 2>&1 && \
     [ "$(ao_settings get global ao_doctor_probe 2>/dev/null | tr -d '\r')" = "1" ]; then
    ao_settings delete global ao_doctor_probe >/dev/null 2>&1
    chk "secure settings" "ok:writable through adb"
  else
    chk "secure settings" "warn:not writable"
  fi
else
  chk "adb device" "fail:$(ao_target 2>&1 | sed 's/^error: //')"
fi

echo
if [ "$fails" -eq 0 ]; then ao_ok "doctor: all critical checks passed"; else ao_warn "doctor: $fails critical problem(s)"; fi
exit "$fails"
