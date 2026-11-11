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
- [~] Tasker profiles for instant reactions — bridge unblocked (RUN_COMMAND
      granted + plugin launched once, see `docs/HANDOFF.md`); task
      `Battery Low Guard` built and running, profile `Battery Level 0, 15`
      created; **still to do**: attach task → profile, enable it, then the
      charger-state pair. Recipes corrected to State → Power contexts.

Next:
- [ ] Optional: messaging gateway on the phone so it can be driven from Telegram
- [ ] Optional: clear telephony/messages data (~6 GB) if the user agrees

Known limits:
- Termux background survival depends on battery exemptions + wake-lock; not
  guaranteed by Android.
- Wireless-debugging ports rotate; `adb-wireless-setup.sh --reconnect` handles it.
- No local STT on-device (ctranslate2 has no android wheel) — voice is provider-side only.
