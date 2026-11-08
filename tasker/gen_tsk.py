#!/usr/bin/env python3
"""gen_tsk.py — generate importable Tasker .tsk.xml task files.

Why this exists: Hermes can author Tasker automation for you. Rather than
guess at Tasker's XML, this generator only emits actions whose on-disk XML
layout is VERIFIED against real Tasker exports (see ACTION registry below).

Verified actions (from real Tasker 4.8/6.3 exports):
  877  Send Intent    arg0 Action, arg1 Cat(Int), arg2 MimeType, arg3 Data,
                      arg4 Extras("k: v" lines), arg5/6 unused,
                      arg7 Package, arg8 Class, arg9 Target(Int)
  104  Browse URL     arg0 url(Str), arg1 App
   20  Launch App     arg0 App(appClass/appPkg/label), arg1 Str "", arg2/3 Int
   30  Wait           arg0..arg4 Int
  123  Run Shell      arg0 command(Str), arg1/2 Int, arg3/4/5 Str   (root only)

Anything else: add an ACTION entry + a builder, then import-test once.

Usage:
  gen_tsk.py --name "Hermes Ask" \
      --intent net.dinglisch.android.taskerm.ACTION_TASK \
               --extras "task_name: My Task" --target 1 \
      --out "Hermes Ask.tsk.xml"

  gen_tsk.py --name "Open site" --url https://example.com --wait 3
  gen_tsk.py --list-actions
  gen_tsk.py --spec spec.json --out out.tsk.xml
"""
import argparse, json, sys, time
from xml.etree import ElementTree as ET

TASKER_TV = "6.3.13"  # import is version-tolerant; this mirrors a real export


def _el(tag, **attrs):
    return ET.Element(tag, {k: str(v) for k, v in attrs.items()})


def el_str(sr, val):
    e = _el("Str", sr=sr, ve=3); e.text = val; return e


def el_int(sr, val):
    return _el("Int", sr=sr, val=val)


def el_app(sr, pkg="", cls="", label=""):
    e = _el("App", sr=sr)
    ET.SubElement(e, "appClass").text = cls
    ET.SubElement(e, "appPkg").text = pkg
    ET.SubElement(e, "label").text = label
    return e


# ---------------------------------------------------------------- action builders
# Each returns the list of argument child-elements (after <code>).
def build_send_intent(a):
    raw = a.get("extras") or []
    norm = []
    if isinstance(raw, dict):
        norm = list(raw.items())
    else:
        for item in raw:
            if isinstance(item, (list, tuple)) and len(item) == 2:
                norm.append((str(item[0]), str(item[1])))
            else:
                k, _, v = str(item).partition(":")
                norm.append((k.strip(), v.strip()))
    extras_str = "\n".join("%s: %s" % (k, v) for k, v in norm)
    return [
        el_str("arg0", a["action"]),
        el_int("arg1", int(a.get("cat", 0))),
        el_str("arg2", a.get("mime", "")),
        el_str("arg3", a.get("data", "")),
        el_str("arg4", extras_str),
        el_str("arg5", ""),
        el_str("arg6", ""),
        el_str("arg7", a.get("package", "")),
        el_str("arg8", a.get("class", "")),
        el_int("arg9", int(a.get("target", 1))),  # 1 = Activity (verified); Broadcast/Service unverified
    ]


def build_browse_url(a):
    return [el_str("arg0", a["url"]), el_app("arg1")]


def build_launch_app(a):
    pkg = a["package"]
    return [el_app("arg0", pkg=pkg, cls=a.get("class", ""), label=a.get("label", pkg)),
            el_str("arg1", ""), el_int("arg2", 0), el_int("arg3", 0)]


def build_wait(a):
    return [el_int("arg0", 0), el_int("arg1", int(a.get("seconds", 1))),
            el_int("arg2", 0), el_int("arg3", 0), el_int("arg4", 0)]


def build_run_shell(a):
    return [el_str("arg0", a["command"]), el_int("arg1", 0), el_int("arg2", 0),
            el_str("arg3", ""), el_str("arg4", ""), el_str("arg5", "")]


