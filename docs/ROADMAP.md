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

Next:
- [ ] Tasker profiles for instant reactions (battery low, charger connected) —
      UI taps only; see `docs/TASKER-RECIPES.md`
- [ ] Optional: messaging gateway on the phone so it can be driven from Telegram
- [ ] Optional: clear telephony/messages data (~6 GB) if the user agrees
- [ ] gfxinfo frame-time analysis (per-app jank %, not just crash/ANR counts)
- [ ] `bloat-strip --plan` from a saved JSON (audit → review → apply in one flow)

Known limits:
- Termux background survival depends on battery exemptions + wake-lock; not
  guaranteed by Android.
- Wireless-debugging ports rotate; `adb-wireless-setup.sh --reconnect` handles it.
- No local STT on-device (ctranslate2 has no android wheel) — voice is provider-side only.
