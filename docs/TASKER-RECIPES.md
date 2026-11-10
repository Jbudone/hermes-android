# Tasker recipes

Prerequisites (one time):
- `Termux:Tasker` and `Termux:API` installed (F-Droid, same signing key as Termux).
- Tasker: **Preferences → Misc → Allow External Access** ON.
- Tasker granted *Run commands in Termux environment*
  (Android Settings → Apps → Tasker → Permissions → Additional permissions).
- `bash ~/hermes-android/bootstrap/termux-bootstrap.sh` has copied the scripts
  into `~/.termux/tasker/`:
  `ask-hermes.sh`, `perf-guard.sh`, `briefing.sh`, `hermes-android-tasker.sh`

A Tasker task that calls Termux is always the same shape:

    Action → Plugin → Termux:Tasker
      Executable: hermes-android-tasker.sh   (or another script from the list)
      Arguments:  <space-separated>          → $1 $2 … in the script
      (leave "Execute in terminal session" OFF so it runs in the background)
    Then: Action → Alert → Notify
      Text: %stdout                          (Termux:Tasker returns output here)

Because the plugin action's XML code is assigned per plugin instance, these are
built in the Tasker UI rather than generated. The scripts themselves are not.

---

## 1. Battery-low guard

Profile: **Event → Power → Battery Low** (or State → Power → Battery Level 0–15)
Task: `hermes-android-tasker.sh` with arguments `perf-fix --yes trim-caches kill-bg`

Frees caches and kills background work when the battery is nearly flat, so the
last few percent go to what you actually need.

## 2. Charger-triggered cleanup

Profile: **Event → Power → Power Connected**
Task: `perf-guard.sh` with arguments `--fix`

Runs a performance check on plug-in and applies the safe fixes; notifies only if
something is HIGH/MED. Pair with a "Power Disconnected" exit task if you want a
report before unplugging.

## 3. Morning briefing (insights + Hermes summary)

Profile: **Time → 07:30, repeat Mon–Fri**
Task: `briefing.sh` (no arguments), then **Alert → Notify** with text `%stdout`.

`briefing.sh` runs `hermes-android insights`, asks the on-device Hermes for the
three things worth attention, and posts it as a notification.

## 4. Ask Hermes from a home-screen widget

Tasker: **Task → Plugin → Termux:Tasker**, executable `ask-hermes.sh`,
arguments `what is eating my battery?` → `%stdout` holds the answer.
Add a **Tasker Widget** (Task Shortcut) to the home screen for one-tap access.

## 5. Hermes → Tasker (the other direction)

No plugin needed. From Hermes (on the phone or from the PC):

    hermes-android tasker-run "Movie Mode"        # run an existing Tasker task
    hermes-android tasker-signal battery_low 15   # raise an event

For the event, create **Profile → Event → System → Intent Received** with action
`net.hermes.phone.EVENT`, then match `%event` / `%data` inside the task.

---

## Useful one-liners inside a task

    hermes-android perf                    # full performance report
    hermes-android perf-fix --yes trim-caches kill-bg
    hermes-android bloat                   # what's big / unused
    hermes-android insights                # battery, wakelocks, storage
    phone shell "settings put global adb_wifi_enabled 1"

## Notes

- Android may kill background script runs; exempt both Termux and Tasker from
  battery optimisation (`adb shell cmd deviceidle whitelist +com.termux`).
- Keep an eye on `%err` / `%errmsg` in Tasker for plugin failures — they usually
  mean the RUN_COMMAND permission wasn't granted.
