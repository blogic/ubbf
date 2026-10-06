#!/usr/bin/env python3
"""
TR-181 XML Specification Analyzer - Batch Processing Version
Processes all TR-181 XML spec files and generates individual JSON outputs for each object
"""

import xml.etree.ElementTree as ET
import sys
import os
from pathlib import Path
from typing import Dict, List, Set, Optional, Any
import json
import re
import glob

DM_DIR = Path(__file__).resolve().parent
SPEC_DIR = str(DM_DIR / "spec")
JSON_SPEC_DIR = str(DM_DIR / "json_spec")

class TR181Analyzer:
    def __init__(self, xml_file: str):
        self.xml_file = xml_file
        self.tree = ET.parse(xml_file)
        self.root = self.tree.getroot()
        # Remove namespace for easier parsing
        self._remove_namespace(self.root)

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

                # Get size constraints. A value may match any of several
                # sizes, e.g. empty or 5 to 7 characters.
                sizes = []
                for size in child.findall('size'):
                    lo = size.get('minLength')
                    hi = size.get('maxLength')
                    sizes.append([int(lo) if lo else None,
                                  int(hi) if hi else None])
                if [None, None] in sizes:
                    sizes = []
                if len(sizes) == 1:
                    if sizes[0][0] is not None:
                        details['minLength'] = sizes[0][0]
                    if sizes[0][1] is not None:
                        details['maxLength'] = sizes[0][1]
                elif sizes:
                    details['lengths'] = sizes

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

                # Get range constraints. A value may lie in any of several
                # ranges, e.g. IPVersion allows -1, 4 and 6.
                ranges = []
                for range_elem in child.findall('range'):
                    lo = range_elem.get('minInclusive')
                    hi = range_elem.get('maxInclusive')
                    ranges.append([int(lo) if lo else None,
                                   int(hi) if hi else None])
                if len(ranges) == 1:
                    if ranges[0][0] is not None:
                        details['minInclusive'] = ranges[0][0]
                    if ranges[0][1] is not None:
                        details['maxInclusive'] = ranges[0][1]
                elif ranges:
                    details['ranges'] = ranges

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
                # Reference to another data type
                ref = child.get('ref')
                if ref:
                    details['type'] = f'dataType:{ref}'

            else:
                details['type'] = tag

        return details if details else {'type': 'unknown'}

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

        # Get description
        desc_elem = obj_elem.find('description')
        if desc_elem is not None and desc_elem.text:
            details['description'] = ' '.join(desc_elem.text.strip().split())

        # Get only DIRECT child parameters (not recursive)
        for param in obj_elem.findall('./parameter'):
            param_details = self._get_parameter_details(param)
            if param_details['name']:
                details['parameters'].append(param_details)

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
        """Extract all objects from the XML file"""
        objects = {}

        # Find all object elements
        for obj in self.root.findall('.//object'):
            obj_details = self.get_object_details(obj)
            obj_path = obj_details['path']

            if obj_path:
                objects[obj_path] = obj_details

        return objects

    def generate_output_filename(self, obj_path: str) -> str:
        """Generate output filename from object path"""
        # Remove Device. prefix and trailing dots
        clean_path = obj_path.replace('Device.', '').rstrip('.')
        # Replace {i} with empty string for cleaner names
        clean_path = clean_path.replace('.{i}', '')
        # Return the cleaned path
        return f"{clean_path}.json"


def process_single_xml(xml_file: str, output_dir: str) -> Dict[str, str]:
    """Process a single XML file and generate JSON outputs - one per object"""
    print(f"\nProcessing: {xml_file}")
    print("-" * 60)

    try:
        analyzer = TR181Analyzer(xml_file)
        objects = analyzer.extract_all_objects()

        if not objects:
            print(f"  No objects found in {xml_file}")
            return {}

        print(f"  Found {len(objects)} objects")

        # Create output directory if it doesn't exist
        Path(output_dir).mkdir(parents=True, exist_ok=True)

        output_files = {}

        # Process EACH object individually - create a separate file for each
        for obj_path, obj_details in objects.items():
            filename = analyzer.generate_output_filename(obj_path)
            output_path = os.path.join(output_dir, filename)

            # Create output data for this single object
            output_data = {
                'source_file': os.path.basename(xml_file),
                'path': obj_path,
                'object': obj_details
            }

            # Write JSON file
            with open(output_path, 'w') as f:
                json.dump(output_data, f, indent=2)

            output_files[obj_path] = output_path

            # Determine object type for display
            instance_count = obj_path.count('{i}')
            if instance_count == 0:
                obj_type = "single"
            elif instance_count == 1:
                obj_type = "multi"
            else:
                obj_type = f"nested-{instance_count}"

            print(f"    ✓ [{obj_type:8}] {obj_path}")
            print(f"                  → {filename}")

        return output_files

    except Exception as e:
        print(f"  ERROR processing {xml_file}: {e}")
        import traceback
        traceback.print_exc()
        return {}


def process_all_specs(spec_dir: str = SPEC_DIR, output_dir: str = JSON_SPEC_DIR):
    """Process all XML files in the spec directory"""

    # Find all XML files
    xml_files = glob.glob(os.path.join(spec_dir, "*.xml"))

    if not xml_files:
        print(f"No XML files found in {spec_dir}")
        return

    print(f"Found {len(xml_files)} XML files to process")
    print("=" * 60)

    all_outputs = {}

    # Process each XML file
    for xml_file in sorted(xml_files):
        outputs = process_single_xml(xml_file, output_dir)
        all_outputs.update(outputs)

    # Generate summary
    print("\n" + "=" * 60)
    print(f"SUMMARY: Generated {len(all_outputs)} JSON files in {output_dir}")
    print("=" * 60)

    # Create an index file with better organization
    index_file = os.path.join(output_dir, "index.json")
    index_data = {
        'total_objects': len(all_outputs),
        'output_directory': output_dir,
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

    print(f"\nIndex file created: {index_file}")

    # Print statistics
    multi_instance = [p for p in all_outputs.keys() if '{i}' in p]
    single_instance = [p for p in all_outputs.keys() if '{i}' not in p]
    nested = [p for p in all_outputs.keys() if p.count('{i}') > 1]

    print(f"\nStatistics:")
    print(f"  Single-instance objects: {len(single_instance)}")
    print(f"  Multi-instance objects: {len(multi_instance) - len(nested)}")
    print(f"  Nested objects: {len(nested)}")

    # Show categories
    print(f"\nObjects by category:")
    for category in sorted(index_data['by_category'].keys())[:10]:
        count = len(index_data['by_category'][category])
        print(f"  {category}: {count} objects")


def main():
    import argparse

    parser = argparse.ArgumentParser(description='TR-181 XML Specification Analyzer')
    parser.add_argument('--spec-dir', default=SPEC_DIR,
                        help='Directory containing TR-181 XML specification files')
    parser.add_argument('--output-dir', default=JSON_SPEC_DIR,
                        help='Output directory for JSON files')
    parser.add_argument('--single-file', help='Process only a single XML file')
    parser.add_argument('--clean', action='store_true',
                        help='Clean output directory before processing')

    args = parser.parse_args()

    # Clean output directory if requested
    if args.clean and os.path.exists(args.output_dir):
        import shutil
        print(f"Cleaning {args.output_dir}...")
        shutil.rmtree(args.output_dir)

    if args.single_file:
        if not os.path.exists(args.single_file):
            print(f"Error: File {args.single_file} not found")
            sys.exit(1)
        process_single_xml(args.single_file, args.output_dir)
    else:
        process_all_specs(args.spec_dir, args.output_dir)


if __name__ == "__main__":
    main()