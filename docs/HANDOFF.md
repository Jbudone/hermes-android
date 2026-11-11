# Handoff — phone managed by Hermes

State as of **2026-11-10 (round 2)**. Read this first in a new session.

## TL;DR — how to resume

Everything lives in this repo (committed + pushed) or in on-device state that
survives; nothing is only on the PC. **Disconnecting the phone is safe.**

    cd ~/jdrive/jstuff/work/personal/hermes-android
    phone                 # status (USB → wireless → mDNS → saved)
    phone perf | jank | drain | bloat | insights
    phone wifi-on         # after a reboot OR a USB disconnect: plug USB once

To come back: plug in USB, run `phone` (or `phone wifi-on` to go wireless
again), then unplug.

## Device

- Samsung Galaxy S22 Ultra, `SM-S908U1`, Android 16 (SDK 36), aarch64, **not rooted**
- adb serial (USB): `R5CT41C44ZM`
- LAN IP **rotates** (seen `.58`, then `.129`); PC is `192.168.1.250`
- ZeroTier is installed but **not running**; freeze it (`pm disable-user`) only if
  wireless debugging misbehaves.

## What is installed on the phone

- **Termux from F-Droid** (Play build replaced — signature mismatch with add-ons)
- **Termux:API** and **Termux:Tasker** (F-Droid, signature-matched)
- **`android-tools` 37.x** (35.x cannot pair)
- **Hermes Agent canary** (apt/canary channel); provider `openrouter` /
  `deepseek/deepseek-v4.1-flash`, key copied from the PC's `~/.hermes/.env`
  (never passed through chat; staged copy deleted).
- **`~/hermes-android`** toolkit + the `android-phone-ops` skill in `~/.hermes/skills/`
- Grants that **persist** (re-apply only after a factory reset): `pm grant`
  `com.termux.permission.RUN_COMMAND` and `WRITE_SECURE_SETTINGS` to Tasker;
  battery-optimisation whitelist for Termux + Tasker; `termux-job-scheduler`
  digest job **1001** (periodic 86400000 ms, `--persisted true`,
  `~/.termux/tasker/digest.sh` → `hermes-digest` notification).

## Toolkit commands

`doctor`, `perf`, `perf-fix`, `jank`, `drain`, `bloat`, `bloat-strip`,
`insights`, `tasker-run`, `tasker-signal`, `tasker-gen`, `keepalive`,
`self-update`, `backup`.

The **PC copy is authoritative** and always current. The phone's clone lags —
refresh it on-device with `hermes-android self-update` (it was last pulled to
`67decb7`; the PC is ahead).

## Tasker automations (all enabled)

| Profile | Trigger | Task |
|---|---|---|
| `*Battery Level 0, 15` | State → Power → Battery Level 0–15 | `Battery Low Guard` (`hermes-android-tasker.sh perf-fix --yes trim-caches kill-bg`) |
| `*Power Any` | State → Power → Power | `Charger Guard` (`perf-guard.sh --fix`) |
| `*Device Boot` | Event → System → Device Boot | `Agent Keepalive` (`hermes-android-tasker.sh keepalive` — wake-lock + heartbeat + re-assert digest) |

Each task's action 2 is Notify (text `%stdout`). Tasker is **v6.7.9**.
Recipes + UI-driving notes: `docs/TASKER-RECIPES.md`. Build new plugin tasks by
**cloning** a working one (long-press → Clone → rename).

## Storage, backups, tweaks

- Storage **76% used (~26 GB free)**. SMS/MMS were cleared after a full export.
- **Backups: `~/phone-backups/2026-11-10/`** — `sms.txt` (16,627 w/ bodies),
  `mms_meta.txt`, `mms_parts_text.txt`, `mms_media/` (2,438 files, 3.1 GB),
  `calls.txt`, and `secrets/` (Google OAuth client secrets pulled off /sdcard).
  Re-run any time: **`phone backup`** (PC-side).
- **Frozen** (`bloat-strip --freeze`, reversible): all Bixby service/agent/
  wakeup/vision + facebook appmanager/services/system. Freezing stops the
  services but frees **no disk** — use `--remove` for space.
- **Background-restricted** (`perf-fix restrict`, reversible): osp.app.signin,
  samsung.android.rubin.app, podcastaddict, finch, android.vending, sbrowser.

## What does NOT survive

- **Wireless debugging does NOT survive a reboot** (verified by actually
  rebooting): `adb_wifi_enabled` resets to 0, and both the IP and the port
  rotate. After any reboot you need **USB once** → `phone wifi-on`. Tasker
  cannot automate this (Run Shell → error 255).
- Disconnecting USB also drops the wireless endpoint, so resume starts at USB.

## How adb access works (the important bit)

`adb pair` is broken with android-tools 35.x on this device. Instead the phone
holds **the same adb key the PC authorised over USB**, so `adb connect` works
with no pairing. Details: `docs/PAIRING.md` §D. Consequences:

- On device: `adb connect 127.0.0.1:<port>` then `phone`.
- The wireless port rotates on every toggle; **adbd stops advertising on mDNS
  once a client is connected**, so if the PC holds the session the phone sees
  nothing. Get the port from `adb devices` on the PC, or disconnect the PC first.
