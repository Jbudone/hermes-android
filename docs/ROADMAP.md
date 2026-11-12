## Roadmap

Shipped:
- [x] Privilege layer (`lib/android-ops.sh`) with PC + adb-to-self target resolution
- [x] perf report / fix, bloat audit / strip, insights, doctor
- [x] Tasker bridge both ways + verified `.tsk.xml` generator
- [x] Termux bootstrap + wireless-adb pairing helper
- [x] `android-phone-ops` skill + offline test suite (50 tests)
- [x] `phone` one-command entry point (USB → connected → mDNS → saved)
- [x] On-device Hermes (canary apt) configured and driving itself over adb-to-self
- [x] Termux:API / Termux:Tasker installed, signature-matched (F-Droid Termux)
- [x] Scheduled daily digest via `termux-job-scheduler` (job 1001, persisted)
- [x] First real cleanup: ~19.5 GB freed, storage 99% → ~80%
- [x] gfxinfo frame-time analysis: `jank` command + `lib/gfxinfo.py`, wired into `perf`
- [x] `bloat-strip --plan <audit.json>`: audit → reviewable plan → apply in one flow

In progress:
- [x] Tasker guards for instant reactions — **both rebuilt and verified** this
      session: `Battery Low Guard` (+ profile `*Battery Level 0, 15`) and
      `Charger Guard` (+ profile `*Power Any`), all enabled.
      Note: the previous session's guards were lost when Tasker updated
      6.7.8 → 6.7.9; rebuilt from `docs/TASKER-RECIPES.md`.

Next — prioritized improvement plan (execute in this order):

1. [x] systemui jank — investigated and reframed. Windowed sample is ~10–11%
       janky / p95 34 ms on a 120 Hz panel; the 29% "HIGH" was cumulative
       since boot, not steady-state. Animations already at 0.5; set
       `accessibility_reduce_transparency=1` (small win: systemui 11.5→10.7%,
       launcher 11→9.1%). **Real sustained drain found instead: AirDroid
       (`com.sand.airdroid` + `:push`) ≈9% CPU (~1 h CPU each since boot) and
       2.5 GB swap in use (MemAvailable ~2.9 GB of 7.2 GB).**
       DONE: AirDroid frozen (`pm disable-user --user 0`, reversible) —
       both PIDs gone, ~9% CPU reclaimed. Follow-up: relieve memory pressure.
2. [x] Reclaim ~6 GB — DONE. Freed ~5.8 GB (df: 84.6 → 78.8 GB used; 82 → 76%).
       SMS + MMS cleared via `pm clear com.android.providers.telephony`; the
       call log survived (2,000 rows — served by the contacts provider).
       Messages app data cleared too (`pm clear com.google.android.apps.messaging`).
       Complete backups in ~/phone-backups/2026-11-10/: sms.txt (16,627 with
       bodies), mms_meta.txt (25,899), mms_parts_text.txt, mms_media/ (2,438
       files, 3.1 GB), calls.txt (2,000).
       CAVEAT: `dumpsys diskstats` per-package sizes are **stale** on this
       device — they did not change after freeing 5.8 GB — so anything derived
       from them (incl. the easyMover 6.4 GB "phantom") can't be trusted.
       A stale provider read also briefly showed the messages as still present;
       verify clears by re-querying after the provider restarts.
3. [~] Tasker guards — charger pair DONE. `Charger Guard` task (clone of the
       working Battery Low Guard → executable `perf-guard.sh`, args `--fix`,
       timeout carried over) built and verified green; profile `*Power Any`
       (State → Power → Power, Source: Any) attached + enabled. Both guards now
       enabled: `*Battery Level 0, 15` → Battery Low Guard; `*Power Any` →
       Charger Guard. Remaining: a screen-off / periodic `perf-guard` to catch
       regressions (the daily termux-job-scheduler digest partly covers this).
       LESSON: clone a working task (long-press → Clone) instead of rebuilding —
       it keeps the plugin action + timeout, so only Executable/Args/title change.
