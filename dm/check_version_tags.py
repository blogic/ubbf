#!/usr/bin/env python3
"""Checks the TR-181 version tags of ubbf against the spec.

Two checks, both against the dm/spec/tr-181-2-<minor>-<patch>-usp-full.xml
files:

Schema tags (default). For each schema member that the spec knows, the
expected tags are:
  since: the item's version (inherited from its object) when it is newer
         than the oldest supported version
  until: the first spec version that marks the item deleted
A member that came or goes with its object needs no tag of its own: the
model entry of the object carries it. A member deleted in the oldest
supported version or before must go from the schema. The tags come from
dm/version_tags_dump.uc. Vendor items (X_) and members the spec does not
have are not checked.

Device (--dut). The paths a device advertises, the output of
`ubus call bbf-dm names '{"path":"Device.","next_level":false}'`, against
the spec of the device's version: an item the version does not have yet,
or has deleted, is an error. This covers the model entries, which the
schema check does not see. Items the spec does not have are listed apart.

Usage, from any directory, with a host build of src/ucode-mod-ubbf in $B:
  ucode -L "$R/files/usr/share/ucode/*.uc" -L "$B/*.so" \\
      $R/dm/version_tags_dump.uc > tags.json
  python3 -I $R/dm/check_version_tags.py tags.json [--prefix Device.DeviceInfo.]
  python3 -I $R/dm/check_version_tags.py --dut names.json --version 2.21.0
"""

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SPEC_DIR = Path(__file__).resolve().parent / 'spec'
SPEC_NAME = re.compile(r'^tr-181-2-(\d+)-(\d+)-usp-full\.xml$')
OLDEST_MINOR = 19

# Items that ubbf shows on purpose in versions the spec does not give
# them, with the reason. A key ending in a dot stands for its subtree.
# They are reported as allowed, not as errors.
DEVIATIONS = {
    'Device.Security.Certificate.{i}.GetCertificateURI()':
        '2.20 command, kept on 2.19 images by decision (2026-10-16)',
    'Device.WiFi.Templates.':
        '2.20 objects, kept on 2.19 images for the MLO groups of '
        'default_config (2026-10-16)',
    'Device.WiFi.AccessPoint.{i}.APMLDTemplateRef':
        'in no spec version, links an AccessPoint to its MLO template '
        '(2026-10-16)',
    'Device.DNS.RebindProtection.':
        '2.20 object, kept on 2.19 images: dns.uc renders it and '
        'initial.json sets it (2026-10-16)',
}


def local(tag):
    return tag.split('}', 1)[-1]


def minor_of(version):
    if version is None:
        return None
    m = re.match(r'^2\.(\d+)', version)
    return int(m.group(1)) if m else None


def deviation_of(item):
    """The reason an item is a deliberate deviation, or None."""
    for key, reason in DEVIATIONS.items():
        if item == key or (key.endswith('.') and item.startswith(key)):
            return reason
    return None


def spec_files(spec_dir):
    """Returns {minor: path}, the highest patch release of each minor."""
    best = {}
    for path in spec_dir.iterdir():
        m = SPEC_NAME.match(path.name)
        if not m:
            continue
        minor, patch = int(m.group(1)), int(m.group(2))
        if minor not in best or patch > best[minor][0]:
            best[minor] = (patch, path)
    return {minor: path for minor, (patch, path) in sorted(best.items())}


def spec_items(path):
    """Returns {item path: (version, status)} with inherited versions."""
    root = ET.parse(path).getroot()
    model = next(e for e in root if local(e.tag) == 'model')
    objects = {}
    items = {}

    for obj in model:
        if local(obj.tag) != 'object':
            continue
        name = obj.get('name')
        parent = name.rstrip('.').rsplit('.', 1)[0] + '.'
        version = obj.get('version') or objects.get(parent, (None,))[0]
        objects[name] = (version, obj.get('status'))
        items[name] = objects[name]

        for child in obj:
            if local(child.tag) not in ('parameter', 'command', 'event'):
                continue
            items[name + child.get('name')] = (child.get('version') or version,
                                               child.get('status'))
    return items


def expected_tags(specs):
    """Returns {item path: (since minor, until minor)} over all versions."""
    out = {}
    for minor, items in specs.items():
        for path, (version, status) in items.items():
            since, until = out.get(path, (None, None))
            first = minor_of(version)
            if first is not None and first > OLDEST_MINOR:
                since = first
            if status == 'deleted' and until is None:
                until = minor
            out[path] = (since, until)
    return out


