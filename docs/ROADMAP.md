## Roadmap

Shipped:
- [x] Privilege layer (`lib/android-ops.sh`) with PC + adb-to-self target resolution
- [x] perf report / fix, bloat audit / strip, insights, doctor
- [x] Tasker bridge both ways + verified `.tsk.xml` generator
- [x] Termux bootstrap + wireless-adb pairing helper
- [x] `android-phone-ops` skill + offline test suite (32 tests)
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
5. [ ] Security cleanup of shared storage: move the Google OAuth
       `client_secret_*.json` out of `/sdcard/Download`, remove stray scripts,
       and decide the ZeroTier-vs-wireless-debugging policy (ZeroTier rebinds
       wireless debugging and breaks pairing).
6. [ ] Remote-control path with no laptop: run the Hermes gateway on the phone
       (drive from Telegram) + reboot-surviving key-based wireless adb with a
       reconnect helper (`docs/PAIRING.md`).

Known limits:
- Termux background survival depends on battery exemptions + wake-lock; not
  guaranteed by Android.
- Wireless-debugging ports rotate; `adb-wireless-setup.sh --reconnect` handles it.
- No local STT on-device (ctranslate2 has no android wheel) — voice is provider-side only.
