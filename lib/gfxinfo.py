#!/usr/bin/env python3
"""gfxinfo — parse `dumpsys gfxinfo` into per-app frame statistics.

`dumpsys gfxinfo` (no package) emits one block per rendering process:

    ** Graphics info for pid 3914 [com.android.systemui] **

    Stats since: 22644525970110ns
    Total frames rendered: 9868
    Janky frames: 2861 (28.99%)
    ...
    99th percentile: 200ms
    Number Missed Vsync: 885
    Number High input latency: 7460
    Number Slow UI thread: 2436
    ...

Blocks whose process has no attached window (common: background processes)
carry no frame counters and are skipped. Several blocks can share a package
(systemui, providers, split app processes), so results are aggregated per
package: frame counts are summed and percentile lines keep the worst value
seen for that package.

Used by commands/jank-report.sh and commands/perf-report.sh, and unit-tested
offline against test/fixtures/gfxinfo/gfxinfo.txt.
"""
import json
import re
import sys

HDR = re.compile(r"^(\d+) \[(.+?)\] \*\*$")
PERCENTILES = ("50", "90", "95", "99")
COUNTERS = {
    "janky": r"Janky frames: (\d+) \(([\d.]+)%\)",
    "legacy": r"Janky frames \(legacy\): (\d+) \(([\d.]+)%\)",
    "missed_vsync": r"Number Missed Vsync: (\d+)",
    "high_input": r"Number High input latency: (\d+)",
    "slow_ui": r"Number Slow UI thread: (\d+)",
    "slow_upload": r"Number Slow bitmap uploads: (\d+)",
    "slow_draw": r"Number Slow issue draw commands: (\d+)",
    "deadline": r"Number Frame deadline missed: (\d+)",
    "deadline_legacy": r"Number Frame deadline missed \(legacy\): (\d+)",
}


def _ms(line):
    m = re.search(r"(\d+(?:\.\d+)?)\s*ms", line)
    return float(m.group(1)) if m else None


def parse(text):
    """Yield one dict per rendering process that actually drew frames."""
    blocks = re.split(r"(?m)^\*\* Graphics info for pid ", text)[1:]
    for block in blocks:
        lines = block.splitlines()
        m = HDR.match(lines[0])
        if not m:
            continue
        pid, pkg = int(m.group(1)), m.group(2)
        # Frame stats sit before the View hierarchy / window dump; anything
        # after it ("Window", "View hierarchy", PROFILEDATA rows) is noise.
        stop = len(lines)
        for i, l in enumerate(lines[1:], 1):
            s = l.strip()
            if s.startswith(("View hierarchy:", "Window", "---PROFILEDATA---")):
                stop = i
                break
        head = lines[1:stop]
        total = None
        rec = {"pid": pid, "package": pkg}
        for l in head:
            s = l.strip()
            if s.startswith("Total frames rendered:"):
                mm = re.search(r"(\d+)", s)
                total = int(mm.group(1)) if mm else None
            elif s.startswith("Stats since:"):
                continue
            elif s.startswith(tuple(f"{p}th percentile:" for p in PERCENTILES)):
                p = s.split("th", 1)[0]
                rec["p" + p] = _ms(s)
            elif s.startswith("50th gpu percentile:"):
                rec["gpu_p50"] = _ms(s)
            elif s.startswith("90th gpu percentile:"):
                rec["gpu_p90"] = _ms(s)
            else:
                for key, pat in COUNTERS.items():
                    mm = re.match(pat, s)
                    if mm:
                        rec[key] = int(mm.group(1))
                        break
        rec["frames"] = total
        if not total:  # no window / never drew: not a jank signal
            continue
        yield rec


