#!/usr/bin/env bash
# adb-wireless-setup.sh — connect adb to an Android device over Wireless
# Debugging, so the toolkit can drive it. Works two ways:
#
#   • on the PHONE (Termux): talks to itself over 127.0.0.1 (adb-to-self)
#   • on a PC:               talks to the phone over your LAN IP
#
#   bash adb-wireless-setup.sh                 # auto-detect ports, then pair
#   bash adb-wireless-setup.sh --host 192.168.1.42
#   bash adb-wireless-setup.sh --reconnect     # reuse saved ports
#   bash adb-wireless-setup.sh --persist       # also relax phantom-proc killing
#
# The wireless-debugging screen shows TWO DIFFERENT PORTS: the pairing dialog's
# port (with the 6-digit code) and the main "IP address & Port" line. Mixing
# them up is the classic failure. This script reads both from `adb mdns
# services` when it can, so you usually only have to type the code.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/android-ops.sh
. "$HERE/../lib/android-ops.sh"

HOST=""; RECONNECT=0; PERSIST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift ;;
    --reconnect) RECONNECT=1 ;;
    --persist) PERSIST=1 ;;
    -h|--help) sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) ao_die "unknown arg: $1" ;;
  esac; shift
done

ao_on_android && [ -z "$HOST" ] && HOST="127.0.0.1"
ao_have "$AO_ADB" || ao_die "adb not found (host: platform-tools; device: pkg install android-tools)"
"$AO_ADB" start-server >/dev/null 2>&1 || true

STATE="${TMPDIR:-/tmp}/ao-run"; mkdir -p "$STATE"; ENVF="$STATE/ports.env"

if [ "$RECONNECT" = 1 ]; then
  # shellcheck disable=SC1090
  [ -f "$ENVF" ] && . "$ENVF"
  [ -n "${AO_HOST:-}" ] && HOST="$AO_HOST"
  if [ -n "${AO_CONNECT_PORT:-}" ]; then
    ao_adb connect "$HOST:$AO_CONNECT_PORT" >/dev/null 2>&1 || true
  fi
  # Also try whatever mdns currently advertises (the port rotates).
  read -r _m_p m_c <<<"$("$AO_ADB" mdns services 2>/dev/null | ao_parse_mdns)"
  if [ "$m_c" != "-" ] && [ "$m_c" != "${AO_CONNECT_PORT:-}" ]; then
    ao_info "mdns advertises connect port $m_c (was ${AO_CONNECT_PORT:-none}); trying it"
    "$AO_ADB" connect "$HOST:$m_c" >/dev/null 2>&1 || true
    AO_CONNECT_PORT="$m_c"
  fi
  [ -n "${AO_CONNECT_PORT:-}" ] || ao_die "no connect port; run the pairing flow first"
  if "$AO_ADB" -s "$HOST:$AO_CONNECT_PORT" shell true >/dev/null 2>&1; then
    ao_ok "adb shell works over $HOST:$AO_CONNECT_PORT"
    printf 'AO_HOST=%s\nAO_CONNECT_PORT=%s\n' "$HOST" "$AO_CONNECT_PORT" > "$ENVF"
  else
    ao_warn "still not reachable — toggle Wireless debugging off/on, then re-run"
  fi
  exit 0
fi

[ -n "$HOST" ] || HOST="127.0.0.1"

# --- auto-detect ports -------------------------------------------------------
DET_PAIR=""; DET_CONNECT=""
if ao_have "$AO_ADB"; then
  read -r dp dc <<<"$("$AO_ADB" mdns services 2>/dev/null | ao_parse_mdns)"
  [ "${dp:-"-"}" != "-" ] && DET_PAIR="$dp"
  [ "${dc:-"-"}" != "-" ] && DET_CONNECT="$dc"
fi

prompt() { # prompt <label> <default>
  local label="$1" def="${2:-}" v=""
  if [ -n "$def" ]; then read -r -p "$label [$def]: " v; else read -r -p "$label: " v; fi
  [ -z "$v" ] && v="$def"
  printf '%s' "$v"
}