ACTION = {
    "send_intent": (877, build_send_intent),
    "browse_url":  (104, build_browse_url),
    "launch_app":  (20, build_launch_app),
    "wait":        (30, build_wait),
    "run_shell":   (123, build_run_shell),
}


def make_action(index, kind, params):
    if kind not in ACTION:
        raise SystemExit("unknown action kind %r (see --list-actions)" % kind)
    code, builder = ACTION[kind]
    act = _el("Action", sr="act%d" % index, ve=7)
    c = ET.SubElement(act, "code"); c.text = str(code)
    for child in builder(params):
        act.append(child)
    return act


def build_task(name, actions, task_id=None):
    task_id = task_id or (int(time.time()) % 1_000_000 + 1000)
    now_ms = int(time.time() * 1000)
    root = _el("TaskerData", sr="", dvi=1, tv=TASKER_TV)
    task = ET.SubElement(root, "Task", sr="task%d" % task_id)
    for tag, text in (("cdate", now_ms), ("edate", now_ms), ("id", task_id),
                      ("nme", name), ("pri", 1000)):
        ET.SubElement(task, tag).text = str(text)
    for i, (kind, params) in enumerate(actions):
        task.append(make_action(i, kind, params))
    ET.indent(root, space="  ")
    return root


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--name", help="Tasker task name")
    p.add_argument("--out", "-o", default="-", help="output .tsk.xml (default stdout)")
    p.add_argument("--id", type=int, help="explicit Tasker task id")
    p.add_argument("--spec", help="JSON spec file: {\"name\":..,\"actions\":[[kind,{..}],..]}")
    p.add_argument("--list-actions", action="store_true")
    # convenience single/multi action flags (repeatable)
    p.add_argument("--intent", help="Send Intent: the intent action string")
    p.add_argument("--data", default="")
    p.add_argument("--package", default="")
    p.add_argument("--class", dest="klass", default="")
    p.add_argument("--mime", default="")
    p.add_argument("--target", type=int, default=1)
    p.add_argument("--extras", action="append", default=[], help="Send Intent extra 'key: value' (repeatable)")
    p.add_argument("--url", help="Browse URL")
    p.add_argument("--launch", help="Launch App: package[/activity]")
    p.add_argument("--wait", type=int, help="Wait N seconds")
    p.add_argument("--shell", help="Run Shell: command (root only)")
    args = p.parse_args()

    if args.list_actions:
        for k, (code, _) in ACTION.items():
            print("  %-14s code %s" % (k, code))
        return

    name = args.name
    actions = []
    if args.spec:
        spec = json.load(open(args.spec))
        name = name or spec.get("name", "Task")
        for kind, params in spec["actions"]:
            actions.append((kind, params))
    if args.intent:
        actions.append(("send_intent", {"action": args.intent, "data": args.data,
                                        "package": args.package, "class": args.klass,
                                        "mime": args.mime, "target": args.target,
                                        "extras": args.extras}))
    if args.url:
        actions.append(("browse_url", {"url": args.url}))
    if args.launch:
        pkg, _, cls = args.launch.partition("/")
        actions.append(("launch_app", {"package": pkg, "class": cls}))
    if args.shell:
        actions.append(("run_shell", {"command": args.shell}))
    if args.wait:
        actions.append(("wait", {"seconds": args.wait}))

    if not name or not actions:
        p.error("need --name and at least one action (or --spec / --list-actions)")

    root = build_task(name, actions, args.id)
    ET.indent(root, space="  ")
    xml = ET.tostring(root, encoding="unicode")
    if args.out and args.out != "-":
        open(args.out, "w", encoding="utf-8").write('<?xml version="1.0" encoding="UTF-8"?>\n' + xml + "\n")
        print("wrote %s (%d action(s))" % (args.out, len(actions)))
    else:
        print('<?xml version="1.0" encoding="UTF-8"?>')
        print(xml)


if __name__ == "__main__":
    main()
