#!/data/data/com.termux/files/usr/bin/bash
# termux-finish-adb.sh — one-shot: install the PC's authorised adb key into
# Termux and connect, with no pairing (adb 35.x can't pair on this device).
#
# Run in Termux:  bash /sdcard/Download/hermes-adb-setup.sh
set -u
export PATH="$HOME/hermes-android/bin:/data/data/com.termux/files/usr/bin:$PATH"
SRC=/sdcard/Download/.hkey

echo "== hermes-android: finish adb setup =="

# storage access is needed to read /sdcard
if [ ! -d /sdcard/Download ]; then
  echo "! granting storage access (accept the Android prompt, then re-run)"
  termux-setup-storage
  exit 1
fi
if [ ! -f "$SRC/adbkey" ]; then
  echo "! staged key not found at $SRC"
  echo "  (re-run the staging step from the PC: adb push ~/.android/adbkey ...)"
  exit 1
fi

mkdir -p "$HOME/.android"
cp -f "$SRC/adbkey"     "$HOME/.android/adbkey"
cp -f "$SRC/adbkey.pub" "$HOME/.android/adbkey.pub"
chmod 600 "$HOME/.android/adbkey"
rm -rf "$SRC"
echo "✓ installed adb key into ~/.android (staged copy removed)"

adb kill-server >/dev/null 2>&1 || true
adb start-server >/dev/null 2>&1 || true

TGT="$(phone connect 2>/dev/null || true)"
if [ -n "$TGT" ]; then
  echo "✓ connected: $TGT"
  if adb -s "$TGT" shell true >/dev/null 2>&1; then
    echo "✓ adb shell works"
    echo "  model: $(adb -s "$TGT" shell getprop ro.product.model | tr -d '\r')"
    echo
    echo "Next:  phone perf     # or: hermes-android doctor"
    exit 0
  fi
fi

echo "! auto-connect did not come up."
echo "  Open Settings → Developer options → Wireless debugging and read its port, then:"
echo "     adb connect 127.0.0.1:<port>"
echo "     phone connect"
exit 1
