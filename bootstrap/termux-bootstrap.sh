#!/data/data/com.termux/files/usr/bin/bash
# termux-bootstrap.sh — one-shot setup of Hermes + this toolkit inside Termux.
#
# Run it IN Termux on the phone:
#   bash termux-bootstrap.sh                 # clone the toolkit from GitHub
#   bash termux-bootstrap.sh --from /sdcard/hermes-android   # copy a local dir
#   bash termux-bootstrap.sh --repo <git-url>
#
# It is idempotent: safe to re-run.
set -euo pipefail

REPO_URL="${HERMES_ANDROID_REPO:-https://github.com/Jbudone/hermes-android}"
FROM=""; REPO="$REPO_URL"
while [ $# -gt 0 ]; do
  case "$1" in
    --from) FROM="$2"; shift ;;
    --repo) REPO="$2"; shift ;;
    -h|--help) sed -n '3,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac; shift
done

say(){ printf '\033[36m==>\033[0m %s\n' "$*"; }
ok(){ printf '\033[32m  ✓\033[0m %s\n' "$*"; }
warn(){ printf '\033[33m  !\033[0m %s\n' "$*"; }

# --- 0. sanity ---
if [ ! -d /data/data/com.termux/files/usr ]; then
  echo "This must run inside Termux (standard prefix not found)." >&2; exit 1
fi
export PATH="/data/data/com.termux/files/usr/bin:$PATH"
export ANDROID_API_LEVEL="$(getprop ro.build.version.sdk 2>/dev/null || echo 34)"

# --- 1. base packages ---
say "Installing base packages (git curl gnupg python termux-api android-tools)"
pkg update -y >/dev/null 2>&1 || true
pkg install -y git curl gnupg python termux-api android-tools openssl >/dev/null 2>&1 || \
  pkg install -y git curl gnupg python android-tools openssl >/dev/null 2>&1 || true
ok "packages ready"

# --- 2. Hermes itself (APT package is currently broken upstream; use the
#        supported from-source installer which handles Termux automatically) ---
if command -v hermes >/dev/null 2>&1; then
  ok "hermes already installed: $(hermes --version 2>/dev/null | head -1)"
else
  say "Installing Hermes (from-source path; a few minutes, phone will get warm)"
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
  command -v hermes >/dev/null 2>&1 && ok "hermes installed" || warn "hermes install finished with warnings — run 'hermes doctor'"
fi

# --- 3. this toolkit ---
say "Installing hermes-android toolkit"
DEST="$HOME/hermes-android"
if [ -n "$FROM" ]; then
  rm -rf "$DEST"; mkdir -p "$DEST"; cp -a "$FROM"/. "$DEST"/
elif [ -d "$DEST/.git" ]; then
  git -C "$DEST" pull --ff-only >/dev/null 2>&1 && ok "updated $DEST" || warn "git pull failed; keeping current"
else
  git clone --depth 1 "$REPO" "$DEST" 2>/dev/null || { warn "clone failed ($REPO)"; warn "Re-run with: --from <dir> or --repo <url>"; exit 1; }
fi
chmod +x "$DEST"/bin/hermes-android "$DEST"/commands/*.sh "$DEST"/tasker/gen_tsk.py 2>/dev/null || true
ln -sf "$DEST/bin/hermes-android" "$PREFIX/bin/hermes-android" 2>/dev/null || true
ok "toolkit at $DEST (command: hermes-android)"

# --- 4. Termux:Tasker scripts ---
say "Installing Termux:Tasker scripts into ~/.termux/tasker"
mkdir -p "$HOME/.termux/tasker"; chmod 700 "$HOME/.termux"
cp -f "$DEST"/tasker/termux-scripts/*.sh "$HOME/.termux/tasker/" 2>/dev/null || true
chmod 700 "$HOME"/.termux/tasker/*.sh 2>/dev/null || true
ok "scripts ready (point Termux:Tasker plugin 'Executable' at e.g. hermes-android-tasker.sh)"

# --- 5. PATH persistence ---
if ! grep -q 'hermes-android/bin' "$HOME/.bashrc" 2>/dev/null; then
  printf '\nexport PATH="$HOME/hermes-android/bin:$PATH"\n' >> "$HOME/.bashrc"
  ok "added toolkit to ~/.bashrc PATH"
fi

# --- 6. next steps ---
cat <<NEXT

$(printf '\033[1mNext steps\033[0m')
  1. Configure a model/provider:      hermes setup
  2. Give Hermes shell powers on the phone (non-root, wireless adb):
                                       bash $DEST/bootstrap/adb-wireless-setup.sh
  3. Self-check:                      hermes-android doctor
  4. Ask it something:                hermes-android perf   # then 'hermes chat'
  5. Keep it alive in the background (optional): see docs/PAIRING.md §gateway

Tasker side (once): install the Termux:Tasker plugin, grant Tasker the
"Run commands in Termux environment" permission, and enable
Preferences → Misc → Allow External Access. Then Hermes can both run your
Tasker tasks (hermes-android tasker-run "Name") and be run BY Tasker.
NEXT
