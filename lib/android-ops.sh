#!/usr/bin/env bash
# android-ops — shared helpers for the Hermes Android toolkit.
#
# Two run modes, identical public surface:
#   host   : running on a PC that drives the phone over adb (USB or wireless)
#   device : running inside Termux on the phone, driving itself over adb-to-self
#            (adb over wireless-debugging loopback — see docs/PAIRING.md)
#
# In BOTH modes privileged Android operations go through `adb shell`, because a
# plain Termux user is denied most binder services by SELinux. adb shell gives
# the `shell` UID, which is what `pm`, `cmd`, `dumpsys`, `settings` expect.
#
# Public API (used by everything else in this repo):
#   ao_target            resolve+echo the adb serial to use
#   ao_sh  "<cmd>"       run a shell string on the device, echo stdout
#   ao_pm  ...           wrapper for `pm`
#   ao_cmd ...           wrapper for `cmd`
#   ao_dumpsys ...       wrapper for `dumpsys`
#   ao_settings ...      wrapper for `settings`
#   ao_prop <name>       getprop
#   ao_on_android        0 if we are running on the device itself
#   ao_have_root         0 if `su -c id` yields uid=0
#   ao_root "<cmd>"      run on device as root (dies if no root)
#   ao_have <cmd>        command exists locally
#   ao_table_line ...    pretty two/three column output
#
# shellcheck shell=bash

set -o pipefail

# ---------------------------------------------------------------- output utils
ao_die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
ao_info() { printf '\033[36m•\033[0m %s\n' "$*" >&2; }
ao_warn() { printf '\033[33m!\033[0m %s\n' "$*" >&2; }
ao_ok()   { printf '\033[32m✓\033[0m %s\n' "$*" >&2; }
ao_have() { command -v "$1" >/dev/null 2>&1; }

AO_NO_COLOR="${AO_NO_COLOR:-}"
if [ -n "$AO_NO_COLOR" ] || [ ! -t 2 ]; then
  ao_info() { printf '• %s\n' "$*" >&2; }
  ao_warn() { printf '! %s\n' "$*" >&2; }
  ao_ok()   { printf '✓ %s\n' "$*" >&2; }
fi

# ------------------------------------------------------------------- adb core
AO_ADB="${AO_ADB:-adb}"
AO_ADB_TIMEOUT="${AO_ADB_TIMEOUT:-20}"
AO_TARGET="${AO_TARGET:-}"

ao_on_android() { [ "$(uname -o 2>/dev/null)" = "Android" ] || [ -n "${ANDROID_ROOT:-}" ]; }

_ao_adb_raw() { "$AO_ADB" "$@"; }

# Resolve which device to talk to.
# Preference: explicit AO_ADB_SERIAL > a connected localhost (adb-to-self) >
# exactly one connected device > fail with instructions.
_ao_pick_target() {
  if [ -n "${AO_ADB_SERIAL:-}" ]; then printf '%s' "$AO_ADB_SERIAL"; return 0; fi
  ao_have "$AO_ADB" || ao_die "adb not found. host: install android platform-tools. device: 'pkg install android-tools'."
  local devs local_t n
  devs="$(_ao_adb_raw devices 2>/dev/null | awk 'NR>1 && $2=="device"{print $1}')"
  [ -n "$devs" ] || ao_die "no adb device connected. USB: plug in + authorise. Wireless: run bootstrap/adb-wireless-setup.sh. See docs/PAIRING.md"
  local_t="$(printf '%s\n' "$devs" | grep -E '^localhost:' | head -1 || true)"
  [ -n "$local_t" ] && { printf '%s' "$local_t"; return 0; }
  n="$(printf '%s\n' "$devs" | grep -c . )"
  if [ "$n" -gt 1 ]; then
    ao_die "multiple adb devices connected; export AO_ADB_SERIAL=<one of: $(printf '%s ' $devs)>"
  fi
  printf '%s' "$devs"
}

ao_target() {
  if [ -z "$AO_TARGET" ]; then
    AO_TARGET="$(_ao_pick_target)" || return 1
  fi
  [ -n "$AO_TARGET" ] || return 1
  printf '%s' "$AO_TARGET"
}

# ao_sh "<shell string>"  — run on device, print stdout. Non-zero -> propagate.
ao_sh() {
  local t
  t="$(ao_target)" || ao_die "no adb target (see docs/PAIRING.md)"
  _ao_adb_raw -s "$t" shell "$1"
}

# ao_sh_quiet — drop stderr too (for probes we expect to fail).
ao_sh_quiet() { _ao_adb_raw -s "$(ao_target)" shell "$1" 2>/dev/null; }

ao_prop() { ao_sh "getprop $1"; }
ao_sdk()  { ao_prop ro.build.version.sdk; }
ao_model(){ ao_prop ro.product.model; }
ao_android_ver(){ ao_prop ro.build.version.release; }

ao_pm()   { ao_sh "pm $*"; }
ao_cmd()  { ao_sh "cmd $*"; }
ao_settings(){ ao_sh "settings $*"; }
ao_dumpsys(){ ao_sh "dumpsys $*"; }

# ----------------------------------------------------------------------- root
AO_ROOT_STATE="${AO_ROOT_STATE:-}"
ao_have_root() {
  if [ -z "$AO_ROOT_STATE" ]; then
    if ao_sh_quiet 'su -c id' | grep -q 'uid=0'; then AO_ROOT_STATE=yes; else AO_ROOT_STATE=no; fi
  fi
  [ "$AO_ROOT_STATE" = "yes" ]
}
ao_root() { # ao_root "<cmd>"
  if ao_have_root; then ao_sh "su -c '$1'"
  else ao_die "operation needs root (Magisk/KernelSU). Requested: $1"; fi
}

# ------------------------------------------------------------------ formatting
# ao_table_line <key> <value>  — aligned two-column line to stdout
ao_table_line() { printf '  %-28s %s\n' "$1" "$2"; }

ao_human_bytes() { # stdin: integer bytes
  awk 'BEGIN{b='"${1:-0}"'; s="B KiB MiB GiB TiB"; n=split(s,a," "); i=1;
       while(b>=1024 && i<n){b/=1024;i++} printf "%.1f%s", b, a[i]}'
}

# Strip a package:activity or full path to just the bare package name.
ao_pkg_of() { printf '%s' "$1" | sed -E 's#/[^ ]*$##'; }

ao_now_epoch() { date +%s; }