ao_info "adb-to-$HOST over Wireless Debugging"
echo
if [ -n "$DET_PAIR$DET_CONNECT" ]; then
  ao_ok "detected via mDNS — pairing port ${DET_PAIR:-?}, connect port ${DET_CONNECT:-?}"
else
  echo "Open Settings → Developer options → Wireless debugging, then:"
  echo "  • 'Pair device with pairing code' shows its own PORT + a 6-digit CODE"
  echo "  • the main screen shows 'IP address & Port' with the CONNECT port"
fi
echo

PAIR_PORT="$(prompt 'Pairing port' "$DET_PAIR")"
PAIR_CODE="$(prompt 'Pairing code (6 digits)' '')"
CONNECT_PORT="$(prompt "Connect port (from 'IP address & Port')" "$DET_CONNECT")"

[ -n "$PAIR_CODE" ] || ao_die "no pairing code given (open 'Pair device with pairing code' first)"
[ -n "$PAIR_PORT" ] || ao_die "no pairing port given"
[ -n "$CONNECT_PORT" ] || ao_die "no connect port given"
if [ "$PAIR_PORT" = "$CONNECT_PORT" ]; then
  ao_die "pairing and connect ports are the SAME ($PAIR_PORT) — they must differ. Re-check the two screens."
fi

pairstr=""
try_pair() { # try_pair <port> ; sets pairstr
  pairstr="$("$AO_ADB" pair "$HOST:$1" "$PAIR_CODE" 2>&1)"
  printf '%s' "$pairstr" | grep -qi 'Successfully paired'
}

ao_info "pairing $HOST:$PAIR_PORT"
if try_pair "$PAIR_PORT"; then
  ao_ok "paired"
elif try_pair "$CONNECT_PORT"; then
  ao_warn "ports were swapped — corrected (pairing=$CONNECT_PORT, connect=$PAIR_PORT)"
  t="$PAIR_PORT"; PAIR_PORT="$CONNECT_PORT"; CONNECT_PORT="$t"
else
  ao_warn "pair failed: $pairstr"
  ao_warn "usual causes: code expired (reopen the dialog), or wrong pairing port"
fi

sleep 1
ao_info "connecting $HOST:$CONNECT_PORT"
"$AO_ADB" connect "$HOST:$CONNECT_PORT" >/dev/null 2>&1 || true

# verify, with one swap-retry
verify() { "$AO_ADB" -s "$HOST:$1" shell true >/dev/null 2>&1; }
if ! verify "$CONNECT_PORT"; then
  ao_warn "shell not up on $CONNECT_PORT — trying the other port"
  if verify "$PAIR_PORT"; then
    ao_warn "using $PAIR_PORT as the connect port"
    CONNECT_PORT="$PAIR_PORT"
  fi
fi

printf 'AO_HOST=%s\nAO_CONNECT_PORT=%s\n' "$HOST" "$CONNECT_PORT" > "$ENVF"
cat > "$STATE/adb-connect.sh" <<EOF
#!/usr/bin/env bash
exec "$HERE/adb-wireless-setup.sh" --reconnect
EOF
chmod +x "$STATE/adb-connect.sh"

if verify "$CONNECT_PORT"; then
  ao_ok "adb shell works over $HOST:$CONNECT_PORT"
  ao_info "toolkit auto-detects a localhost target; from a PC export AO_ADB_SERIAL=$HOST:$CONNECT_PORT"
  ao_info "reconnect later with: bash $HERE/adb-wireless-setup.sh --reconnect"
else
  ao_warn "connected but shell failed — toggle Wireless debugging off/on (the port rotates) and re-run"
fi

if [ "$PERSIST" = 1 ]; then
  ao_info "relaxing phantom-process killing (keeps Termux alive; slight battery cost)"
  "$AO_ADB" -s "$HOST:$CONNECT_PORT" shell "settings put global settings_enable_monitor_phantom_procs false" \
    && ao_ok "phantom-process monitor disabled" || ao_warn "could not change phantom-process setting"
fi
