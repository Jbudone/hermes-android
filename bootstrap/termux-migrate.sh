#!/data/data/com.termux/files/usr/bin/bash
# termux-migrate.sh — rebuild the Hermes setup after switching to F-Droid Termux.
# v2: noninteractive (stdin </dev/null, --force-confnew) AND verbose, so it can
# never hang silently on an apt/dpkg prompt again.
#
# Run in Termux:  bash /sdcard/Download/termux-migrate.sh
set -u
export PATH="/data/data/com.termux/files/usr/bin:$PATH"
export DEBIAN_FRONTEND=noninteractive
APT="pkg -y -o Dpkg::Options::=--force-confnew"

log(){ printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

log "checking storage access"
if [ ! -d /sdcard/Download ]; then
  echo "! storage access required — accept the prompt, then re-run"
  termux-setup-storage
  exit 1
fi

log "apt update"
$APT update </dev/null || echo "  (update returned non-zero; continuing)"

log "installing packages (git curl python termux-api android-tools openssl)"
$APT install git curl python termux-api android-tools openssl </dev/null \
  || echo "  (install returned non-zero; continuing — read the output above)"

log "fetching the toolkit"
H="$HOME/hermes-android"
if [ -d "$H/.git" ]; then
  git -C "$H" pull --ff-only >/dev/null 2>&1 && echo "  updated" || echo "  (pull failed; keeping current)"
else
  git clone --depth 1 https://github.com/Jbudone/hermes-android "$H" || { echo "! clone failed"; exit 1; }
  echo "  cloned"
fi
chmod +x "$H"/bin/* "$H"/commands/*.sh "$H"/bootstrap/*.sh 2>/dev/null || true

log "installing the authorised adb key"
SRC=/sdcard/Download/.hkey
if [ -f "$SRC/adbkey" ]; then
  mkdir -p "$HOME/.android"
  cp -f "$SRC/adbkey"     "$HOME/.android/adbkey"
  cp -f "$SRC/adbkey.pub" "$HOME/.android/adbkey.pub"
  chmod 600 "$HOME/.android/adbkey"
  rm -rf "$SRC"
  echo "  ✓ key installed (staged copy removed)"
else
  echo "  ! no staged key at $SRC (re-copy from the PC if adb connect fails)"
fi

grep -q 'hermes-android/bin' "$HOME/.bashrc" 2>/dev/null || \
  printf '\nexport PATH="$HOME/hermes-android/bin:$PATH"\n' >> "$HOME/.bashrc"
ln -sf "$H/bin/hermes-android" "$PREFIX/bin/hermes-android" 2>/dev/null || true
ln -sf "$H/bin/phone"          "$PREFIX/bin/phone"          2>/dev/null || true
export PATH="$H/bin:$PATH"

log "connecting over adb"
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
