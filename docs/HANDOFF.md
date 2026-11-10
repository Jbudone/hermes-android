# Handoff — phone managed by Hermes

State as of 2026-11-09. Read this first in a new session.

## TL;DR

The phone is fully drivable and the on-device agent works. From the PC:

    cd ~/jdrive/jstuff/work/personal/hermes-android
    phone                 # status (auto-detects USB → wireless → mDNS → saved)
    phone perf | jank | bloat | insights
    phone shell "…"
    phone wifi-on         # after a reboot: plug USB, run this, unplug

## Device

- Samsung Galaxy S22 Ultra, `SM-S908U1`, Android 16 (SDK 36), aarch64, **not rooted**
- adb serial (USB): `R5CT41C44ZM`
- LAN IP: `192.168.1.129`; PC is `192.168.1.250`
- ZeroTier is installed on the phone; it makes wireless debugging bind to the
  VPN interface and breaks pairing. Disable it if wireless debugging misbehaves.

## What is installed on the phone

- **Termux from F-Droid (0.118.3)** — the Play build was replaced because its
  signature (`61fa5427`) is incompatible with the Termux add-ons (`7c3fcce`).
- **Termux:API** and **Termux:Tasker** (F-Droid, signature-matched).
- **`android-tools` 37.x** — 35.x cannot pair; 37 works (watch for libc++ skew:
  `pkg upgrade` if `adb` fails with `__hash_16__memory` / `__hash_memory`).
- **Hermes Agent 0.22.0 canary**, install method `apt` (canary APT channel).
- **`~/hermes-android`** toolkit + `android-phone-ops` skill in
  `~/.hermes/skills/`.
- **Provider**: `openrouter` / `deepseek/deepseek-v4.1-flash`, key copied from
  the PC's `~/.hermes/.env` (never passed through chat; staged copy deleted).
- **Scheduled digest**: `termux-job-scheduler` job **1001**, periodic 86400000 ms,
  `--persisted true`, script `~/.termux/tasker/digest.sh`, posts a
  `hermes-digest` notification. Cancel: `termux-job-scheduler --cancel --job-id 1001`.
- Termux and Tasker are whitelisted from battery optimisation.

## How adb access works (the important bit)

`adb pair` is broken with android-tools 35.x on this device. Instead the phone
holds **the same adb key the PC authorised over USB**, so `adb connect` works
with no pairing. Details: `docs/PAIRING.md` §D.

Consequences:
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
`svc power stayon usb` keeps it awake while plugged in.

Practical pattern: push a small `.sh` to `/sdcard/Download/`, then type
`bash /sdcard/Download/<name>.sh` and Enter. Avoids quoting problems and keeps
typed text short.

## Frame times / jank (new)

`phone jank` parses `dumpsys gfxinfo` (one dump, all processes, ~0.6 s) into
per-app frame stats: frames, janky %, p50/p90/p95/p99, slow-UI / slow-draw /
missed-vsync counters, aggregated per package. `perf` collects the same dump
and emits `JANK` findings, so HIGH/MED jank now shows up next to CPU/thermal.

- Counters are **cumulative since each process started** (usually boot), so an
  app that dragged at boot still looks bad hours later. For a windowed
  measurement: `phone jank --reset <pkg>`, use the app, then `phone jank`.
- A 200-frame floor (`--min-frames`) keeps one-off splash screens out of the
  ranking; `--json` returns every app plus the notable subset.
- Baseline on this phone (Nov 2026, warm): systemui ~29% janky p95 61 ms
  (HIGH), launcher 13% (MED), Gboard/Termux ~10% (MED). Systemui is the
  standing offender, not a one-off.

## Storage work already done

Freed ~19.5 GB (99% → ~80% used): uninstalled Hearthstone (10.8 GB) and Diablo
Immortal (6.2 GB), cleared Smart Switch leftovers (6.2 GB), removed Facebook +
Messenger (1.8 GB), froze Bixby language packs, trimmed caches.

Still large if more is needed: `com.android.providers.telephony` ~3.2 GB,
Messages ~3.1 GB, YouTube ~2.0 GB (clearing these is destructive — ask first).

Removal flow, from an audit to an applied plan:

    phone bloat --json > /tmp/audit.json          # inventory
    phone bloat-strip --plan /tmp/audit.json       # preview a plan (dry run)
    phone bloat-strip --plan /tmp/audit.json --yes --freeze   # apply, journalled
    phone bloat-strip --restore <ledger.jsonl>     # undo

`--plan` reads `bloat-audit --json` and writes a reviewable
`bloat-plan-<ts>.json` next to the ledger; `--include-unused` adds 90-day-unused
third-party apps and `--min-mb` filters small ones. Already-disabled packages
are skipped, and the hard blocklist still wins over anything in the plan file.

## What remains

1. **Tasker profiles** for instant reactions (battery low, charger connected) —
   `docs/TASKER-RECIPES.md`. Needs UI taps; plugin actions cannot be generated
   as XML (their action code is assigned per plugin instance).
2. Optional further storage cleanup (above).
3. Optional: messaging gateway on the phone (`hermes gateway run`) so the phone
   can be driven from Telegram with no laptop.

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
