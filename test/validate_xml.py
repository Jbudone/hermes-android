#!/usr/bin/env python3
"""Validate a generated .tsk.xml: well-formed + expected action codes present."""
import sys
from xml.etree import ElementTree as ET

path = sys.argv[1]
expected = [int(x) for x in sys.argv[2:]]
root = ET.parse(path).getroot()          # raises if not well-formed
assert root.tag == "TaskerData", "root must be <TaskerData>, got %s" % root.tag
codes = [int(a.findtext("code")) for a in root.iter("Action")]
print("root=%s codes=%s" % (root.tag, codes))
if expected:
    missing = [c for c in expected if c not in codes]
    if missing:
        print("MISSING codes: %s" % missing)
        sys.exit(2)
print("XML OK")
