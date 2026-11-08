#!/usr/bin/env bash
# adb-wireless-setup.sh — connect adb to an Android device over Wireless
# Debugging, so the toolkit can drive it. Works two ways:
#
#   • on the PHONE (Termux): talks to itself over 127.0.0.1 (adb-to-self)
#   • on a PC:               talks to the phone over your LAN IP
#
#   bash adb-wireless-setup.sh                 # interactive pair + connect
#   bash adb-wireless-setup.sh --host 192.168.1.42
#   bash adb-wireless-setup.sh --reconnect     # reuse saved ports
#   bash adb-wireless-setup.sh --persist       # also relax phantom-proc killing
#
# You need the phone's Wireless Debugging screen open (Settings → Developer
# options → Wireless debugging). It shows a "pairing code" dialog and a
# "IP address & Port" line — the two ports are DIFFERENT.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/android-ops.sh"

HOST=""; RECONNECT=0; PERSIST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift ;;
    --reconnect) RECONNECT=1 ;;
    --persist) PERSIST=1 ;;
    -h|--help) sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) ao_die "unknown arg: $1" ;;
  esac; shift
done

ao_on_android && [ -z "$HOST" ] && HOST="127.0.0.1"
ao_have "$AO_ADB" || ao_die "adb not found (host: platform-tools; device: pkg install android-tools)"

STATE="${TMPDIR:-/tmp}/ao-run"; mkdir -p "$STATE"; ENVF="$STATE/ports.env"

if [ "$RECONNECT" = 1 ]; then
  # shellcheck disable=SC1090
  [ -f "$ENVF" ] && . "$ENVF"
  [ -n "${AO_HOST:-}" ] && HOST="$AO_HOST"
  [ -n "${AO_CONNECT_PORT:-}" ] || ao_die "no saved connect port; run the pairing flow first"
  ao_adb connect "$HOST:$AO_CONNECT_PORT" && ao_ok "connected to $HOST:$AO_CONNECT_PORT"
  AO_ADB_SERIAL="$HOST:$AO_CONNECT_PORT" "$AO_ADB" -s "$HOST:$AO_CONNECT_PORT" shell true >/dev/null 2>&1 \
    && ao_ok "adb shell works" || ao_warn "connected but shell failed"
  exit 0
fi

[ -n "$HOST" ] || HOST="127.0.0.1"
ao_info "adb-to-$HOST over Wireless Debugging"
echo
echo "On the phone: Settings → Developer options → Wireless debugging."
echo "  • 'Pair device with pairing code' shows a PORT + a 6-digit CODE  (pairing)"
echo "  • the main screen shows 'IP address & Port' with the CONNECT port"
echo

read -r -p "Pairing port (from the pairing dialog): " PAIR_PORT
read -r -p "Pairing code (6 digits): " PAIR_CODE
read -r -p "Connect port (from 'IP address & Port'): " CONNECT_PORT

ao_info "pairing $HOST:$PAIR_PORT"
"$AO_ADB" pair "$HOST:$PAIR_PORT" "$PAIR_CODE" || ao_warn "pair failed (already paired? wrong code/port?)"
ao_info "connecting $HOST:$CONNECT_PORT"
"$AO_ADB" connect "$HOST:$CONNECT_PORT" || ao_warn "connect failed"

printf 'AO_HOST=%s\nAO_CONNECT_PORT=%s\n' "$HOST" "$CONNECT_PORT" > "$ENVF"
# convenience re-connect helper
cat > "$STATE/adb-connect.sh" <<EOF
#!/usr/bin/env bash
exec "$HERE/adb-wireless-setup.sh" --reconnect
EOF
chmod +x "$STATE/adb-connect.sh"

if "$AO_ADB" -s "$HOST:$CONNECT_PORT" shell true >/dev/null 2>&1; then
  ao_ok "adb shell works over $HOST:$CONNECT_PORT"
  ao_info "the toolkit auto-detects a localhost target; from a PC export AO_ADB_SERIAL=$HOST:$CONNECT_PORT"
else
  ao_warn "connected but shell failed — reopen Wireless Debugging (the port changes) and re-run"
fi

if [ "$PERSIST" = 1 ]; then
  ao_info "relaxing phantom-process killing (keeps Termux/Heroku alive; slight battery cost)"
  "$AO_ADB" -s "$HOST:$CONNECT_PORT" shell "settings put global settings_enable_monitor_phantom_procs false" \
    && ao_ok "phantom-process monitor disabled" || ao_warn "could not change phantom-process setting"
fi
