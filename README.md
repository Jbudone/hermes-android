# hermes-android

Give Hermes Agent hands on your Android phone: **detect & fix performance
issues, strip bloat, produce insights, and build Tasker automations** — non-root,
from a PC or from the phone itself.

> Status: the toolkit is built and its offline test suite passes
> (`bash test/run-tests.sh` → 24/24): shell syntax, the Tasker XML generator
> (validated against real Tasker exports), and the telemetry/inventory parsers
> against fixtures. It has **not** yet been run against a physical device from
> here — the on-device `collect` paths are standard `adb`/`pm`/`dumpsys`
> commands but should be confirmed with `hermes-android doctor` on the phone.

## Install

On the phone (Termux, from F-Droid):

```bash
bash bootstrap/termux-bootstrap.sh
```

That installs Hermes itself (from the Termux **canary** APT channel — the
`stable` channel is currently broken upstream and its index 404s — with a
from-source build as automatic fallback), this toolkit, the Termux:Tasker
scripts, and wires up the `hermes-android` command. Then:

```bash
hermes setup                                 # provider/model
bash bootstrap/adb-wireless-setup.sh         # give it shell powers (adb-to-self)
hermes-android doctor                        # verify
```

From a PC instead: you already have the repo; `export AO_ADB_SERIAL=<ip:port>`
after `bootstrap/adb-wireless-setup.sh --host <phone-ip>`.

## Use

```
hermes-android perf            # performance findings (HIGH/MED/LOW)
hermes-android perf-fix --dry-run
hermes-android bloat           # bloat + unused apps
hermes-android bloat-strip --dry-run
hermes-android insights        # battery / wakelocks / storage
hermes-android tasker-run "Task Name"
hermes-android tasker-signal EVT data
hermes-android tasker-gen --name "X" --url https://example.com --out x.tsk.xml
```

Or just talk to Hermes: the `android-phone-ops` skill teaches it the workflow,
so "find what's slowing my phone down and fix it" runs `perf`, reads the
evidence, and applies safe fixes.

## Layout

```
bin/hermes-android          dispatcher (single entry point)
lib/android-ops.sh          adb privilege layer + shared helpers
commands/                   doctor, perf(-report/-fix), bloat(-audit/-strip), insights, tasker-run/-signal
tasker/gen_tsk.py           .tsk.xml generator (verified action layouts only)
tasker/termux-scripts/      scripts for the Tasker → Termux direction
bootstrap/                  on-device installer + adb pairing helper
skills/android-phone-ops/   Hermes skill that drives all of it
docs/                       ARCHITECTURE, PAIRING, TASKER, ROOT, ROADMAP
test/                       offline suite + fixtures
```

## Safety model

- Everything privileged goes through `adb shell` (the `shell` UID); bare Termux
  cannot reach those services anyway.
- `bloat-strip` and `perf-fix` are **dry-run by default**, journal every change
  to a ledger, refuse a hard blocklist of critical packages, and are reversible
  (`bloat-strip --restore <ledger>`; freeze = `pm enable`, remove = `cmd package
  install-existing`).
- Generated Tasker XML uses only action layouts verified against real exports.

See `docs/HANDOFF.md` first in a new session; `docs/` has the full picture.
