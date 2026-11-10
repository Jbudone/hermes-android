#!/data/data/com.termux/files/usr/bin/bash
# termux-finish-adb.sh — one-shot: install the PC's authorised adb key into
# Termux and connect, with no pairing (adb 35.x can't pair on this device).
#
# Run in Termux:  bash /sdcard/Download/hermes-adb-setup.sh
set -u
export PATH="/data/data/com.termux/files/usr/bin:$PATH"
SRC=/sdcard/Download/.hkey
H="$HOME/hermes-android"

echo "== hermes-android: finish adb setup =="

if [ ! -d /sdcard/Download ]; then
  echo "! storage access needed — accept the Android prompt, then re-run"
  termux-setup-storage
  exit 1
fi
if [ ! -f "$SRC/adbkey" ]; then
  echo "! staged key not found at $SRC"
  echo "  (from the PC: adb push ~/.android/adbkey /sdcard/Download/.hkey/adbkey)"
  exit 1
fi

# --- install the key the phone already trusts (authorised over USB) ---
mkdir -p "$HOME/.android"
cp -f "$SRC/adbkey"     "$HOME/.android/adbkey"
cp -f "$SRC/adbkey.pub" "$HOME/.android/adbkey.pub"
chmod 600 "$HOME/.android/adbkey"
rm -rf "$SRC"
echo "✓ adb key installed into ~/.android (staged copy removed)"

# --- refresh the toolkit so 'phone' exists (best effort) ---
if [ -d "$H/.git" ]; then
  git -C "$H" pull --ff-only >/dev/null 2>&1 && echo "✓ toolkit updated" || echo "! git pull failed (continuing)"
  chmod +x "$H"/bin/* "$H"/commands/*.sh 2>/dev/null || true
fi
export PATH="$H/bin:$PATH"

# --- connect: mDNS discovery (no port typing), then 'phone', then saved ---
connect_mdns() {
  local addr
  addr="$(adb mdns services 2>/dev/null | awk '/_adb-tls-connect\._tcp/{print $NF; exit}')"
  [ -n "$addr" ] || return 1
  adb connect "$addr" >/dev/null 2>&1 || true
  if adb -s "$addr" shell true >/dev/null 2>&1; then printf '%s' "$addr"; return 0; fi
  return 1
}

adb kill-server >/dev/null 2>&1 || true
adb start-server >/dev/null 2>&1 || true

TGT="$(connect_mdns || true)"
if [ -z "$TGT" ] && [ -x "$H/bin/phone" ]; then
  TGT="$("$H/bin/phone" connect 2>/dev/null || true)"
fi

if [ -n "$TGT" ]; then
  echo "✓ connected: $TGT"
  echo "  model: $(adb -s "$TGT" shell getprop ro.product.model | tr -d '\r')"
  echo
  echo "Next:  phone perf     # or: hermes-android doctor"
  exit 0
fi

echo "! could not auto-connect."
echo "  Make sure Developer options → Wireless debugging is ON, note its port, then:"
echo "     adb connect 127.0.0.1:<port>"
echo "     $H/bin/phone connect"
exit 1
