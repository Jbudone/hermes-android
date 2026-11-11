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
- [~] Tasker guards for instant reactions. Guard 1 (`Battery Low Guard` +
      profile `*Battery Level 0, 15`) **rebuilt and verified** this session
      (plugin runs, both actions green, profile attached + enabled). Guard 2
      (charger) is half-built — finish it, then extend.
      Note: the previous session's guards were lost when Tasker updated
      6.7.8 → 6.7.9; rebuild done from `docs/TASKER-RECIPES.md`.

Next — prioritized improvement plan (execute in this order):

1. [x] systemui jank — investigated and reframed. Windowed sample is ~10–11%
       janky / p95 34 ms on a 120 Hz panel; the 29% "HIGH" was cumulative
       since boot, not steady-state. Animations already at 0.5; set
       `accessibility_reduce_transparency=1` (small win: systemui 11.5→10.7%,
       launcher 11→9.1%). **Real sustained drain found instead: AirDroid
       (`com.sand.airdroid` + `:push`) ≈9% CPU (~1 h CPU each since boot) and
       2.5 GB swap in use (MemAvailable ~2.9 GB of 7.2 GB).**
       Follow-ups: decide AirDroid (restrict / freeze / remove — user's app,
       also a remote-access privacy surface) and relieve memory pressure.
2. [ ] Reclaim ~6 GB: telephony provider (~3.2 GB), Messages (~3.1 GB),
       YouTube cache (~2 GB). Back up threads first; destructive, needs sign-off.
3. [ ] Finish + extend Tasker guards: charger pair (`perf-guard.sh --fix`),
       plus a screen-off / periodic `perf-guard` to catch regressions.
4. [ ] Harden on-device agent background survival: `termux-wake-lock`,
       battery-optimisation exemption for Termux + Tasker, keep the digest on
       `termux-job-scheduler`, add a watchdog that logs agent death.
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
