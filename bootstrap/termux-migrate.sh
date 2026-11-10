#!/data/data/com.termux/files/usr/bin/bash
# termux-migrate.sh — one-shot rebuild of the Hermes setup after moving from the
# Google Play Termux to the F-Droid build (Play build cannot use the add-ons:
# RUN_COMMAND is signature-gated).
#
# Run in the fresh Termux:  bash /sdcard/Download/termux-migrate.sh
set -u
export PATH="/data/data/com.termux/files/usr/bin:$PATH"

echo "== termux migration setup =="

if [ ! -d /sdcard/Download ]; then
  echo "! granting storage access — accept the Android prompt, then re-run this script"
  termux-setup-storage
  exit 1
fi

echo "→ installing packages"
pkg update -y >/dev/null 2>&1 || true
pkg install -y git curl python termux-api android-tools openssl >/dev/null 2>&1 || true
pkg upgrade -y android-tools >/dev/null 2>&1 || true

echo "→ fetching the toolkit"
H="$HOME/hermes-android"
if [ -d "$H/.git" ]; then
  git -C "$H" pull --ff-only >/dev/null 2>&1 && echo "  updated" || echo "  (pull failed; keeping current)"
else
  git clone --depth 1 https://github.com/Jbudone/hermes-android "$H" || { echo "! clone failed"; exit 1; }
  echo "  cloned"
fi
chmod +x "$H"/bin/* "$H"/commands/*.sh "$H"/bootstrap/*.sh 2>/dev/null || true

echo "→ installing the authorised adb key"
SRC=/sdcard/Download/.hkey
if [ -f "$SRC/adbkey" ]; then
  mkdir -p "$HOME/.android"
  cp -f "$SRC/adbkey"     "$HOME/.android/adbkey"
  cp -f "$SRC/adbkey.pub" "$HOME/.android/adbkey.pub"
  chmod 600 "$HOME/.android/adbkey"
  rm -rf "$SRC"
  echo "  ✓ key installed (staged copy removed)"
else
  echo "  ! no staged key at $SRC (re-copy it from the PC if adb connect fails)"
fi

grep -q 'hermes-android/bin' "$HOME/.bashrc" 2>/dev/null || \
  printf '\nexport PATH="$HOME/hermes-android/bin:$PATH"\n' >> "$HOME/.bashrc"
ln -sf "$H/bin/hermes-android" "$PREFIX/bin/hermes-android" 2>/dev/null || true
ln -sf "$H/bin/phone"          "$PREFIX/bin/phone"          2>/dev/null || true
export PATH="$H/bin:$PATH"

echo "→ connecting to this device over adb"
adb kill-server >/dev/null 2>&1 || true
adb start-server >/dev/null 2>&1 || true
TGT="$(phone connect 2>/dev/null || true)"
if [ -n "$TGT" ]; then
  echo "  ✓ connected: $TGT"
  echo "  model: $(adb -s "$TGT" shell getprop ro.product.model | tr -d '\r')"
else
  echo "  ! auto-connect failed — enable Wireless debugging, then:"
  echo "      adb connect 127.0.0.1:<port>   &&   phone"
fi

cat <<'NEXT'

Next: install Hermes itself (if not already):
  bash ~/hermes-android/bootstrap/termux-bootstrap.sh
Then:
  hermes setup
  phone perf
NEXT
