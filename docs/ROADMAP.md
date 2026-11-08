# Roadmap

Shipped (v1):
- [x] Privilege layer (`lib/android-ops.sh`) with PC + adb-to-self target resolution
- [x] perf report / fix, bloat audit / strip, insights, doctor
- [x] Tasker bridge both ways + verified `.tsk.xml` generator
- [x] Termux bootstrap + wireless-adb pairing helper
- [x] `android-phone-ops` skill + offline test suite

Next, in priority order:
- [ ] On-device first-run validation log (fill `docs/VALIDATION.md` from a real phone)
- [ ] Scheduled autonomy: a Hermes cron on the phone that runs `perf`/`insights`
      nightly and messages a digest via the gateway
- [ ] `bloat-strip --plan` from a saved JSON (audit → review → apply in one flow)
- [ ] gfxinfo frame-time analysis (per-app jank %, not just crash/ANR counts)
- [ ] Tasker presets: common generated tasks (battery-low, home-wifi, charger) as
      first-class `tasker-gen --preset` outputs
- [ ] Root upgrade path wired into specific actions behind `ao_have_root`

Known limits:
- Termux background survival depends on battery exemptions + wake-lock; not
  guaranteed by Android.
- Wireless-debugging ports rotate; `adb-wireless-setup.sh --reconnect` handles it.
- No local STT on-device (ctranslate2 has no android wheel) — voice is provider-side only.
