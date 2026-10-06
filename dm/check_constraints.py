#!/usr/bin/env python3
"""Checks the types, rules and table facts of the ubbf schemas against the spec.

The type of each schema parameter that is not a list must be the dm_type of
its spec base type. For each writable schema parameter that the newest dm/json_spec/<version>/
knows, the rule in the `constraints` table of its schema export must state
what the spec states: enum, min, max, ranges, min_length, max_length,
lengths, list, list_min_length and list_max_length. `secured` is a ubbf
fact and is not checked, and so is the enum of a parameter whose spec
values are an enumerationRef to a list of what the device supports. For
each table export, `addable: false` must
match a readOnly table in the spec, and `max_instances` a finite
maxEntries. The newest version serves every image: it refuses no value
that an older supported version allows.

Usage, from any directory, with a host build of src/ucode-mod-ubbf in $B:
  ucode -L "$R/files/usr/share/ucode/*.uc" -L "$B/*.so" \\
      $R/dm/version_tags_dump.uc > schemas.json
  python3 -I $R/dm/check_constraints.py schemas.json [--prefix Device.WiFi.]
"""

import argparse
import json
import sys
from pathlib import Path

DM_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(DM_DIR))
from analyze_tr181_spec import version_dirs  # noqa: E402

NUMERIC = {'int', 'unsignedInt', 'long', 'unsignedLong'}

DM_TYPES = {
    'string': 'STRING', 'boolean': 'BOOL', 'int': 'INT', 'unsignedInt': 'UINT',
    'long': 'LONG', 'unsignedLong': 'ULONG', 'hexBinary': 'HEXBIN',
    'base64': 'BASE64', 'dateTime': 'DATETIME', 'decimal': 'DECIMAL',
}

# Rules that differ from the spec on purpose, with the reason. The key is
# "<object path><Param>". They are reported as allowed, not as errors.
DEVIATIONS = {
    'Device.PCP.PreferredVersion':
        'libpcpnatpmp speaks NAT-PMP (0) and PCP 1 and 2 only',
    'Device.QoS.Classification.{i}.DSCPMark':
        '-2 (mark from the Ethernet priority) has no implementation',
    'Device.QoS.Classification.{i}.TrafficClass':
        'the minor number of an HTB class, written in decimal and parsed as '
        'hex by tc (bbf-qos-apply)',
    'Device.QoS.Classification.{i}.VLANIDCheck':
        'the IEEE 802.1Q VLAN ID range',
    'Device.QoS.Classification.{i}.EthernetPriorityCheck':
        'the IEEE 802.1Q priority range',
    'Device.SFPs.AllowedSFPs.AllowedSFP.{i}.VendorOUI':
        'empty is the criterion that matches any vendor',
    'Device.SFPs.SFPProperties.SFP.{i}.VendorOUI':
        'empty is the criterion that matches any vendor',
}


def spec_load(spec_dir):
    """Maps each object path to its spec record."""
    objects = {}
    for path in sorted(Path(spec_dir).glob('*.json')):
        obj = json.loads(path.read_text()).get('object') or {}
        if obj.get('path'):
            objects[obj['path']] = obj
    return objects


def rule_of(param):
    """The rule the spec states for one parameter."""
    out = {}
    ptype = param.get('type') or ''

    if param.get('list'):
        out['list'] = True
        for key, name in (('listMinLength', 'list_min_length'),
                          ('listMaxLength', 'list_max_length')):
            if param.get(key) is not None:
                out[name] = int(param[key])

    if param.get('enumerations'):
        out['enum'] = list(param['enumerations'])

    if ptype in NUMERIC:
        for key, name in (('minInclusive', 'min'), ('maxInclusive', 'max')):
            if param.get(key) is not None:
                out[name] = int(param[key])
        if param.get('ranges'):
            out['ranges'] = [list(r) for r in param['ranges']]

    # The core checks a hexBinary length in bytes, as TR-106 counts it.
    if ptype in ('string', 'hexBinary'):
        for key, name in (('minLength', 'min_length'), ('maxLength', 'max_length')):
            if param.get(key) is not None:
                out[name] = int(param[key])
        if param.get('lengths'):
            out['lengths'] = [list(r) for r in param['lengths']]

    return out


def rule_ours(facts):
    """The rule of a schema parameter, without null keys and ubbf facts."""
    return {k: v for k, v in (facts or {}).items()
            if v is not None and k != 'secured'}


def table_facts(obj):
    """What the spec states about a table."""
    limit = obj.get('maxEntries')
    return {
        'addable': obj.get('access') != 'readOnly',
        'max_instances': int(limit) if str(limit).isdigit() else None,
    }


def check(exports, objects, prefix):
    errors = []
    allowed = []

    for e in exports:
        obj = objects.get(e['path'])
        if obj is None or not e['path'].startswith(prefix):
            continue

        if e['path'].endswith('{i}.'):
            want = table_facts(obj)
            for key in ('addable', 'max_instances'):
                if e.get(key) != want[key]:
                    errors.append(f"{e['id']}: {e['path']} {key} is "
                                  f"{e.get(key)}, the spec has {want[key]}")

        params = {p['name']: p for p in obj.get('parameters') or [] if p.get('name')}
        for name, got in sorted(e.get('types', {}).items()):
            param = params.get(name)
            # A list travels as a comma-separated string, whatever its item type.
            if param is None or param.get('list'):
                continue
            want = DM_TYPES.get(param.get('type'))
            if want and got != want:
                errors.append(f"{e['id']}: {e['path']}{name} type is {got}, "
                              f"the spec has {want}")

        # The spec JSON writes a list default as [a,b]; the value is a,b.
        for name, value in sorted(e.get('defaults', {}).items()):
            if isinstance(value, str) and value.startswith('[') and value.endswith(']'):
                errors.append(f"{e['id']}: {e['path']}{name} default {value} is "
                              f"in the bracket form of the spec JSON")

        for name in sorted(e['writable']):
            if name not in params:
                continue
            want = rule_of(params[name])
            got = rule_ours(e['constraints'].get(name))
            # The values of an enumerationRef are the device's supported
            # list, which the schema states as its enum.
            if params[name].get('enumerationRef') and 'enum' not in want:
                got.pop('enum', None)
            if got == want:
                continue
            item = e['path'] + name
            line = f"{e['id']}: {item} has {json.dumps(got, sort_keys=True)}, " \
                   f"the spec has {json.dumps(want, sort_keys=True)}"
            if item in DEVIATIONS:
                allowed.append(f'{line} ({DEVIATIONS[item]})')
            else:
                errors.append(line)

    return errors, allowed


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('schemas', help='output of dm/version_tags_dump.uc')
    ap.add_argument('--prefix', default='Device.', help='check only below this path')
    args = ap.parse_args()

    spec_dir = version_dirs(str(DM_DIR / 'json_spec'))[-1]
    exports = json.loads(Path(args.schemas).read_text())
    errors, allowed = check(exports, spec_load(spec_dir), args.prefix)

    for line in allowed:
        print(f'allowed: {line}')
    for line in errors:
        print(f'error: {line}')
    print(f'{len(errors)} errors, {len(allowed)} allowed, against {Path(spec_dir).name}')

    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
