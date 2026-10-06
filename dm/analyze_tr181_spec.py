#!/usr/bin/env python3
"""
TR-181 XML Specification Analyzer

Writes one JSON file per object of a TR-181 full USP XML into
dm/json_spec/<version>/, for example dm/json_spec/2.21.0/. Each file is
named after the full object path, so no two objects share a file. Without
--spec, every dm/spec/tr-181-2-<minor>-<patch>-usp-full.xml is processed,
the highest patch release of each minor (a patch release carries the same
model as its .0 release).
"""

import xml.etree.ElementTree as ET
import sys
import os
from pathlib import Path
from typing import Dict, List, Set, Optional, Any
import json
import re

DM_DIR = Path(__file__).resolve().parent
SPEC_DIR = str(DM_DIR / "spec")
JSON_SPEC_DIR = str(DM_DIR / "json_spec")
FULL_XML = re.compile(r"^tr-181-2-(\d+)-(\d+)-usp-full\.xml$")


def spec_version(xml_file: str) -> Optional[str]:
    """"2.21.0" for tr-181-2-21-0-usp-full.xml, None for another name."""
    m = FULL_XML.match(os.path.basename(xml_file))
    return f"2.{m.group(1)}.{m.group(2)}" if m else None


def spec_files(spec_dir: str) -> List[str]:
    """The full USP XMLs of spec_dir, the highest patch of each minor."""
    best: Dict[int, tuple] = {}
    for name in os.listdir(spec_dir):
        m = FULL_XML.match(name)
        if not m:
            continue
        minor, patch = int(m.group(1)), int(m.group(2))
        if minor not in best or patch > best[minor][0]:
            best[minor] = (patch, os.path.join(spec_dir, name))
    return [path for _, (_, path) in sorted(best.items())]


def version_dirs(json_dir: str = JSON_SPEC_DIR) -> List[str]:
    """The version directories of json_dir, oldest first."""
    found = []
    for name in os.listdir(json_dir):
        m = re.match(r"^2\.(\d+)\.(\d+)$", name)
        if m and os.path.isdir(os.path.join(json_dir, name)):
            found.append(((int(m.group(1)), int(m.group(2))), name))
    return [os.path.join(json_dir, name) for _, name in sorted(found)]

