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
   **The phone must be joined to a Wi-Fi network to pair** (internet is not
   required — a hotspot or an offline router works). On mobile data only,
   `adb pair` fails at the protocol level.
   **VPNs break this.** ZeroTier / Tailscale / WireGuard make Android advertise
   and bind adbd + the pairing server to the VPN interface (e.g. `172.27.x.x`),
   and `adb pair` then fails at the handshake even though the port looks open.
   Turn the VPN off while pairing/connecting.
4. `bash bootstrap/adb-wireless-setup.sh` — paste the **two full addresses** it
   asks for, exactly as the phone shows them:
   - the pairing dialog's `IP:port` + the 6-digit code
   - the main screen's `IP:port` (the connect address)
   Use the IP the phone shows (`172.27.x.x`, `192.168.x.x`, …) — **not**
   `127.0.0.1`. The pairing server binds to that interface, so loopback fails.
5. The toolkit auto-detects the single connected `IP:port` target, so
   `hermes-android` commands just work with no env var.

Wireless-debugging ports change every time it is toggled. Reconnect with:
`bash bootstrap/adb-wireless-setup.sh --reconnect`

### If `adb pair` keeps failing with `protocol fault …: Success`

That is stale pairing/TLS state on the phone (a fresh code + correct ports still
fail, and even a plain `adb connect` from another machine fails while the TCP
port is open). Reset it:

1. Developer options → turn **Wireless debugging OFF**.
2. **Reboot the phone** (this clears the stale pairing state).
3. Turn Wireless debugging ON, open *Pair device with pairing code*.
4. Run the script again (it now restarts the adb server first).

Keep the phone unlocked during pairing.

### D. Reuse an already-authorised key (bypasses pairing entirely)

If `adb pair` fails no matter what — the ADB **35.x** client in Termux
(`android-tools 35.0.2`) does this on some devices — do not fight it. adb
authorisation is **key-based**, so any client holding a key the phone already
trusts can connect without pairing:

1. Over USB, authorise this PC (`adb devices` → Allow).
2. Copy the key into Termux's store:
   ```
   adb push ~/.android/adbkey     /sdcard/Download/.hkey/adbkey
   adb push ~/.android/adbkey.pub /sdcard/Download/.hkey/adbkey.pub
   ```
   then in Termux:
   ```
   mkdir -p ~/.android
   cp /sdcard/Download/.hkey/adbkey ~/.android/adbkey
   cp /sdcard/Download/.hkey/adbkey.pub ~/.android/adbkey.pub
   chmod 600 ~/.android/adbkey
   rm -rf /sdcard/Download/.hkey      # do not leave a private key on /sdcard
   ```
3. Ensure wireless debugging is on (from the PC, no tapping needed):
   `adb shell settings put global adb_wifi_enabled 1`
4. Connect — the port rotates, so let mDNS find it: `phone connect`

Termux needs "All files access" to read `/sdcard`; grant it with
`adb shell appops set com.termux MANAGE_EXTERNAL_STORAGE allow`.

After this, the phone drives itself over `127.0.0.1:<port>` with no PC.

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