def tag_text(minor):
    return None if minor is None else f'2.{minor}'


def check(tags, expected, prefix):
    errors = []
    for entry in tags:
        for name in entry['members']:
            item = entry['path'] + name
            if not item.startswith(prefix) or 'X_' in item:
                continue
            if item not in expected:
                for key in ('since', 'until'):
                    if name in entry[key]:
                        errors.append(f'{entry["id"]}: {key} tag on {item}, '
                                      f'which the spec does not have')
                continue
            since, until = expected[item]
            if deviation_of(item):
                print(f'allowed: {item}: {deviation_of(item)}')
                continue
            if until is not None and until <= OLDEST_MINOR:
                errors.append(f'{entry["id"]}: {item}: deleted in '
                              f'{tag_text(until)}, the oldest supported '
                              f'version: remove the member')
                continue
            obj_since, obj_until = expected.get(entry['path'], (None, None))
            if since == obj_since:
                since = None
            if until == obj_until:
                until = None
            for key, want in (('since', since), ('until', until)):
                got = entry[key].get(name)
                if got != tag_text(want):
                    errors.append(f'{entry["id"]}: {item}: {key} is {got}, '
                                  f'the spec says {tag_text(want)}')
    return errors


def dut_paths(names):
    """The advertised paths as patterns: instance numbers become {i}."""
    out = set()
    for entry in names.get('params', []):
        out.add(re.sub(r'\.\d+(?=\.|$)', '.{i}', entry['path']))
    return out


def dut_check(paths, expected, minor, prefix):
    """Returns (errors, allowed, unknown) for a device's advertised paths."""
    errors, allowed, unknown = [], set(), []
    for item in sorted(paths):
        if not item.startswith(prefix) or 'X_' in item:
            continue
        reason = deviation_of(item)
        if reason:
            allowed.add(next(k for k in DEVIATIONS if DEVIATIONS[k] == reason))
            continue
        if item not in expected and item + '{i}.' in expected:
            item += '{i}.'
        if item not in expected:
            unknown.append(item)
            continue
        since, until = expected[item]
        if since is not None and minor < since:
            errors.append(f'{item}: advertised, but new in {tag_text(since)}')
        elif until is not None and minor >= until:
            errors.append(f'{item}: advertised, but deleted in {tag_text(until)}')
    return errors, sorted(allowed), unknown


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('tags', nargs='?', help='output of dm/version_tags_dump.uc')
    ap.add_argument('--dut', type=Path,
                    help='output of `ubus call bbf-dm names` on a device')
    ap.add_argument('--version', help='TR-181 version of that device, 2.21.0')
    ap.add_argument('--prefix', default='Device.',
                    help='check only items below this path')
    ap.add_argument('--spec-dir', type=Path, default=SPEC_DIR)
    args = ap.parse_args()

    if bool(args.dut) == bool(args.tags):
        ap.error('give either a tags file or --dut')
    if args.dut and minor_of(args.version) is None:
        ap.error('--dut needs --version 2.<minor>[.<patch>]')

    files = spec_files(args.spec_dir)
    if not files:
        sys.exit(f'no TR-181 full XML in {args.spec_dir}')

    specs = {minor: spec_items(path) for minor, path in files.items()}
    expected = expected_tags(specs)
    versions = ', '.join(tag_text(m) for m in files)

    if args.dut:
        text = args.dut.read_text()
        names = json.loads(text[text.index('{'):])
        minor = minor_of(args.version)
        errors, allowed, unknown = dut_check(dut_paths(names), expected,
                                             minor, args.prefix)
        for key in allowed:
            print(f'allowed: {key}: {DEVIATIONS[key]}')
        for item in unknown:
            print(f'not in the spec: {item}')
        for e in errors:
            print(e)
        print(f'{len(errors)} errors, {len(unknown)} items not in the spec, '
              f'below {args.prefix} at TR-181 {args.version}, '
              f'spec versions {versions}')
        sys.exit(1 if errors else 0)

    tags = json.loads(Path(args.tags).read_text())
    errors = check(tags, expected, args.prefix)

    for e in errors:
        print(e)
    print(f'{len(errors)} mismatches below {args.prefix}, spec versions {versions}')
    sys.exit(1 if errors else 0)


if __name__ == '__main__':
    main()
