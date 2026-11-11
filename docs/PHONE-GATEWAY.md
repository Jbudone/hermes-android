# Phone messaging gateway (drive the phone from Telegram)

Goal: run Hermes's messaging gateway **on the phone** so you can drive it from
Telegram with no laptop. The token is entered **on the device** and never
pasted into a Hermes chat.

## Prerequisites

- A Telegram bot: message **@BotFather** → `/newbot` → copy the token.
  Keep it out of any chat; you'll paste it on the phone.

## Steps (run in Termux on the phone)

1. Configure the platform (interactive wizard; it stores credentials in
   `~/.hermes/.env` on the device):

   ```bash
   hermes gateway setup
   ```

   Choose **Telegram** and paste the bot token when prompted.

2. Confirm it registered:

   ```bash
   hermes gateway status
   ```

3. Test it in the foreground, then message the bot:

   ```bash
   hermes gateway
   ```

   Ctrl-C to stop once it replies.

4. Keep it running in the background. Android suspends Termux, so take a
   wake-lock first:

   ```bash
   termux-wake-lock
   hermes gateway >~/.hermes/logs/gateway.out 2>&1 &
   ```

   Note: Termux has **no systemd/launchd**, so `hermes gateway install`
   (the Linux service path) does not apply on the phone.

5. Start it at boot. Install **Termux:Boot** (F-Droid) and drop a script in
   `~/.termux/boot/` that runs `termux-wake-lock` then `hermes gateway &`.
   (Alternatively extend the `Agent Keepalive` Tasker task with a plugin action
   running `hermes-android-tasker.sh` and a new `gateway` subcommand.)

## Security notes

- The gateway is a **remote-control surface for the whole phone** — anyone who
  can talk to the bot can run tools on it. Keep the token secret.
- Restrict the bot to your own Telegram user id (allowlist) so a leaked bot
  link isn't enough to drive the device.
- The phone is not rooted; the gateway runs as the Termux user, so privileged
  ops still go through `adb shell` (see the `android-phone-ops` skill).

## Verify

Message the bot from your phone; the gateway should reply. `hermes gateway
status` reports the running state and any degraded/heartbeat warnings.
