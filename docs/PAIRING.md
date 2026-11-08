# Connecting Hermes to the phone

The toolkit talks to Android over `adb`. Three routes, pick one:

## A. USB (simplest, from this PC)

1. Phone: Settings → About → tap *Build number* ×7 → Developer options → USB debugging ON.
2. Plug in USB, `adb devices` → authorise the RSA prompt on the phone.
3. `hermes-android doctor` should now see the device.

## B. Wireless, driving the phone FROM this PC

1. Phone: Developer options → **Wireless debugging** ON.
2. Run `bootstrap/adb-wireless-setup.sh --host <phone-lan-ip>`.
   Enter the *pairing* port + 6-digit code, then the *connect* port
   (the two ports differ — the pairing dialog shows one, the main screen the other).
3. Export the target so every command uses it:
   `export AO_ADB_SERIAL=<ip>:<connect-port>`

## C. On the phone itself (Termux, adb-to-self) — recommended for autonomy

This makes the phone self-sufficient: Hermes runs in Termux and drives itself.

1. Install Termux (F-Droid), then `bash bootstrap/termux-bootstrap.sh`.
2. In Termux: `pkg install android-tools` (bootstrap does it).
3. Phone: Developer options → **Wireless debugging** ON.
4. `bash bootstrap/adb-wireless-setup.sh` (host defaults to `127.0.0.1`).
   Enter the pairing port+code and the connect port.
5. The toolkit auto-detects the `localhost:*` target, so `hermes-android`
   commands just work with no env var.

Wireless-debugging ports change every time it is toggled. Reconnect with:
`bash bootstrap/adb-wireless-setup.sh --reconnect`

## Keeping it alive (Android fights background work)

Android may suspend or kill Termux. Mitigations, strongest first:

- Battery: exempt both **Termux** and **Tasker** from optimisation
  (`adb shell cmd deviceidle whitelist +com.termux`).
- Hold a wake lock while working: `termux-wake-lock` (and `termux-wake-unlock`).
  The gateway can run under it: see below.
- Relax phantom-process killing (optional, costs a little battery):
  `adb shell settings put global settings_enable_monitor_phantom_procs false`
  — `adb-wireless-setup.sh --persist` does this.

## Gateway (ask Hermes from the phone, or remotely)

The Termux install has no systemd. Run the gateway in a session:

```bash
termux-wake-lock
mkdir -p "${HERMES_HOME:-$HOME/.hermes}/logs"
nohup hermes gateway run >> "${HERMES_HOME:-$HOME/.hermes}/logs/gateway.log" 2>&1 &
```

Then connect a messaging platform (e.g. Telegram) with `hermes setup` so you
can message Hermes from anywhere. Token-gate any local HTTP surface: on
Android, `127.0.0.1` is reachable by any app with network permission.
