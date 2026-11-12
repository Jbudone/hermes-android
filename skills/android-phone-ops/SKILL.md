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
hermes-android jank [--json]          per-app frame-time / jank % from gfxinfo
hermes-android perf-fix [--dry-run]   safe, reversible remediations
hermes-android bloat [--json]         bloat / unused-app audit
hermes-android bloat-strip --dry-run  preview freeze/remove (reversible + ledger)
hermes-android bloat-strip --plan F   apply a saved audit: audit -> plan -> done
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
- **"Why does it feel laggy?"** → `jank` (frame-time percentiles per app,
  jank %). Counters are cumulative since each process started, so reset first
  for a windowed number: `jank --reset <pkg>`, use the app, `jank` again.
- **"Strip bloat"** → `bloat` to list candidates, `bloat-strip --dry-run` to
  preview, then `--yes (--freeze|--remove) <pkgs>`. FREEZE (`pm disable-user`)
  is preferred over REMOVE for anything you might want back. Everything is
  journalled; `bloat-strip --restore <ledger>` undoes it. The blocklist
  (systemui, settings, phone, gms, termux, Tasker…) is refused automatically.
  For a one-flow pass use `bloat --json > audit.json` then
  `bloat-strip --plan audit.json` (preview) / `--yes --freeze` (apply);
  `--include-unused` and `--min-mb` shape the selection.
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
- `dumpsys gfxinfo` (no package) returns every rendering process in one call
  (~0.6 s, ~700 KB). Blocks with no `Total frames rendered` are windowless
  processes — skip them, they are not a jank signal.
- Generated `.tsk.xml` uses only verified action layouts (877 Send Intent,
  104 Browse URL, 20 Launch App, 30 Wait, 123 Run Shell). Import-test once.

## Pitfalls

- **`adb pair` is broken in Termux's `android-tools` 35.x** (`protocol fault
  (couldn't read status message): Success` on every address/port, even after a
  reboot, over LAN with a fresh code). Don't fight it: adb auth is key-based, so
  authorise the PC's key over USB, copy `~/.android/adbkey` into Termux's
  `~/.android/`, then `adb connect` — no pairing at all. See `docs/PAIRING.md` §D.
- **Wireless-debugging port rotates on every toggle.** Never hardcode it; use
  `phone connect` (mDNS) or `adb connect 127.0.0.1:<port>` from the screen.
  `adb shell settings put global adb_wifi_enabled 1` turns it on without tapping.
- **Termux needs "All files access" to read `/sdcard`**:
  `adb shell appops set com.termux MANAGE_EXTERNAL_STORAGE allow`.
- `phone` resolves AO_ADB_SERIAL → USB → already-connected → mDNS → saved port,
  so it works identically on the PC and on the phone.
- The official Hermes Termux APT package: the `stable` channel 404s while
  `canary` is live; `install.sh` now refuses on Termux. Use the canary channel.
- **Termux from Google Play cannot use the add-ons.** Termux:API/Tasker are
  F-Droid-signed; `RUN_COMMAND` is signature-gated, so a Play build installs the
  plugins but they can never talk to it. Use F-Droid Termux (same key as the
  plugins). Check with `dumpsys package com.termux | grep -oE 'signatures:\[[0-9a-f]+\]'`.
- Fresh F-Droid Termux has no `/etc/apt/sources.list.d`; `mkdir -p` it before
  writing a repo file, or the write fails silently and the package is "not found".
- Upstream no longer ships `constraints-termux.txt`; the from-source fallback
  must install `.[termux]` without `-c`. Also repair any half-finished clone.
- `pkg -y update` is invalid — flags go after the subcommand. Use
  `apt-get -y -o Dpkg::Options::=--force-confnew update`.
- **Tasker plugin errors "missing, disabled, not exported or no permission
  receiver"** mean the plugin app is in Android's *stopped* state (never
  launched — a stopped package's receivers get no broadcasts) and/or the caller
  lacks `com.termux.permission.RUN_COMMAND`, which protects its service.
  Fix both: launch the plugin once
  (`am start -n com.termux.tasker/.activities.TermuxTaskerLauncherActivity`
  then `pm grant net.dinglisch.android.taskerm com.termux.permission.RUN_COMMAND`
  — it is protectionLevel=dangerous, so `pm grant` works). Verified: the plugin
  then configures normally and the action reports success.
- **`adb shell input text` cannot express `%` or a plain space.** `%s` becomes a
  space, and a literal `%` is swallowed (`"%stdout"` arrives as `" tdout"`). For
  Tasker variables, tap the field's variable-pick (tag) icon instead. Prefer
  pushing a `.sh` to `/sdcard/Download/` and typing `bash /sdcard/Download/x.sh`.
