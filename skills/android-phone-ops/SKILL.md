---
name: android-phone-ops
description: "Use when driving an Android phone from Hermes: perf, bloat, insights, Tasker. Runs the hermes-android toolkit over adb (non-root)."
version: 1.0.0
license: MIT
platforms: [linux, android]
metadata:
  hermes:
    tags: [android, termux, adb, performance, bloat, tasker, debloat, insights]
---

# Android phone ops

Operate a real Android phone — detect & fix performance problems, strip bloat,
produce insights, and build Tasker automations — through one toolkit,
`hermes-android`, that works both on a PC (adb over USB/wireless) and
on the phone itself (Termux, adb-to-self). No root required, though root
upgrades what is possible.

Toolkit lives at `$HOME/hermes-android` (override with `HERMES_ANDROID_HOME`).
Install/verify: `hermes-android doctor`.

## The one rule that matters

Privileged Android ops (`pm`, `cmd`, `dumpsys`, `settings`, `am`) must run via
`adb shell` — a plain Termux user is denied those binder services by SELinux.
The toolkit routes everything through `ao_sh` in `lib/android-ops.sh`, which
resolves the right adb target automatically (explicit `AO_ADB_SERIAL` →
a connected `localhost:*` → the single connected device). Never run `pm`/`cmd`
directly inside Termux and expect it to work.

## Commands

```
hermes-android doctor                 environment + device self-check (run first)
hermes-android perf [--json]          performance report + findings (HIGH/MED/LOW)
hermes-android perf-fix [--dry-run]   safe, reversible remediations
hermes-android bloat [--json]         bloat / unused-app audit
hermes-android bloat-strip --dry-run  preview freeze/remove (reversible + ledger)
hermes-android insights [--json]      battery, wakelocks, storage, network
hermes-android tasker-run "Task"      run a named Tasker task
hermes-android tasker-signal EVT data broadcast a Hermes→Tasker event
hermes-android tasker-gen ...         generate importable .tsk.xml
```

## Workflow for the five asks

- **"Detect & fix performance issues"** → `perf` (read the findings), then
  `perf-fix --dry-run` to see remediations, then `perf-fix --yes <actions>`.
  Prefer `trim-caches kill-bg anim-fast` first; `compile-speed` is heavy.
  Anything from `perf` tagged HIGH is worth acting on; report the evidence.
- **"Strip bloat"** → `bloat` to list candidates, `bloat-strip --dry-run` to
  preview, then `--yes (--freeze|--remove) <pkgs>`. FREEZE (`pm disable-user`)
  is preferred over REMOVE for anything you might want back. Everything is
  journalled; `bloat-strip --restore <ledger>` undoes it. The blocklist
  (systemui, settings, phone, gms, termux, Tasker…) is refused automatically.
- **"Add new features"** → this is just Hermes writing for the phone: Termux
  scripts in `~/.termux/tasker/`, toolkit extensions (add a `commands/*.sh` +
  a dispatcher case), or a Tasker task via `tasker-gen`.
- **"Give insights"** → `insights`; then reason over the raw dumps in the
  printed run dir for anything the parser didn't surface.
- **"Interesting Tasker stuff"** → write the Termux-side script, then either
  (a) point the Termux:Tasker plugin at `hermes-android-tasker.sh <subcommand>`,
  (b) `tasker-run "Name"` to fire an existing Tasker task, or
  (c) `tasker-gen` a `.tsk.xml` to import.

## Verify, don't assume

- adb wireless ports change every time Wireless Debugging is toggled — if ops
  suddenly fail, re-run `bootstrap/adb-wireless-setup.sh --reconnect`.
- After any `bloat-strip` or `perf-fix` apply, re-run `perf`/`bloat` and
  read back the state before claiming success.
- Generated `.tsk.xml` uses only verified action layouts (877 Send Intent,
  104 Browse URL, 20 Launch App, 30 Wait, 123 Run Shell). Import-test once.

## Pitfalls

- The official Hermes Termux APT package is currently broken upstream (repo
  404s). Install via the from-source one-liner, which detects Termux and
  prebuilds the psutil shim — `bootstrap/termux-bootstrap.sh` does this.
- Tasker XML untested actions: don't invent `<Action>` codes. Extend the
  `ACTION` table in `tasker/gen_tsk.py` only with a verified layout.
- `pm uninstall --user 0` is reversible via `cmd package install-existing`.
  Do not use `--user all` (irreversible without reflash).
- On the phone, `127.0.0.1` is not a trust boundary — any app with network
  permission can reach a local server, so keep the Hermes gateway token-gated.
- Android may suspend Termux in the background: `termux-wake-lock` plus a
  battery-optimisation exemption helps but does not guarantee it.
