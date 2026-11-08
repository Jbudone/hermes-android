#!/data/data/com.termux/files/usr/bin/bash
# termux-bootstrap.sh — one-shot setup of Hermes + this toolkit inside Termux.
#
# Run it IN Termux on the phone:
#   bash termux-bootstrap.sh                 # clone the toolkit from GitHub
#   bash termux-bootstrap.sh --from /sdcard/hermes-android   # copy a local dir
#   bash termux-bootstrap.sh --repo <git-url>
#   bash termux-bootstrap.sh --stable        # use the stable APT channel instead
#
# It is idempotent and does NOT abort on a single failed step: it always gets
# the toolkit + Tasker scripts in place, then reports the Hermes install status.
#
# Hermes itself: the official `stable` APT channel is currently broken upstream
# (its index 404s). This script therefore installs from the `canary` channel
# (live, prebuilt, same signing key) and falls back to a from-source build.
set -uo pipefail

REPO_URL="${HERMES_ANDROID_REPO:-https://github.com/Jbudone/hermes-android}"
CANARY="https://hermes-assets.nousresearch.com/releases/termux/canary"
SUITE="hermes-canary"
KEY_FP="C572 B5FD D1A2 9CCF A9A9 12B6 840B 0848 E139 156D"
FROM=""; REPO="$REPO_URL"
while [ $# -gt 0 ]; do
  case "$1" in
    --from) FROM="$2"; shift ;;
    --repo) REPO="$2"; shift ;;
    --stable) CANARY="https://hermes-assets.nousresearch.com/releases/termux/stable"; SUITE="hermes-stable" ;;
    -h|--help) sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac; shift
done

say(){ printf '\033[36m==>\033[0m %s\n' "$*"; }
ok(){ printf '\033[32m  ✓\033[0m %s\n' "$*"; }
warn(){ printf '\033[33m  !\033[0m %s\n' "$*"; }
have(){ command -v "$1" >/dev/null 2>&1; }

# --- 0. sanity ---
if [ ! -d /data/data/com.termux/files/usr ]; then
  echo "This must run inside Termux (standard prefix not found)." >&2; exit 1
fi
export PATH="/data/data/com.termux/files/usr/bin:$PATH"
export ANDROID_API_LEVEL="$(getprop ro.build.version.sdk 2>/dev/null || echo 34)"
export CARGO_BUILD_TARGET="aarch64-linux-android"

# --- 1. base packages ---
say "Installing base packages (git curl gnupg python termux-api android-tools)"
pkg update -y >/dev/null 2>&1 || true
pkg install -y git curl gnupg python termux-api android-tools openssl >/dev/null 2>&1 \
  || pkg install -y git curl gnupg python android-tools openssl >/dev/null 2>&1 || true
ok "packages requested"

# --- 2. Hermes ---
install_hermes_apt() {
  say "Installing Hermes from the $SUITE APT channel (prebuilt)"
  mkdir -p "$PREFIX/etc/apt/keyrings"
  curl -fsSL "$CANARY/key.asc" -o "$PREFIX/etc/apt/keyrings/hermes-agent.asc" || return 1
  local fp fp_norm key_norm
  fp="$(gpg --show-keys --with-fingerprint "$PREFIX/etc/apt/keyrings/hermes-agent.asc" 2>/dev/null | sed -n '2p')"
  fp_norm="$(printf '%s' "$fp" | tr -d ' ')"
  key_norm="$(printf '%s' "$KEY_FP" | tr -d ' ')"
  case "$fp_norm" in
    *"$key_norm"*) ok "repo key fingerprint verified" ;;
    *) warn "unexpected key fingerprint: $fp (continuing, verify before trusting)" ;;
  esac
  printf '%s\n' "deb [signed-by=$PREFIX/etc/apt/keyrings/hermes-agent.asc] $CANARY $SUITE main" \
    > "$PREFIX/etc/apt/sources.list.d/hermes-agent.list"
  pkg update -y >/dev/null 2>&1
  pkg install -y hermes-agent || return 1
  have hermes
}
install_hermes_source() {
  say "Falling back to a from-source build (compiles on-device; 10-20 min, phone gets warm)"
  pkg install -y git python clang rust make pkg-config libffi openssl ca-certificates binutils >/dev/null 2>&1 || true
  local d="$HOME/hermes-agent"
  [ -d "$d/.git" ] || git clone --depth 1 https://github.com/NousResearch/hermes-agent "$d" || return 1
  ( cd "$d" || return 1
    python -m venv venv --system-site-packages
    # shellcheck disable=SC1091
    . venv/bin/activate || return 1
    python -m pip install --upgrade pip setuptools wheel || true
    if [ -f scripts/install_psutil_android.py ]; then python scripts/install_psutil_android.py || true; fi
    python -m pip install -e '.[termux]' -c constraints-termux.txt || return 1
  ) || return 1
  ln -sf "$d/venv/bin/hermes" "$PREFIX/bin/hermes" 2>/dev/null || true
  have hermes
}