- `adb shell settings put global adb_wifi_enabled 1` turns wireless debugging on
  without tapping the screen.

## Automating the phone UI

`shell` cannot run commands inside Termux: every entry point (RUN_COMMAND
service, Termux:Tasker plugin) is gated by the signature-level
`com.termux.permission.RUN_COMMAND`. `run-as` fails (Termux is not debuggable).
So when something must run *inside* Termux, drive the UI:

    adb shell input text 'bash%s/sdcard/Download/script.sh'   # %s = space
    adb shell input keyevent 66                               # Enter

The user must unlock first (secure keyguard — never bypass or ask for the PIN).
`svc power stayon usb` keeps it awake while plugged in. Practical pattern: push
a small `.sh` to `/sdcard/Download/`, then type `bash /sdcard/Download/<name>.sh`.

## Frame times / jank

`phone jank` parses `dumpsys gfxinfo` into per-app frame stats (frames, janky %,
p50/p90/p95/p99, slow-UI/draw, missed-vsync), aggregated per package; `perf`
emits `JANK` findings too.

- Counters are **cumulative since each process started**, so an app that dragged
  at boot looks bad hours later. For a windowed number: `phone jank --reset <pkg>`,
  use the app, then `phone jank`.
- **The old "systemui 29% HIGH" was boot-cumulative** — windowed it is ~10–11%
  on a 120 Hz panel. Don't chase it; the real idle cost is memory pressure
  (see below).

## CPU / memory

- **`phone drain`** samples CPU over N frames and ranks persistent offenders —
  a 1 s snapshot is noise. First real run: no rogue third-party app; idle CPU is
  memory-pressure fallout (`kswapd0`, `system_server`, `HeapTaskDaemon`).
- Memory is the top smoothness lever: swap runs ~2–2.8 GB of 4.2 GB. Relief so
  far = `perf-fix trim-caches kill-bg` + the restrictions above (reversible).

## Gotchas that cost time (do not rediscover)

| Symptom | Cause / fix |
|---|---|
| `protocol fault … Success` on `adb pair` | ADB 35.x bug; key-sharing, not retries |
| `adb` not on PATH | `~/.local/bin/adb` symlink, or lib falls back to platform-tools |
| Play Termux + add-ons don't talk | signature mismatch; use F-Droid Termux |
| `sources.list.d` write failed | fresh Termux lacks the dir; `mkdir -p` first |
| `constraints-termux.txt` missing | no longer shipped upstream; install `.[termux]` without it |
| `pkg -y update` | invalid; flags go **after** the subcommand (`apt-get -y … update`) |
| apt/dpkg hangs with no output | conffile prompt; `--force-confnew`, `stdin </dev/null` |
| `hermes -c "prompt"` | `-c` = continue session; one-shot is `hermes chat -q "prompt"` |
| `dumpsys`/`pm` denied in Termux | SELinux; go through `adb shell` (`ao_sh`) |
| Tasker: `plugin error: missing, disabled, not exported or no permission receiver` | plugin app is in Android **stopped** state (launch it once) and/or Tasker lacks `com.termux.permission.RUN_COMMAND` (`pm grant …`) |
| `adb shell input text "%stdout"` types `" tdout"` | `input text` rewrites `%s` to a space; for Tasker variables use the field's variable-pick (tag) icon |
| `adb shell input text "a b"` types `"ab"` | spaces need `%s`; keep strings short, push a `.sh` to `/sdcard/Download/` |
| Tasker has no *Battery Low* / *Power Connected* event | Tasker 6.7.x / Android 16 removed them; use State → Power → Battery Level / Power |
| Termux:Tasker config says "The (unknown) App (null) has not been granted …" | expected when launched from adb (no calling app); not the plugin failure |
| **New Tasker task/profile vanishes** | Tasker does not flush immediately — `am force-stop` right after creating it loses it. Verify after a Tasker restart |
| Tasker `Run Shell` → **Error 255** | can't write global settings here even with WRITE_SECURE_SETTINGS; use `adb shell` |
| Plugin **Executable field autocorrected** (`hermes-android-tasker.sh` → `hermes Android tasker.sh`) | type a few chars and tap the file-autocomplete suggestion |
| `dumpsys diskstats` sizes look wrong / frozen | per-package sizes are **stale** on this device; `bloat` now uses live `cmd package get-package-storage-stats`. Trust `df` |
| `pm clear` seems not to work | re-query **after** the provider restarts; an immediate read shows pre-clear rows |
| MMS attachments unreachable by file-transfer apps | they live in the telephony provider's private storage; use `content://mms/part` + `content read` (`phone backup`) |

## What remains

1. **Telegram gateway** on the phone — exact steps in `docs/PHONE-GATEWAY.md`;
   needs the user's bot token (entered on the device, never through chat).
2. Decide on `Outlook` (652 MB) / `Samsung Notes` (368 MB): freeze / remove /
   keep. Games (~3.9 GB) are in use, not dormant. `com.android.carrierconfig`
   was flagged by the sweep but is system-critical — leave it.
3. Optional: periodic `perf-guard` to catch regressions (the daily digest partly
   covers it).