class TR181Analyzer:
    def __init__(self, xml_file: str):
        self.xml_file = xml_file
        self.tree = ET.parse(xml_file)
        self.root = self.tree.getroot()
        # Remove namespace for easier parsing
        self._remove_namespace(self.root)
        self.data_types = {e.get('name'): e for e in self.root.iter('dataType')
                           if e.get('name')}

    def _remove_namespace(self, elem):
        """Remove namespace from XML elements for easier parsing"""
        if elem.tag.startswith('{'):
            elem.tag = elem.tag.split('}')[1]
        for child in elem:
            self._remove_namespace(child)

    def _get_syntax_details(self, syntax_elem) -> Dict[str, Any]:
        """Extract detailed syntax information from a parameter"""
        if syntax_elem is None:
            return {'type': 'unknown'}

        details = {}

        # TR-181 marks a credential with secured="true" on <syntax> itself,
        # so it is not reached by the child walk below.
        if syntax_elem.get('secured') == 'true':
            details['secured'] = True

        # Check for default value first (can be at syntax level)
        default_elem = syntax_elem.find('default')
        if default_elem is not None:
            details['default'] = default_elem.get('value')
            # Also capture the default type if specified
            if default_elem.get('type'):
                details['defaultType'] = default_elem.get('type')

        for child in syntax_elem:
            tag = child.tag

            # Skip default element as we already processed it
            if tag == 'default':
                continue

            if tag == 'string':
                details['type'] = 'string'

                # Check for default value inside string element
                string_default = child.find('default')
                if string_default is not None:
                    details['default'] = string_default.get('value')
                    if string_default.get('type'):
                        details['defaultType'] = string_default.get('type')

                self._sizes_apply(details, child)

                # Get enumerations - simplified to just array of values
                enums = []
                for enum in child.findall('enumeration'):
                    enum_val = enum.get('value')
                    if enum_val:
                        enums.append(enum_val)
                if enums:
                    details['enumerations'] = enums

                # Get pattern constraints
                pattern = child.find('pattern')
                if pattern is not None:
                    details['pattern'] = pattern.get('value')

                # The allowed values are those of another parameter, a
                # list of what the device supports.
                enum_ref = child.find('enumerationRef')
                if enum_ref is not None:
                    details['enumerationRef'] = enum_ref.get('targetParam', '')

                # Get path reference
                pathRef = child.find('pathRef')
                if pathRef is not None:
                    details['pathRef'] = {
                        'targetParent': pathRef.get('targetParent', ''),
                        'targetType': pathRef.get('targetType', '')
                    }

            elif tag in ['int', 'unsignedInt', 'long', 'unsignedLong']:
                details['type'] = tag

                # Check for default value inside integer element
                int_default = child.find('default')
                if int_default is not None:
                    details['default'] = int_default.get('value')
                    if int_default.get('type'):
                        details['defaultType'] = int_default.get('type')

                self._ranges_apply(details, child)

            elif tag == 'boolean':
                details['type'] = 'boolean'

                # Check for default value inside boolean element
                bool_default = child.find('default')
                if bool_default is not None:
                    details['default'] = bool_default.get('value')
                    if bool_default.get('type'):
                        details['defaultType'] = bool_default.get('type')

            elif tag == 'dateTime':
                details['type'] = 'dateTime'

            elif tag == 'hexBinary':
                details['type'] = 'hexBinary'
                size = child.find('size')
                if size is not None:
                    if size.get('minLength'):
                        details['minLength'] = int(size.get('minLength'))
                    if size.get('maxLength'):
                        details['maxLength'] = int(size.get('maxLength'))

            elif tag == 'base64':
                details['type'] = 'base64'
                size = child.find('size')
                if size is not None:
                    if size.get('minLength'):
                        details['minLength'] = int(size.get('minLength'))
                    if size.get('maxLength'):
                        details['maxLength'] = int(size.get('maxLength'))

            elif tag == 'list':
                # A comma-separated list: the facts of the item element that
                # follows apply to each item, the size here to the whole value.
                details['list'] = True
                size = child.find('size')
                if size is not None:
                    if size.get('minLength'):
                        details['listMinLength'] = int(size.get('minLength'))
                    if size.get('maxLength'):
                        details['listMaxLength'] = int(size.get('maxLength'))

            elif tag == 'dataType':
                # A named data type: its base facts, then the facets the
                # reference adds, as for any derived type.
                ref = child.get('ref')
                if ref:
                    details.update(self._data_type_details(ref))
                    details['dataType'] = ref
                    self._sizes_apply(details, child)
                    self._ranges_apply(details, child)

            else:
                details['type'] = tag

        return details if details else {'type': 'unknown'}

    @staticmethod
    def _sizes_apply(details, elem):
        """The size facets of an element. A value may match any of
        several sizes, e.g. empty or 5 to 7 characters."""
        sizes = []
        for size in elem.findall('size'):
            lo = size.get('minLength')
            hi = size.get('maxLength')
            sizes.append([int(lo) if lo else None, int(hi) if hi else None])
        if not sizes:
            return
        for key in ('minLength', 'maxLength', 'lengths'):
            details.pop(key, None)
        if [None, None] in sizes:
            return
        if len(sizes) == 1:
            if sizes[0][0] is not None:
                details['minLength'] = sizes[0][0]
            if sizes[0][1] is not None:
                details['maxLength'] = sizes[0][1]
        else:
            details['lengths'] = sizes

    @staticmethod
    def _ranges_apply(details, elem):
        """The range facets of an element. A value may lie in any of
        several ranges, e.g. IPVersion allows -1, 4 and 6."""
        ranges = []
        for range_elem in elem.findall('range'):
            lo = range_elem.get('minInclusive')
            hi = range_elem.get('maxInclusive')
            ranges.append([int(lo) if lo else None, int(hi) if hi else None])
        if not ranges:
            return
        for key in ('minInclusive', 'maxInclusive', 'ranges'):
            details.pop(key, None)
        if len(ranges) == 1:
            if ranges[0][0] is not None:
                details['minInclusive'] = ranges[0][0]
            if ranges[0][1] is not None:
                details['maxInclusive'] = ranges[0][1]
        else:
            details['ranges'] = ranges

    def _data_type_details(self, name) -> Dict[str, Any]:
        """The facts of a named data type, with those of its base type."""
        elem = self.data_types.get(name)
        if elem is None:
            return {'type': f'dataType:{name}'}

        base = elem.get('base')
        if not base:
            return self._get_syntax_details(elem)

        details = self._data_type_details(base)
        self._sizes_apply(details, elem)
        self._ranges_apply(details, elem)
        return details

    def _get_parameter_details(self, param_elem) -> Dict[str, Any]:
        """Extract detailed parameter information"""
        name = param_elem.get('name', '')
        access = param_elem.get('access', 'readOnly')
        version = param_elem.get('version', '')

        # Get description
        desc_elem = param_elem.find('description')
        description = ''
        if desc_elem is not None and desc_elem.text:
            description = desc_elem.text.strip()
            # Clean up description - remove excess whitespace
            description = ' '.join(description.split())

        # Get syntax details
        syntax = param_elem.find('syntax')
        syntax_details = self._get_syntax_details(syntax)

        param_info = {
            'name': name,
            'access': access,
            'description': description,
            **syntax_details
        }

        if version:
            param_info['version'] = version
        if param_elem.get('status'):
            param_info['status'] = param_elem.get('status')

        # Check for special attributes
        if param_elem.get('activeNotify'):
            param_info['activeNotify'] = param_elem.get('activeNotify')
        if param_elem.get('forcedInform'):
            param_info['forcedInform'] = param_elem.get('forcedInform')
        if param_elem.get('hidden'):
            param_info['hidden'] = param_elem.get('hidden')

        return param_info

    def get_object_details(self, obj_elem) -> Dict[str, Any]:
        """Get comprehensive details about a specific object element"""
        obj_path = obj_elem.get('name', '')

        details = {
            'path': obj_path,
            'access': obj_elem.get('access', 'readOnly'),
            'minEntries': obj_elem.get('minEntries', '0'),
            'maxEntries': obj_elem.get('maxEntries', '1'),
            'enableParameter': obj_elem.get('enableParameter', ''),
            'numEntriesParameter': obj_elem.get('numEntriesParameter', ''),
            'version': obj_elem.get('version', ''),
            'parameters': []
        }
        if obj_elem.get('status'):
            details['status'] = obj_elem.get('status')

        # Get description
        desc_elem = obj_elem.find('description')
        if desc_elem is not None and desc_elem.text:
            details['description'] = ' '.join(desc_elem.text.strip().split())

        # Get only DIRECT child parameters (not recursive)
        for param in obj_elem.findall('./parameter'):
            param_details = self._get_parameter_details(param)
            if param_details['name']:
                details['parameters'].append(param_details)

        # Commands and events: name, version, status and the argument names,
        # which is what a version delta compares.
        for tag, key in (('command', 'commands'), ('event', 'events')):
            members = []
            for elem in obj_elem.findall(f'./{tag}'):
                member = {'name': elem.get('name', '')}
                for attr in ('version', 'status', 'async'):
                    if elem.get(attr):
                        member[attr] = elem.get(attr)
                for section in ('input', 'output'):
                    sec = elem.find(section)
                    if sec is not None:
                        member[section] = [p.get('name') for p in sec.iter('parameter')]
                if tag == 'event':
                    member['arguments'] = [p.get('name') for p in elem.findall('./parameter')]
                members.append(member)
            if members:
                details[key] = members

        # Get direct child objects
        details['children'] = []
        for child_obj in obj_elem.findall('./object'):
            child_name = child_obj.get('name', '')
            if child_name:
                details['children'].append(child_name)

        # Check for unique keys
        unique_key = obj_elem.find('uniqueKey')
        if unique_key is not None:
            functional = unique_key.get('functional', 'false')
            key_params = [param.get('ref') for param in unique_key.findall('parameter')]
            details['uniqueKey'] = {
                'functional': functional,
                'parameters': key_params
            }

        return details

    def extract_all_objects(self) -> Dict[str, Any]:
        """Extract the objects of the model.

        Only the objects of <model>: the <component> blocks carry objects
        whose names are relative to the component, and would land under
        the wrong path.
        """
        objects = {}
        model = self.root.find('model')
        if model is None:
            return objects

        for obj in model.findall('object'):
            obj_details = self.get_object_details(obj)
            obj_path = obj_details['path']

            if obj_path:
                objects[obj_path] = obj_details

        return objects

    def generate_output_filename(self, obj_path: str) -> str:
        """The file of an object: its full path without the trailing dot,
        "Device.USB.USBHosts.Host.{i}.json", so each object has its own."""
        return f"{obj_path.rstrip('.')}.json"


