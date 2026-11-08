#!/usr/bin/env bash
# adb-wireless-setup.sh — connect adb to an Android device over Wireless
# Debugging, so the toolkit can drive it. Works two ways:
#
#   • on the PHONE (Termux): the phone connects to itself over the IP its
#     Wireless-debugging screen shows — NOT 127.0.0.1, because the pairing
#     server binds to that interface, not loopback
#   • on a PC:                the same flow, using the phone's LAN address
#
#   bash adb-wireless-setup.sh                 # interactive pair + connect
#   bash adb-wireless-setup.sh --reconnect     # reuse saved host/port
#   bash adb-wireless-setup.sh --persist       # also relax phantom-proc killing
#
# You paste TWO full "IP:port" addresses plus the 6-digit code. Because you
# paste whole addresses, swapping them cannot break anything — the script tries
# both orders and corrects itself.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/android-ops.sh
. "$HERE/../lib/android-ops.sh"

usage() { sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'; }

RECONNECT=0; PERSIST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --host) shift ;;            # accepted for compatibility; addresses are pasted now
    --reconnect) RECONNECT=1 ;;
    --persist) PERSIST=1 ;;
    -h|--help) usage; exit 0 ;;
    *) ao_die "unknown arg: $1" ;;
  esac; shift
done

ao_have "$AO_ADB" || ao_die "adb not found (host: platform-tools; device: pkg install android-tools)"
"$AO_ADB" start-server >/dev/null 2>&1 || true

STATE="${TMPDIR:-/tmp}/ao-run"; mkdir -p "$STATE"; ENVF="$STATE/ports.env"

# "host:port" -> "<host> <port>"  (tolerates spaces, quotes, stray labels)
# provided by lib/android-ops.sh as ao_split_addr

verify() { "$AO_ADB" -s "$1:$2" shell true >/dev/null 2>&1; }

# ---------------------------------------------------------------- reconnect ---
if [ "$RECONNECT" = 1 ]; then
  # shellcheck disable=SC1090
  [ -f "$ENVF" ] && . "$ENVF"
  if [ -n "${AO_HOST:-}" ] && [ -n "${AO_CONNECT_PORT:-}" ]; then
    "$AO_ADB" connect "$AO_HOST:$AO_CONNECT_PORT" >/dev/null 2>&1 || true
    if verify "$AO_HOST" "$AO_CONNECT_PORT"; then
      ao_ok "adb shell works over $AO_HOST:$AO_CONNECT_PORT"; exit 0
    fi
    ao_info "saved port not reachable; checking mDNS for the rotated port"
    read -r _ph mc <<<"$("$AO_ADB" mdns services 2>/dev/null | ao_parse_mdns)"
    if [ "$mc" != "-" ]; then
      "$AO_ADB" connect "$AO_HOST:$mc" >/dev/null 2>&1 || true
      if verify "$AO_HOST" "$mc"; then
        printf 'AO_HOST=%s\nAO_CONNECT_PORT=%s\n' "$AO_HOST" "$mc" > "$ENVF"
        ao_ok "adb shell works over $AO_HOST:$mc"; exit 0
      fi
    fi
  fi
  ao_warn "could not reconnect — toggle Wireless debugging off/on, then re-run without --reconnect"
  exit 1
fi

# ------------------------------------------------------------------- pair -----
ao_info "Android wireless-debugging pairing"
echo
echo "Open Settings → Developer options → Wireless debugging. It shows ONE IP and"
echo "TWO DIFFERENT ports:"
echo "  • the IP (same on both screens), e.g. 172.27.110.73"
echo "  • 'Pair device with pairing code'  → its own PORT + a 6-digit code"
echo "  • the main screen 'IP address & Port' → the CONNECT port"
echo

read -r -p "Device IP (e.g. 172.27.110.73): " DEV_RAW
DEV_RAW="$(printf '%s' "$DEV_RAW" | tr -cd '0-9.:')"
read -r DEV_IP _junk <<<"$(ao_split_addr "$DEV_RAW")"
if [ "$DEV_IP" = "-" ]; then
  case "$DEV_RAW" in
    *.*) DEV_IP="$DEV_RAW" ;;                       # bare IP, no port
    *) ao_die "that looks like a port, not an IP — enter the IP shown (e.g. 172.27.110.73)" ;;
  esac
