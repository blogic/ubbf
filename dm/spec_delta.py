#!/usr/bin/env python3
"""Prints what changed in TR-181 between two versions of dm/json_spec/.

Usage:
  python3 -I dm/spec_delta.py 2.19.1 2.21.0 [--prefix Device.WiFi.]
      [--ours tags.json]

The versions name directories of dm/json_spec/ (dm/analyze_tr181_spec.py
writes them). The output lists, per object: objects added and removed,
parameters, commands and events added and removed, status changes, and
changes to type, access, enumerations, ranges, lengths and arguments.

--ours takes the output of dm/version_tags_dump.uc and keeps only the
objects ubbf has a schema for: the list of what a new version means for
the implementation.
"""

import argparse
import json
import sys
from pathlib import Path

DM_DIR = Path(__file__).resolve().parent
JSON_SPEC_DIR = DM_DIR / "json_spec"

# Parameter facts whose change matters for an implementation. The
# description is left out on purpose: it changes with every edit of the
# spec text.
PARAM_FACTS = ("type", "access", "list", "minInclusive", "maxInclusive", "ranges",
               "minLength", "maxLength", "lengths", "listMinLength",
               "listMaxLength", "pattern", "default", "secured")


def objects_load(version_dir):
    """{object path: object record} of one version directory."""
    out = {}
    for path in version_dir.glob("*.json"):
        if path.name == "index.json":
            continue
        obj = json.loads(path.read_text()).get("object") or {}
        if obj.get("path"):
            out[obj["path"]] = obj
    return out


def by_name(records):
    return {r["name"]: r for r in records or [] if r.get("name")}


def status_of(record):
    return record.get("status") or "current"


def member_delta(kind, old, new):
    """Lines for the parameters, commands or events of one object."""
    lines = []
    for name in sorted(set(new) - set(old)):
        rec = new[name]
        lines.append(f"  + {kind} {name}" + (f" (since {rec['version']})" if rec.get("version") else ""))
    for name in sorted(set(old) - set(new)):
        lines.append(f"  - {kind} {name}")
    for name in sorted(set(old) & set(new)):
        a, b = old[name], new[name]
        if status_of(a) != status_of(b):
            lines.append(f"  ~ {kind} {name}: {status_of(a)} -> {status_of(b)}")
        if kind == "parameter":
            for fact in PARAM_FACTS:
                if a.get(fact) != b.get(fact):
                    lines.append(f"  ~ {kind} {name}: {fact} {a.get(fact)!r} -> {b.get(fact)!r}")
            ea, eb = set(a.get("enumerations") or []), set(b.get("enumerations") or [])
            if eb - ea:
                lines.append(f"  ~ {kind} {name}: enum + {', '.join(sorted(eb - ea))}")
            if ea - eb:
                lines.append(f"  ~ {kind} {name}: enum - {', '.join(sorted(ea - eb))}")
        else:
            for section in ("input", "output", "arguments"):
                sa, sb = set(a.get(section) or []), set(b.get(section) or [])
                if sb - sa:
                    lines.append(f"  ~ {kind} {name}: {section} + {', '.join(sorted(sb - sa))}")
                if sa - sb:
                    lines.append(f"  ~ {kind} {name}: {section} - {', '.join(sorted(sa - sb))}")
    return lines


def object_delta(old, new):
    """Lines for one object present in both versions."""
    lines = []
    if status_of(old) != status_of(new):
        lines.append(f"  ~ object: {status_of(old)} -> {status_of(new)}")
    for fact in ("access", "minEntries", "maxEntries"):
        if old.get(fact) != new.get(fact):
            lines.append(f"  ~ object: {fact} {old.get(fact)!r} -> {new.get(fact)!r}")
    lines += member_delta("parameter", by_name(old.get("parameters")), by_name(new.get("parameters")))
    lines += member_delta("command", by_name(old.get("commands")), by_name(new.get("commands")))
    lines += member_delta("event", by_name(old.get("events")), by_name(new.get("events")))
    return lines


def parent_of(path):
    """"Device.A." for "Device.A.B." and for the table "Device.A.B.{i}."."""
    parts = path.rstrip(".").split(".")
    drop = 2 if parts[-1] == "{i}" else 1
    return ".".join(parts[:-drop]) + "."


def ours_load(path):
    """The object paths ubbf has a schema for, from version_tags_dump.uc."""
    return {entry["path"] for entry in json.loads(Path(path).read_text())}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("old", help="older version, a directory name of dm/json_spec/")
    ap.add_argument("new", help="newer version")
    ap.add_argument("--prefix", default="Device.", help="only objects below this path")
    ap.add_argument("--ours", help="output of dm/version_tags_dump.uc")
    ap.add_argument("--json-dir", type=Path, default=JSON_SPEC_DIR)
    args = ap.parse_args()

    dirs = [args.json_dir / v for v in (args.old, args.new)]
    for d in dirs:
        if not d.is_dir():
            sys.exit(f"no {d}; dm/analyze_tr181_spec.py writes it")

    old, new = objects_load(dirs[0]), objects_load(dirs[1])
    ours = ours_load(args.ours) if args.ours else None

    def wanted(path):
        return path.startswith(args.prefix) and (ours is None or path in ours)

    added = sorted(p for p in set(new) - set(old) if p.startswith(args.prefix))
    removed = sorted(p for p in set(old) - set(new) if wanted(p))
    changed = 0

    if ours is None:
        for path in added:
            n = len(new[path].get("parameters") or [])
            print(f"+ object {path} ({n} parameters"
                  + (f", since {new[path]['version']})" if new[path].get("version") else ")"))
    else:
        # A new object counts for ubbf when ubbf implements its parent.
        added = [p for p in added if parent_of(p) in ours]
        for path in added:
            print(f"+ object {path} (below {parent_of(path)}, which ubbf implements)")
    for path in removed:
        print(f"- object {path}")

    for path in sorted(set(old) & set(new)):
        if not wanted(path):
            continue
        lines = object_delta(old[path], new[path])
        if lines:
            changed += 1
            print(path)
            print("\n".join(lines))

    print(f"\n{args.old} -> {args.new} below {args.prefix}"
          + (" (objects ubbf has a schema for)" if ours is not None else "")
          + f": {len(added)} objects added, {len(removed)} removed, {changed} changed")


if __name__ == "__main__":
    main()