- **Tasker 6.7.x on Android 14+ dropped the Power *events*** (Battery Low, Power
  Connected). Use states: *State → Power → Battery Level* (0–15) and *State →
  Power → Power*. UI drives fine over adb: screenshot → tap with
  full-resolution coordinates (double a half-size screenshot's).
- **You cannot run commands inside Termux from adb.** RUN_COMMAND and the
  Termux:Tasker receiver both require the signature permission, and `run-as`
  fails (not debuggable). Drive the UI instead: `adb shell input text 'cmd%sarg'`
  (`%s` = space) then `input keyevent 66`. Needs the phone unlocked — never
  bypass or ask for a PIN. `svc power stayon usb` stops it re-locking.
- Periodic on-device work does not need Tasker: `termux-job-scheduler --script
  … --period-ms … --persisted true`. Android's floor is ~15 min; use Tasker only
  for instant event reactions.
- adbd stops advertising on mDNS once a client is connected, so `adb mdns
  services` can be empty while the endpoint is alive — check `adb devices` first.
- Tasker XML untested actions: don't invent `<Action>` codes. Extend the
  `ACTION` table in `tasker/gen_tsk.py` only with a verified layout.
- `pm uninstall --user 0` is reversible via `cmd package install-existing`.
  Do not use `--user all` (irreversible without reflash).
- On the phone, `127.0.0.1` is not a trust boundary — any app with network
  permission can reach a local server, so keep the Hermes gateway token-gated.
- Android may suspend Termux in the background: `termux-wake-lock` plus a
  battery-optimisation exemption helps but does not guarantee it.
- **Build the 2nd+ plugin task by CLONING a working one**, not from scratch:
  long-press the task → 3-dot → Clone → rename. The clone keeps the plugin
  action *and* the timeout, so you only edit Executable / Arguments / title.
- **MMS attachments ARE extractable over adb** (no root): list parts with
  `content query --uri content://mms/part --projection _id,mid,ct,text` (the
  `text` column gives all MMS bodies in one query), then pull bytes per media
  part with `adb exec-out content read --uri content://mms/part/<id> > f.jpg`.
  `--where`/`--sort` are NOT supported by this device's `content` CLI.
- **`dumpsys diskstats` per-package sizes are stale on this device** — they did
  not change after freeing 5.8 GB, and reported 6.4 GB for a package whose
  `pm clear` *and* `pm uninstall --user 0` freed nothing. Trust `df`, not
  `diskstats`/`bloat` per-package sizes.
- **Verify a `pm clear` on a provider after it restarts** — an immediate
  `content query` can be served by the not-yet-restarted process and show the
  old rows; re-query and look for `SQLITE_CANTOPEN_ENOENT` (DB gone) to confirm.
- **The plugin's Executable field is autocorrected** — typing
  `hermes-android-tasker.sh` yields `hermes Android tasker.sh`. Type a few
  chars (`perf`, `herm`) and tap the field's file-autocomplete suggestion instead.
- **Tasker does not flush new tasks/profiles to disk immediately.** Killing
  Tasker (`am force-stop`) right after creating a task/profile can lose them
  (observed: a new task + its boot profile vanished after a force-stop). After
  building anything in Tasker, verify it survives a Tasker restart before
  relying on it.
- **Tasker `Run Shell` can't write global settings here.**
  `/system/bin/settings put global adb_wifi_enabled 1` returns **Error 255**
  even with `WRITE_SECURE_SETTINGS` granted and after a Tasker restart — it is
  permission/SELinux, not a PATH problem. Do privileged toggles over `adb shell`
  instead, and treat the on-device re-enable of wireless debugging as unsolved.
- **Secondary Android users are invisible to user-0 ops.** This device runs
  Android **user 150 (Samsung Secure Folder)**, which carries its own GMS +
  Play Store + `osp.app.signin` (~1.5 GB RSS). `pm list packages -d`, `appops`,
  `restrict` etc. default to user 0 and either silently miss it or print
  `SecurityException: Shell does not have permission to access user 150`. Run
  `pm list users` and `dumpsys meminfo | grep 'user 150'` before claiming a
  memory win.
- **Package audits miss leftover app data.** `/sdcard/Android/obb/<pkg>` and
  `/sdcard/Android/data/<pkg>` survive an uninstall and are invisible to `pm`
  (measured: 15 orphan OBB dirs ≈ 5.7 GB). Diff those dirs against `pm path
  <pkg>` before proposing storage work.
- **Raw uids everywhere** (`u0a687`, `10246` in `insights`/`drain`/wakelocks and
  `/proc/net/tcp`). Map with `pm list packages -U | grep uid:<n>`, dropping the
  `u0a` prefix (u0a687 = uid 10687 = package name).
- **A registered job is not a running job.** `termux-job-scheduler` job 1001
  exists + PERSISTED while its constraints churn
  (`Unsatisfied constraints: … WITHIN_QUOTA`, `Standby bucket: NEVER`) even with
  `am get-standby-bucket com.termux` = 5 (exempted). Check the job's block in
  `dumpsys jobscheduler` (note its `Network:` id — it can resolve onto a VPN)
  before trusting a "daily digest is live" claim.
- **Reversibility ledgers live in `$TMPDIR/ao-run/<serial>/`**, which is scratch
  and pruned — export the ledger (or the current disabled/frozen package set)
  if the undo path must outlive the session.
- **ZeroTier may be an active always-on VPN** (`dumpsys connectivity | grep -i
  'VPN:'` → `tun0`, `VpnTransportInfo{… sessionId=ZeroTier One}`) even when the
  docs say it is not running; it routes all uids and costs CPU. Verify state
  instead of trusting the note.
- **To audit what the phone exposes on the LAN**: `cat /proc/net/tcp{,6}` (uid +
  hex port, state `0A` = LISTEN) then `nmap -Pn -p <ports> <phone-ip>` from the
  PC — bound-to-0.0.0.0 ≠ reachable, and vice versa.