def process_single_xml(xml_file: str, output_dir: str) -> Dict[str, str]:
    """Write one JSON file per object of a full XML into output_dir."""
    analyzer = TR181Analyzer(xml_file)
    objects = analyzer.extract_all_objects()

    if not objects:
        sys.exit(f"no model objects in {xml_file}")

    Path(output_dir).mkdir(parents=True, exist_ok=True)

    output_files = {}
    for obj_path, obj_details in objects.items():
        filename = analyzer.generate_output_filename(obj_path)
        output_path = os.path.join(output_dir, filename)
        if output_path in output_files.values():
            sys.exit(f"{xml_file}: two objects map to {filename}")

        output_data = {
            'source_file': os.path.basename(xml_file),
            'path': obj_path,
            'object': obj_details
        }

        with open(output_path, 'w') as f:
            json.dump(output_data, f, indent=2)

        output_files[obj_path] = output_path

    return output_files


def process_spec(xml_file: str, json_dir: str = JSON_SPEC_DIR, clean: bool = False):
    """Process one full XML into json_dir/<version>/ with its index."""
    version = spec_version(xml_file)
    if not version:
        sys.exit(f"{xml_file}: not a tr-181-2-<minor>-<patch>-usp-full.xml")

    output_dir = os.path.join(json_dir, version)
    if clean and os.path.exists(output_dir):
        import shutil
        shutil.rmtree(output_dir)

    all_outputs = process_single_xml(xml_file, output_dir)
    print(f"{version}: {len(all_outputs)} objects from "
          f"{os.path.basename(xml_file)} in {output_dir}")

    index_file = os.path.join(output_dir, "index.json")
    index_data = {
        'spec_version': version,
        'source_file': os.path.basename(xml_file),
        'total_objects': len(all_outputs),
        'objects': {},
        'by_category': {}
    }

    for obj_path, json_file in sorted(all_outputs.items()):
        # Basic info
        index_data['objects'][obj_path] = {
            'file': os.path.basename(json_file),
            'instance_type': 'multi' if '{i}' in obj_path else 'single',
            'nesting_level': obj_path.count('{i}')
        }

        # Categorize by domain (first part after Device.)
        if obj_path.startswith('Device.'):
            parts = obj_path[7:].split('.')  # Remove 'Device.' prefix
            if parts:
                category = parts[0]
                if category not in index_data['by_category']:
                    index_data['by_category'][category] = []
                index_data['by_category'][category].append(obj_path)

    with open(index_file, 'w') as f:
        json.dump(index_data, f, indent=2)


def main():
    import argparse

    parser = argparse.ArgumentParser(description='TR-181 XML Specification Analyzer')
    parser.add_argument('--spec', action='append',
                        help='full USP XML to process; repeatable. Default: the '
                             'highest patch of each minor in --spec-dir')
    parser.add_argument('--spec-dir', default=SPEC_DIR,
                        help='Directory containing TR-181 XML specification files')
    parser.add_argument('--output-dir', default=JSON_SPEC_DIR,
                        help='Directory that receives one <version>/ per spec')
    parser.add_argument('--clean', action='store_true',
                        help='Empty each version directory before writing it')

    args = parser.parse_args()

    files = args.spec or spec_files(args.spec_dir)
    if not files:
        sys.exit(f"no tr-181-2-<minor>-<patch>-usp-full.xml in {args.spec_dir}")

    for xml_file in files:
        process_spec(xml_file, args.output_dir, args.clean)


if __name__ == "__main__":
    main()