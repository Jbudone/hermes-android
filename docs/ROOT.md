# What root would add

The toolkit is deliberately non-root and already covers the five asks via
`adb shell`. Root (Magisk / KernelSU) is optional and upgrades specific things:

| Capability | non-root (now) | with root |
|---|---|---|
| CPU/mem/thermal read | `dumpsys`, `/proc` via adb | direct `/sys/class/thermal`, `/proc` |
| Bloat freeze/remove | `pm disable-user`, `pm uninstall --user 0` | also remove for all users, edit `/system` |
| Kernel/VM tunables | not writable | `sysctl`, governor, `vm.*` |
| Deep clean | app caches only | `/data` scans, stale files |
| Live system edits | none | mount `/system` rw, debloat ROM |
| Automation reach | adb + Tasker | full device control, Magisk modules |

The library already has `ao_have_root` / `ao_root`; individual actions can use
root when present and degrade to the non-root path otherwise. To adopt root
later, no rearchitecture is needed — add root branches to specific actions.

Do not enable root just for this. Enable it if you want ROM-level debloating or
kernel tuning, and understand the security trade-off (an unlocked bootloader and
rooted device weaken the platform's protections).
