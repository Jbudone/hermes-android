# Architecture

```
                 ┌─────────────────────────────────────────────┐
                 │                THE PHONE                     │
                 │                                              │
   "ask Hermes"  │  Termux                                      │
   ─────────────►│   ├─ hermes (from-source, on-device)         │
     (Telegram   │   │    └─ skill: android-phone-ops           │
      gateway)   │   ├─ ~/hermes-android   (this toolkit)      │
                 │   ├─ ~/.termux/tasker/*.sh  ◄── Termux:Tasker│◄──┐
                 │   └─ android-tools: adb ─┐                   │   │
                 │                           ▼                  │   │
                 │                    adb shell @ localhost:PORT │   │
                 │                           │  (wireless debug) │   │
                 │                           ▼                  │   │
                 │        Android system: pm / cmd / dumpsys /  │   │
                 │        settings / am      (shell UID)        │   │
                 └─────────────────────────────────────────────┘   │
                              ▲                                    │
                              │ adb (USB or wireless, LAN)         │ Tasker
                 ┌────────────┴──────────────┐                     │ plugin
                 │        THIS PC            │            ┌────────┴───────┐
                 │  hermes (desktop)         │            │    Tasker      │
                 │   └─ same toolkit         │  am broadcast           │
                 │       (AO_ADB_SERIAL=…)   │───────────► ACTION_TASK   │
                 └───────────────────────────┘            │ Intent Received│
                                                          └───────────────┘
```

## Layers

1. **Privilege layer** — `lib/android-ops.sh`. All privileged work goes through
   `adb shell` (the `shell` UID), never bare Termux. One resolver picks the
   adb target so the same commands work from a PC or from the phone.

2. **Capability layer** — `commands/*.sh`. Collection is split from analysis:
   raw `dumpsys`/`pm` output is written to a run dir, then parsed. That makes
   every parser unit-testable offline against fixtures (`test/fixtures`).

3. **Automation layer** — Tasker, two directions:
   - **Tasker → Termux:** Termux:Tasker plugin runs scripts in `~/.termux/tasker/`.
   - **Hermes → Tasker:** `tasker-run` (external-access intent) and
     `tasker-signal` (Intent Received event), plus `tasker-gen` for `.tsk.xml`.

## Why non-root is enough

`adb shell` already holds the permissions that matter for performance, debloat
and diagnostics: `pm`, `cmd appops`, `cmd package compile`, `dumpsys`,
`settings put/delete`, `am`. Root adds direct `/sys` and `/proc` writes and
full `pm` control, but is not required for the five asks. The toolkit is written
so that adding root later (`ao_root`) upgrades individual actions in place.