fi
[ -n "$DEV_IP" ] || ao_die "need the device IP"

read -r -p "Pairing port (from 'Pair with device' dialog): " P_RAW
read -r -p "Pairing code (6 digits): " CODE
read -r -p "Connect port (from the main screen): " C_RAW

P_RAW="$(printf '%s' "$P_RAW" | tr -cd '0-9.:')"
C_RAW="$(printf '%s' "$C_RAW" | tr -cd '0-9.:')"
read -r PH PP <<<"$(ao_split_addr "$P_RAW")"; [ "$PH" = "-" ] && PH="$DEV_IP"
read -r CH CP <<<"$(ao_split_addr "$C_RAW")"; [ "$CH" = "-" ] && CH="$DEV_IP"

[ -n "$CODE" ] || ao_die "no pairing code given"
{ [ -n "$PP" ] && [ "$PP" != "-" ]; } || ao_die "no pairing port given"
{ [ -n "$CP" ] && [ "$CP" != "-" ]; } || ao_die "no connect port given"
case "$PP$CP" in *[!0-9]*) ao_die "ports must be numeric (got '$PP' / '$CP')" ;; esac
[ "$PP" = "$CP" ] && ao_die "pairing and connect ports are identical ($PP) — they must differ"

pr_out=""
attempt_pair() { # attempt_pair <host> <port>
  ao_info "pairing $1:$2"
  pr_out="$("$AO_ADB" pair "$1:$2" "$CODE" 2>&1)"
  printf '%s\n' "$pr_out" | sed 's/^/    /'
  printf '%s' "$pr_out" | grep -qi 'Successfully paired'
}

PAIR_H=""; PAIR_P=""; CONN_H=""; CONN_P=""
if attempt_pair "$PH" "$PP"; then
  ao_ok "paired"; PAIR_H="$PH"; PAIR_P="$PP"; CONN_H="$CH"; CONN_P="$CP"
elif attempt_pair "$CH" "$CP"; then
  ao_warn "addresses were swapped — corrected"; PAIR_H="$CH"; PAIR_P="$CP"; CONN_H="$PH"; CONN_P="$PP"
else
  ao_warn "pairing failed on both addresses"
  case "$pr_out" in
    *"already paired"*) ao_info "'already paired' — continuing to connect"; CONN_H="$CH"; CONN_P="$CP" ;;
    *)
      echo
      echo "Do it by hand and paste the output:"
      echo "  adb pair $PH:$PP $CODE"
      echo "  adb connect $CH:$CP"
      exit 1 ;;
  esac
fi

sleep 1
"$AO_ADB" connect "$CONN_H:$CONN_P" >/dev/null 2>&1 || true

if ! verify "$CONN_H" "$CONN_P" && [ -n "$PAIR_H" ]; then
  ao_warn "shell not up on $CONN_H:$CONN_P — trying $PAIR_H:$PAIR_P"
  verify "$PAIR_H" "$PAIR_P" && { CONN_H="$PAIR_H"; CONN_P="$PAIR_P"; }
fi

if verify "$CONN_H" "$CONN_P"; then
  printf 'AO_HOST=%s\nAO_CONNECT_PORT=%s\n' "$CONN_H" "$CONN_P" > "$ENVF"
  cat > "$STATE/adb-connect.sh" <<EOF
#!/usr/bin/env bash
exec "$HERE/adb-wireless-setup.sh" --reconnect
EOF
  chmod +x "$STATE/adb-connect.sh"
  ao_ok "adb shell works over $CONN_H:$CONN_P"
  ao_info "toolkit auto-detects this target; from a PC: export AO_ADB_SERIAL=$CONN_H:$CONN_P"
  ao_info "reconnect later: bash $HERE/adb-wireless-setup.sh --reconnect"
else
  ao_warn "paired but shell still failed. Toggle Wireless debugging off/on and re-run."
  ao_warn "Keep the phone's screen ON and unlocked during pairing."
  exit 1
fi

if [ "$PERSIST" = 1 ]; then
  ao_info "relaxing phantom-process killing (keeps Termux alive; slight battery cost)"
  "$AO_ADB" -s "$CONN_H:$CONN_P" shell "settings put global settings_enable_monitor_phantom_procs false" \
    && ao_ok "phantom-process monitor disabled" || ao_warn "could not change phantom-process setting"
fi