if have hermes; then
  ok "hermes already installed: $(hermes --version 2>/dev/null | head -1)"
elif install_hermes_apt; then ok "hermes installed (APT $SUITE)"
elif install_hermes_source; then ok "hermes installed (from source)"
else warn "Hermes could not be installed automatically — see docs/PAIRING.md; the toolkit below is still set up"; fi

# --- 3. this toolkit ---
say "Installing hermes-android toolkit"
DEST="$HOME/hermes-android"
if [ -n "$FROM" ]; then
  rm -rf "$DEST"; mkdir -p "$DEST"; cp -a "$FROM"/. "$DEST"/
elif [ -d "$DEST/.git" ]; then
  git -C "$DEST" pull --ff-only >/dev/null 2>&1 && ok "updated $DEST" || warn "git pull failed; keeping current"
else
  git clone --depth 1 "$REPO" "$DEST" 2>/dev/null && ok "cloned toolkit" || warn "clone failed ($REPO) — re-run with --from <dir> or --repo <url>"
fi
if [ -d "$DEST" ]; then
  chmod +x "$DEST"/bin/hermes-android "$DEST"/commands/*.sh "$DEST"/tasker/gen_tsk.py 2>/dev/null || true
  ln -sf "$DEST/bin/hermes-android" "$PREFIX/bin/hermes-android" 2>/dev/null || true
  ok "toolkit at $DEST (command: hermes-android)"
fi

# --- 4. Termux:Tasker scripts ---
say "Installing Termux:Tasker scripts into ~/.termux/tasker"
mkdir -p "$HOME/.termux/tasker"; chmod 700 "$HOME/.termux"
cp -f "$DEST"/tasker/termux-scripts/*.sh "$HOME/.termux/tasker/" 2>/dev/null || true
chmod 700 "$HOME"/.termux/tasker/*.sh 2>/dev/null || true
ok "scripts ready"

# --- 5. PATH persistence ---
if [ -f "$HOME/.bashrc" ] && ! grep -q 'hermes-android/bin' "$HOME/.bashrc" 2>/dev/null; then
  printf '\nexport PATH="$HOME/hermes-android/bin:$PATH"\n' >> "$HOME/.bashrc"
  ok "added toolkit to ~/.bashrc PATH"
fi

# --- 6. next steps ---
cat <<NEXT

$(printf '\033[1mNext steps\033[0m')
  1. Configure a model/provider:      hermes setup
  2. Give Hermes shell powers (non-root, wireless adb):
                                      bash $DEST/bootstrap/adb-wireless-setup.sh
  3. Self-check:                      hermes-android doctor
  4. Try it:                          hermes-android perf

Tasker (once): install the Termux:Tasker plugin, grant Tasker the
"Run commands in Termux environment" permission, and enable
Preferences → Misc → Allow External Access. Then Hermes can both run your
Tasker tasks (hermes-android tasker-run "Name") and be run BY Tasker.
NEXT