def aggregate(procs):
    """Fold several processes of the same package into one row."""
    apps = {}
    for r in procs:
        a = apps.setdefault(r["package"], {
            "package": r["package"], "pids": [], "frames": 0, "janky": 0,
            "legacy": 0, "missed_vsync": 0, "high_input": 0, "slow_ui": 0,
            "slow_upload": 0, "slow_draw": 0, "deadline": 0,
            "deadline_legacy": 0, "p50": None, "p90": None, "p95": None,
            "p99": None, "gpu_p50": None, "gpu_p90": None,
        })
        a["pids"].append(r["pid"])
        for k in ("frames", "janky", "legacy", "missed_vsync", "high_input",
                  "slow_ui", "slow_upload", "slow_draw", "deadline",
                  "deadline_legacy"):
            a[k] += r.get(k) or 0
        for k in ("p50", "p90", "p95", "p99", "gpu_p50", "gpu_p90"):
            v = r.get(k)
            if v is not None and (a[k] is None or v > a[k]):
                a[k] = v
    for a in apps.values():
        f = a["frames"] or 0
        a["janky_pct"] = round(a["janky"] * 100.0 / f, 2) if f else 0.0
        a["slow_ui_pct"] = round(a["slow_ui"] * 100.0 / f, 2) if f else 0.0
    return sorted(apps.values(), key=lambda a: (-a["janky"], -a["frames"]))


def severity(app, min_frames):
    """HIGH/MED/LOW from jank share, guarded by a frame-count floor."""
    if app["frames"] < min_frames:
        return "LOW"
    pct = app["janky_pct"]
    if pct >= 25:
        return "HIGH"
    if pct >= 10:
        return "MED"
    return "LOW"


def findings(apps, min_frames):
    """`sev|JANK|message` lines, one per notable app (worst first)."""
    out = []
    for a in apps:
        sev = severity(a, min_frames)
        if sev == "LOW":
            continue
        why = []
        if a["slow_ui"]:
            why.append("%.0f%% slow UI thread" % a["slow_ui_pct"])
        if a["missed_vsync"]:
            why.append("%d missed vsync" % a["missed_vsync"])
        if a["slow_draw"]:
            why.append("%d slow draw cmds" % a["slow_draw"])
        detail = (" (" + ", ".join(why) + ")") if why else ""
        out.append("%s|JANK|%s: %.1f%% of %d frames janky, p95 %sms%s" % (
            sev, a["package"], a["janky_pct"], a["frames"],
            ("%g" % a["p95"]) if a["p95"] is not None else "?", detail))
    return out


def _fmt(v):
    return "-" if v is None else ("%gms" % v)


def main(argv):
    import argparse
    ap = argparse.ArgumentParser(description="analyse `dumpsys gfxinfo` output")
    ap.add_argument("--file", required=True, help="saved dumpsys gfxinfo output")
    ap.add_argument("--min-frames", type=int, default=200,
                    help="ignore apps below this frame count (default 200)")
    ap.add_argument("--top", type=int, default=15)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--findings", action="store_true",
                    help="emit sev|area|message lines for perf-report")
    args = ap.parse_args(argv)

    text = open(args.file, encoding="utf-8", errors="replace").read()
    apps = aggregate(parse(text))
    notable = [a for a in apps if a["frames"] >= args.min_frames]

    if args.findings:
        for line in findings(apps, args.min_frames):
            print(line)
        return 0
    if args.json:
        print(json.dumps({
            "file": args.file, "min_frames": args.min_frames,
            "apps": apps, "notable": notable,
            "summary": {"apps": len(apps), "notable": len(notable),
                        "frames": sum(a["frames"] for a in apps),
                        "janky": sum(a["janky"] for a in apps)},
        }, indent=2))
        return 0

    if not apps:
        print("  (no frame stats — is the screen off or the device idle?)")
        return 0
    print("Per-app frame stats (min %d frames) — %d apps, %d frames total"
          % (args.min_frames, len(notable), sum(a["frames"] for a in apps)))
    print("─" * 92)
    print("  %-44s %8s %7s %6s %6s %6s %5s" %
          ("app", "frames", "janky", "p50", "p95", "p99", "sev"))
    for a in notable[:args.top]:
        print("  %-44s %8d %6.1f%% %6s %6s %6s %5s" % (
            a["package"][:44], a["frames"], a["janky_pct"],
            _fmt(a["p50"]), _fmt(a["p95"]), _fmt(a["p99"]),
            severity(a, args.min_frames)))
    if not notable:
        print("  (every app is below the frame floor — nothing to rank)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))