4. [~] Harden on-device agent background survival. CONFIRMED already in place:
       Termux + Tasker are both battery-optimisation whitelisted
       (`dumpsys deviceidle whitelist` → `user,com.termux`, `user,net.dinglisch.android.taskerm`)
       and the digest job is live (`termux-job-scheduler` job #u0a449/1001).
       Remaining: `termux-wake-lock` + a watchdog — both need Termux-side
       scripts (drive via a Tasker task whose plugin Executable is an absolute
       path to `bash` with `-c "…"`, since new files can't be written into
       Termux's home over adb).
5. [x] Security cleanup of shared storage — DONE. Backed up and removed the two
       Google OAuth `client_secret_*.json` files from `/sdcard/Download`
       (copies in ~/phone-backups/2026-11-10/secrets/), plus the session's own
       scripts (hm-*, ha-update.sh, termux-migrate.sh). ZeroTier
       (`com.zerotier.one`) is installed but **not running** — left in place;
       freeze it (`pm disable-user`) only if wireless debugging misbehaves.
       CORRECTION 2026-11-11: this is wrong — ZeroTier **is** running as an
       always-on VPN (`tun0 172.27.110.73/16`, VpnTransportInfo sessionId
       "ZeroTier One", ~4.8% CPU). See round-3 #9.
6. [~] Remote-control path with no laptop. Wireless adb DONE: enabled
       (`settings put global adb_wifi_enabled 1`), phone now at
       **192.168.1.58:34693**, key-based connect verified, and
       `bootstrap/adb-wireless-setup.sh --reconnect` works (ports saved to
       `$TMPDIR/ao-run/ports.env`). `WRITE_SECURE_SETTINGS` granted to Tasker.
       Remaining: (a) the Hermes gateway on the phone for Telegram — needs the
       bot token; (b) a working on-boot re-enable of wireless debugging
       (Tasker Run Shell `/system/bin/settings put global adb_wifi_enabled 1`
       returns **Error 255** — permission/SELinux, not PATH; the global setting
       may already persist across reboots, unverified).

Next — round 2 (execute in this order):

1. [x] Cut memory pressure — DONE (partial, reversible). `perf-fix trim-caches
       kill-bg` + `restrict` on 6 non-essential resident apps (osp.app.signin,
       samsung.android.rubin.app, podcastaddict, finch, vending, sbrowser).
       Swap used **2.83 → ~2.02 GB** (~800 MB reclaimed); MemAvailable
       ~2.6 → ~3.3 GB. Ceiling reached: the remaining ~2 GB is core
       (GMS ~545 MB, system_server, systemui) — further gains need #5.
       Revert any of it: `perf-fix --yes "unrestrict <pkg>"`.
2. [x] Standing background-drain sweep — DONE. New `hermes-android drain`
       command: samples `dumpsys cpuinfo` over N frames and ranks avg/max CPU
       per process (a 1s snapshot is noise). First real run found **no rogue
       third-party app** — the idle CPU is memory-pressure fallout: kswapd0
       ~7%, system_server spiking to 32%, HeapTaskDaemon 8+ min CPU. So the fix
       is #1/#5 (less resident memory), not more restrictions. Run `drain`
       again after #5 to confirm the drop.
3. [x] Fix the toolkit's size numbers — DONE. `bloat` now sizes from
       `cmd package get-package-storage-stats` (live), run as ONE on-device loop
       so it stays fast; `dumpsys diskstats` is only a fallback. Verified:
       Messages 2975 → 178.9 MB, telephony 3189 → 11 MB, easyMover phantom gone.
4. [x] `phone backup` — DONE. New `backup` command exports SMS + MMS metadata +
       MMS text + all MMS media (`content://mms/part` + `content read`) + call
       log to `~/phone-backups/<date>/`; `--no-media` for a fast text-only pass;
       restore note included. Verified end-to-end (calls=2000).
5. [x] Dormant-app sweep — DONE (partial). Froze 7 unambiguous bloat packages
       (all Bixby service/agent/wakeup/vision + facebook appmanager/services/
       system, ~894 MB of APK) via `bloat-strip --freeze`. NOTE: `disable-user`
       stops the services and their background CPU but does NOT free disk — use
       `--remove` (reversible via install-existing) for space. Deliberately NOT
       frozen, needs your call: Outlook (652 MB), Samsung Notes (368 MB),
       com.android.carrierconfig (system-critical). Games (~3.9 GB) are in use.
6. [~] Finish remote control. Wireless adb works but **does NOT survive a
       reboot** — VERIFIED by an actual reboot: `adb_wifi_enabled` resets to 0,
       and both the LAN IP (192.168.1.58 → .129) and the port (34693 → 41373)
       rotate. So after a reboot you need USB once:
       `adb shell settings put global adb_wifi_enabled 1` (what `phone wifi-on`
       does), then reconnect. Tasker can't do it (Run Shell → 255).
       Current endpoint: **192.168.1.129:41373**.
       Gateway: exact steps in `docs/PHONE-GATEWAY.md`; needs the user's bot
       token (entered on the device, never through chat) — not yet set up.

Next — round 3 (backlog from the 2026-11-11 evidence pass; discuss/execute one
by one):

1. [ ] **Termux:Boot layer** — install the F-Droid `com.termux.boot` add-on and
       put `~/.termux/boot/*` scripts in place (`termux-wake-lock`, re-assert
       job 1001, heartbeat to the PC). Covers the half Tasker provably cannot:
       agent survival across a reboot. NOTE: `docs/PHONE-GATEWAY.md` §5 already
       points at Termux:Boot for the gateway; it is not installed (no
       `com.termux.boot` package on the device).
2. [ ] **Tasker "ADB Wifi" action as the reboot-survivable adb fix** — Tasker
       has shipped an ADB Wifi action since 5.9.2 that runs shell commands as
       the adb-shell uid over a local pairing, which is the wall that makes Run
       Shell return Error 255. VERIFY FIRST: pairing state may not survive a
       reboot either, so don't promise "no USB ever" until tested.
3. [ ] **`phone state --json` + `phone verify` drift check + generated
       HANDOFF** — docs already contradict each other (.58 vs .129:41373) and
       go stale whenever the port rotates. Persist device state (endpoint, df,
       swap, frozen/restricted sets, job IDs, running users) to
       `~/.local/state/hermes-android/state.json`, diff doc claims against the
       device, and render HANDOFF.md from it instead of hand-editing.
4. [ ] **Run history + trend-based regression alerts** — append every
       `perf`/`jank`/`drain`/`bloat` run to JSONL; alert (notify-send on the
       PC, Healthchecks ping) only when windowed jank or swap crosses the
       trailing median. A single-snapshot "periodic perf-guard" catches bad
       minutes, not regressions.
5. [ ] **Backups: encrypt at rest, prove restore, scope the device key** —
       `~/phone-backups/2026-11-10/secrets/` is plaintext Google OAuth client
       secrets; encrypt via the getkey/sync-secrets toolchain, give the
       on-device Hermes its own scoped provider key instead of the PC's full
       OpenRouter key, add a restore drill (import sms/mms into a scratch
       sqlite, verify 16,627 / 2,438 counts + checksums), and an age-out policy
       for the 3.1 GB of `mms_media`.
6. [ ] **Measured per-boot memory baseline + one zram experiment** — swap is
       back to **2.54 GB used** of 4.19 GB (round-2 recorded ~2.02 GB), so the
       "remaining ~2 GB is core, ceiling reached" claim is stale. Capture a
       per-boot baseline, then vary zram size / `vm.swappiness` / GMS
       background policy one at a time with a documented revert; clear the two
       deferred bloat calls (Outlook 652 MB, Samsung Notes 368 MB) through the
       reversible `--remove` path while recording real `df` deltas.
7. [ ] **`phone orphans` — leftover app data whose package is gone** —
       measured **~5.7 GB**: 15 dirs under `/sdcard/Android/obb` with no
       installed package (warpath 1239 MB, roc 847 MB, snailgames 844 MB,
       zombie.survival.craft.z 664 MB, ec2 503 MB, harvest 479 MB, escapists2
       366 MB, dayzsurvival 355 MB, battlecmd 244 MB, stardewvalley 212 MB, +4
       small). `bloat`/`bloat-strip` cannot see any of it (they audit packages,
       not leftovers). Command lists obb/data dirs with no `pm path`, size +
       mtime; `--clean` moves to a trash dir first.
8. [ ] **Multi-user awareness (Secure Folder = user 150)** — `pm list users`
       shows `UserInfo{150:Secure Folder}` RUNNING_UNLOCKED and it runs its own
       GMS 250 MB + gms.unstable 237 MB + osp.app.signin 234 MB + vending ×2
       ≈297 MB + restore 104 MB + Samsung services (≈1.5 GB RSS). User-0 ops
       miss it entirely (`SecurityException: Shell does not have permission to
       access user 150`), which is why round-2's `restrict osp.app.signin`
       moved nothing. Needs per-user audits, `--user` on restrict/freeze, and a
       `doctor` line for extra running users — plus a decision on whether
       Secure Folder stays warmed.
9. [ ] **ZeroTier: reconcile the docs and decide** — it is **not** "installed
       but not running": `dumpsys connectivity` shows NetworkAgentInfo VPN
       CONNECTED, `tun0 172.27.110.73/16`, `VpnTransportInfo{… sessionId=
       ZeroTier One}`, owner uid 10579, all uids routed, ~4.8% CPU in a 7 s
       sample. Either (a) promote it to the documented stable remote path (a
       fixed 172.27.x address beats the rotating 192.168.1.x + adb port), or
       (b) stop/freeze it deliberately. Not an accidental always-on VPN on a
       device holding secrets.
10. [ ] **Digest self-verification + job constraint rework** — job
        #u0a449/1001 is registered/PERSISTED with the digest.sh extra, but its
        constraint history shows `WITHIN_QUOTA` flipping and its state line says
        `Standby bucket: NEVER` while `am get-standby-bucket com.termux` = 5
        (exempted); its `Network: 107` is the ZeroTier VPN, so delivery depends
        on #9. "The daily digest is live" is currently unverified — have the
        digest write a dated marker we can read back, report last-run age in
        `doctor`, and re-think the constraints (`charging=false`,
        battery-not-low, 24 h period with flex=period).
11. [ ] **Tasker config backup + guard journal** — nothing verifies the guards
        exist or fire: Tasker's own run log's newest entry is **2024-10-06**
        (`/sdcard/Tasker/log/runlog.txt`), `/sdcard/Tasker/configs/user` is
        empty, and Tasker 6.7.9 was installed 2026-11-10 — the same update that
        wiped the guards last time. Schedule a config export, pull it into
        `~/phone-backups/` and version it in the repo; have each guard append
        one line to a log we can read ("guard fired at T, freed X").
12. [ ] **`phone listeners` — what the phone exposes** — `/proc/net/tcp{,6}` +
        nmap from the PC: 35303 open (uid 10092 `com.android.proxyhandler`),
        53601 open bound to 192.168.1.58 (uid 10246 GMS), 6300 bound 0.0.0.0
        (uid 1000) but not reachable from the LAN. Render uid→package, bind
        address, and an actual reachability test; flag anything on the LAN that
        isn't adb.
13. [ ] **`phone wifi-hygiene`** — 97 saved networks with auto-join, including
        "325 renovation Temp", "Barnhome HB", "Capital Grille Guest",
        "CoxWiFi", "Guest@OakCreekShoppingCenter", "MightyMorphinInternets*".
        List security/auto-join per network and prune the ones never chosen.
14. [ ] **Readable uid attribution + honest storage attribution** — (a) the top
        partial wakelock is `u0a687` 15m26s ×3 = `com.anthropic.claude` (then
        ch.protonmail u0a518, shealth u0a306, daemonapp u0a215, vending u0a249,
        gms u0a246); `drain`/`insights` should print `pkg (uid)` and rank
        background budget, not kernel threads. (b) `phone storage`: df, live
        per-package sizes, shared-dir du (/sdcard/Android 12.2 GB — obb 6.3,
        media 2.7, data 3.2; DCIM 3.6 GB), orphans (#7), and an explicit
        "unattributable /data remainder" (diskstats claims App Size 40.4 GB and
        is documented as untrustworthy).
15. [ ] **Persist the reversibility ledgers** — `bloat-strip`/`perf-fix`
        ledgers live in `$TMPDIR/ao-run/<serial>/`, which is scratch and
        pruned; the undo path for the 7 frozen packages currently expires with
        it. Move to a durable state dir and/or export the live
        frozen/restricted set on every apply.

Doc/reality drift found 2026-11-11 (fix as part of #3):
- ZeroTier is running as an always-on VPN (see #9).
- Digest delivery is unproven (see #10).
- Reversibility ledgers are ephemeral (see #15).
- Offline suite is **50 tests**, not the 32 recorded under "Shipped".
- Android user 150 (Secure Folder) exists and is running (see #8).

Known limits:
- Termux background survival depends on battery exemptions + wake-lock; not
  guaranteed by Android.
- Wireless-debugging ports rotate; `adb-wireless-setup.sh --reconnect` handles it.
- No local STT on-device (ctranslate2 has no android wheel) — voice is provider-side only.
