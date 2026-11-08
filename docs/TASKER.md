# Tasker integration

Two directions, both non-root.

## One-time Tasker setup

1. Install the **Termux:Tasker** plugin (F-Droid; match Termux's source).
2. Tasker: Preferences → **Allow External Access** ON. (Without this,
   `tasker-run` and `tasker-signal` silently do nothing.)
3. Grant Tasker the permission *Run commands in Termux environment*
   (Android Settings → Apps → Tasker → Permissions → Additional permissions).
4. Scripts live in `~/.termux/tasker/` (bootstrap installs them there).

## Direction 1 — Tasker runs Hermes

Add a Tasker action: **Plugin → Termux:Tasker**, set *Executable* to one of:

| Script | Purpose |
|---|---|
| `ask-hermes.sh` | ask on-device Hermes; answer lands in `%stdout` |
| `perf-guard.sh [--fix]` | run a perf check; notify on findings (`--fix` applies fixes) |
| `briefing.sh` | ask Hermes for a short phone-health digest → notification |
| `hermes-android-tasker.sh <sub>` | any toolkit command, e.g. `perf`, `bloat`, `insights` |

Pass inputs via the plugin *Arguments* field (comma-separated → `$1 $2 …`).
Read the result from Tasker's `%stdout` (put a **Notify** action after it).

Example profile: *Event → Power → Power Connected* → run `perf-guard.sh --fix`.

## Direction 2 — Hermes drives Tasker

- Run an existing task by name:
  `hermes-android tasker-run "Morning Report" [par1] [par2]`
  (uses `net.dinglisch.android.taskerm.ACTION_TASK`).
- Raise an event Tasker listens for:
  `hermes-android tasker-signal battery_low 15`
  then in Tasker: *Profile → Event → System → Intent Received*, Action
  `net.hermes.phone.EVENT`; inside the task match on `%event` / `%data`.
- Generate a task to import:
  ```
  hermes-android tasker-gen --name "Hermes Ask" \
    --intent net.dinglisch.android.taskerm.ACTION_TASK \
    --extras "task_name: Morning Report" --target 1 --out "Hermes Ask.tsk.xml"
  ```
  Import: long-press the **TASKS** tab → *Import Task*, pick the `.tsk.xml`.

## About generated XML

`tasker/gen_tsk.py` emits only **verified** action layouts — the arg order for
each action was taken from real Tasker exports, not guessed:

| code | action | args |
|---|---|---|
| 877 | Send Intent | `arg0` Action, `arg1` Cat, `arg2` Mime, `arg3` Data, `arg4` Extras ("k: v" lines), `arg7` Package, `arg8` Class, `arg9` Target (1=Activity) |
| 104 | Browse URL | `arg0` url, `arg1` App |
| 20 | Launch App | `arg0` App(appClass/appPkg/label), … |
| 30 | Wait | `arg0..arg4` Int |
| 123 | Run Shell | `arg0` command (root only) |

To support another action, add its builder + code to the `ACTION` table after
confirming the layout against a real export, then import-test once. Do not
invent codes.
