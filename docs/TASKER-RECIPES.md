# Tasker recipes

Prerequisites (one time):
- `Termux:Tasker` and `Termux:API` installed (F-Droid, same signing key as Termux).
- Tasker: **Preferences → Misc → Allow External Access** ON.
- Tasker granted *Run commands in Termux environment* — from adb this is:
  `adb shell pm grant net.dinglisch.android.taskerm com.termux.permission.RUN_COMMAND`
  (the permission is protectionLevel=dangerous, so a plain `pm grant` works and
  persists). Without it every plugin action fails with
  *"plugin error: missing, disabled, not exported or no permission receiver"*.
- Launch `Termux:Tasker` once
  (`adb shell am start -n com.termux.tasker/.activities.TermuxTaskerLauncherActivity`).
  A freshly installed plugin sits in Android's *stopped* state and a stopped
  package's receivers never get broadcasts — the same plugin error above.
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

**Use the State contexts, not the Events.** On Tasker 6.7.8 / Android 16 the
Power *event* list only has Battery Changed, Battery Full and Battery
Overheating — there is no "Battery Low" and no "Power Connected" event any more.
The recipes below use *State → Power*, which is present and behaves as the
trigger.

## 1. Battery-low guard

Profile: **State → Power → Battery Level**, From `0` To `15`
Task: `hermes-android-tasker.sh` with arguments `perf-fix --yes trim-caches kill-bg`
Timeout on the plugin action: **120 s** (expand the Timeout slider into a text
field and type it — the plugin's "Wait for result" needs timeout > 0, and the
default 10 s can cut `trim-caches` off).
Then: **Alert → Notify**, title e.g. `Battery Low Guard`, text `%stdout`.

Frees caches and kills background work when the battery is nearly flat, so the
last few percent go to what you actually need.

## 2. Charger-triggered cleanup

Profile: **State → Power → Power** (i.e. plugged in)
Task: `perf-guard.sh` with arguments `--fix`
Then: **Alert → Notify** with text `%stdout` if you want the report on screen.

Runs a performance check on plug-in and applies the safe fixes; notifies only if
something is HIGH/MED.

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

## 6. Scheduled digest without Tasker (no UI at all)

Tasker is not required for the periodic case. `termux-job-scheduler` (from
Termux:API) runs a script on a schedule, survives reboots (`--persisted true`)
and needs no plugin config:

```
termux-job-scheduler \
  --script "$HOME/.termux/tasker/digest.sh" \
  --period-ms 86400000 --persisted true --network any --job-id 1001
termux-job-scheduler --pending     # confirm
```

`digest.sh` runs `hermes-android perf`, keeps the HIGH/MED lines and posts them
as a `hermes-digest` notification. Cancel with
`termux-job-scheduler --cancel --job-id 1001`.

Android's floor for periodic jobs is ~15 min, so this is for digests/guards, not
instant reactions. For instant event reactions (charger plugged, battery low)
Tasker is the right tool — that is what recipes 1 and 2 are for.

---

## Useful one-liners inside a task

    hermes-android perf                    # full performance report
    hermes-android perf-fix --yes trim-caches kill-bg
    hermes-android bloat                   # what's big / unused
    hermes-android insights                # battery, wakelocks, storage
    phone shell "settings put global adb_wifi_enabled 1"

## Driving the Tasker UI over adb (no hands)

The whole recipe is doable with `adb shell input` — screenshots are the
feedback loop (`adb exec-out screencap -p > s.png`, then look at it), and taps
use **full-resolution** coordinates (a 1080x2316 screen: a coordinate read off a
half-size screenshot must be doubled). What actually bit:

- **Space is `%s`** in `input text`, and there is **no way to type a literal
  `%`** — `input text "%stdout"` arrives as `" tdout"`. For Tasker variables use
  the field's **variable-pick (tag) icon** and tap the entry in the list.
- **Text entry**: tap the field, then `input text`, then `input keyevent 111`
  (ESC) to hide the keyboard so the row's own buttons are reachable again.
- Clearing a field: `input keyevent 123` (move to end) then a burst of
  `input keyevent 67` (DEL).
- Name-entry dialogs confirm on the **✓ at the right of the field row**, not the
  keyboard's ✓; a mid-row tap silently cancels and the new task is discarded.
- Numeric rows (e.g. Timeout) have an **expand icon** on the header row that
  turns the slider into a text field; drag-to-max means *Never*.
- The action picker's Filter box switches the dialog into a tile view — type e.g.
  `Termux` or `Notify` and tap the tile.
- Run a task from Task Edit with ▶ (bottom-left) to test; the action shows a
  **green dot** on success, which is how the plugin bridge was verified.

## Notes

- Android may kill background script runs; exempt both Termux and Tasker from
  battery optimisation (`adb shell cmd deviceidle whitelist +com.termux`).
- Keep an eye on `%err` / `%errmsg` in Tasker for plugin failures — they usually
  mean the RUN_COMMAND permission wasn't granted.
