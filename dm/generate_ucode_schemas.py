#!/usr/bin/env python3

"""
Generate ucode schema modules from TR-181 JSON specifications.

This script reads the parsed JSON specifications and generates ucode modules
containing schema definitions and default values for each domain.
"""

import json
import os
import argparse
from pathlib import Path
from typing import Dict, Any, List, Set
from collections import defaultdict

DM_DIR = Path(__file__).resolve().parent

class UcodeSchemaGenerator:
    """Generate ucode schema modules from TR-181 JSON specs"""

    def __init__(self, json_dir: str, output_dir: str):
        self.json_dir = Path(json_dir)
        self.output_dir = Path(output_dir)

        # Mapping from TR-181 types to dm_type constants
        self.type_mapping = {
            'string': 'dm_type.STRING',
            'boolean': 'dm_type.BOOL',
            'int': 'dm_type.INT',
            'unsignedInt': 'dm_type.UINT',
            'long': 'dm_type.LONG',
            'unsignedLong': 'dm_type.ULONG',
            'hexBinary': 'dm_type.HEXBIN',
            'base64': 'dm_type.BASE64',
            'dateTime': 'dm_type.DATETIME',
            'dataType:IPAddress': 'dm_type.STRING',
            'dataType:IPv4Address': 'dm_type.STRING',
            'dataType:IPv6Address': 'dm_type.STRING',
            'dataType:MACAddress': 'dm_type.STRING',
            'dataType:UUID': 'dm_type.STRING',
            'dataType:URI': 'dm_type.STRING',
            'dataType:URL': 'dm_type.STRING',
            'dataType:Alias': 'dm_type.STRING',
        }

        # Group objects by domain
        self.domains = defaultdict(list)

    def parse_domain_from_path(self, path: str) -> str:
        """Extract domain name from object path"""
        # Remove Device. prefix if present
        if path.startswith('Device.'):
            path = path[7:]

        # Extract first component as domain
        # Handle special cases where domain is multi-part
        parts = path.split('.')
        if not parts or parts[0] == '':
            return 'Unknown'

        domain = parts[0]

        # Special cases for compound domains
        if domain == 'WiFi' and len(parts) > 1:
            if parts[1] in ['AccessPoint', 'EndPoint', 'Radio', 'SSID', 'MultiAP', 'DataElements']:
                return 'WiFi'
        elif domain == 'Cellular' and len(parts) > 1:
            if parts[1] in ['Interface', 'AccessPoint']:
                return 'Cellular'

        return domain

    def get_object_name(self, path: str) -> str:
        """Extract clean object name from path"""
        # Remove Device. prefix
        if path.startswith('Device.'):
            path = path[7:]

        # Remove trailing dot
        path = path.rstrip('.')

        # Remove {i} placeholders for cleaner names
        path = path.replace('.{i}', '')

        # For nested objects, get the last meaningful part
        parts = path.split('.')

        # Build a meaningful name
        if len(parts) == 1:
            return parts[0]
        elif len(parts) == 2:
            return parts[1] if parts[1] else parts[0]
        else:
            # For deeply nested objects, use last two components
            # e.g., Ethernet.Interface.Stats -> Interface_Stats
            # e.g., Ethernet.Link.Stats -> Link_Stats
            # e.g., DHCPv4.Server.Pool -> Server_Pool
            return '_'.join(parts[-2:]) if len(parts) >= 2 else parts[-1]

    def get_dm_type(self, param_info: Dict[str, Any]) -> str:
        """Convert parameter info to dm_type flags"""
        param_type = param_info.get('type', 'unknown')
        access = param_info.get('access', 'readOnly')

        # Map type to dm_type constant
        type_str = self.type_mapping.get(param_type, 'dm_type.STRING')

        # Add access flags
        flags = [type_str]

        if access == 'readWrite':
            flags.append('dm_type.WRITABLE')

        # Join with bitwise OR
        return ' | '.join(flags)

    def generate_schema_object(self, obj_info: Dict[str, Any]) -> tuple:
        """Generate schema and defaults for an object"""
        schema = {}
        defaults = {}

        parameters = obj_info.get('parameters', [])

        for param in parameters:
            param_name = param.get('name', '')
            if not param_name:
                continue

            # Generate schema entry
            dm_type = self.get_dm_type(param)
            schema[param_name] = dm_type

            # Add default if present
            if 'default' in param:
                defaults[param_name] = param['default']
            # For string types without defaults, set empty string
            elif param.get('type') == 'string' or 'dataType:' in param.get('type', ''):
                defaults[param_name] = ""
            # hexBinary/base64 default to empty string (rendered as-is)
            elif param.get('type') in ['hexBinary', 'base64', 'dateTime']:
                defaults[param_name] = ""
            # For numeric types without defaults, set 0
            elif param.get('type') in ['int', 'unsignedInt', 'long', 'unsignedLong']:
                defaults[param_name] = "0"

        return schema, defaults

    def format_ucode_object(self, obj: Dict[str, Any], indent: int = 1) -> str:
        """Format a dictionary as ucode object literal"""
        if not obj:
            return '{}'

        lines = ['{']
        items = list(obj.items())

        for i, (key, value) in enumerate(items):
            # Properly quote keys and handle values
            if isinstance(value, str):
                # Check if it's a dm_type expression (don't quote those)
                if 'dm_type.' in value:
                    formatted_value = value
                else:
                    # Escape quotes in string values
                    escaped_value = value.replace('"', '\\"')
                    formatted_value = f'"{escaped_value}"'
            else:
                formatted_value = json.dumps(value)

            # Add comma except for last item
            comma = ',' if i < len(items) - 1 else ''
            lines.append(f'{"    " * indent}"{key}": {formatted_value}{comma}')

        lines.append('    ' * (indent - 1) + '}')
        return '\n'.join(lines)

    def generate_domain_module(self, domain: str, objects: List[Dict[str, Any]]) -> str:
        """Generate ucode module for a domain"""
        lines = [
            "'use strict';",
            "",
            f"// Auto-generated schema definitions for {domain} domain",
            "// Generated from TR-181 specifications",
            "",
        ]

        # Process each object in the domain
        processed_names = set()
        for obj_data in objects:
            path = obj_data['path']
            obj_name = self.get_object_name(path)

            # Skip duplicates (shouldn't happen with improved naming)
            if obj_name in processed_names:
                print(f"Warning: Duplicate object name '{obj_name}' for path '{path}', skipping")
                continue

            schema, defaults = self.generate_schema_object(obj_data)

            # Skip if no parameters
            if not schema:
                continue

            processed_names.add(obj_name)

            lines.append(f"// Schema for {path}")
            lines.append(f"export const {obj_name} = {{")
            lines.append(f"    path: \"{path}\",")
            lines.append(f"    schema: {self.format_ucode_object(schema, 2)},")

            if defaults:
                lines.append(f"    defaults: {self.format_ucode_object(defaults, 2)}")
            else:
                lines.append("    defaults: {}")

            lines.append("};")
            lines.append("")

        return '\n'.join(lines)

    def load_json_specs(self):
        """Load all JSON specification files"""
        json_files = list(self.json_dir.glob('*.json'))

        for json_file in json_files:
            # Skip index.json - it's metadata, not a schema
            if json_file.name == 'index.json':
                continue
            try:
                with open(json_file, 'r') as f:
                    data = json.load(f)

                # Handle different JSON structures
                if 'object' in data:
                    obj = data['object']
                    if obj and 'path' in obj:
                        domain = self.parse_domain_from_path(obj['path'])
                        self.domains[domain].append(obj)
                elif 'path' in data:
                    domain = self.parse_domain_from_path(data['path'])
                    self.domains[domain].append(data)

            except (json.JSONDecodeError, KeyError) as e:
                print(f"Warning: Could not process {json_file.name}: {e}")
                continue

    def generate_all_modules(self):
        """Generate ucode modules for all domains"""
        # Create output directory if it doesn't exist
        self.output_dir.mkdir(parents=True, exist_ok=True)

        # Load all JSON specs
        print(f"Loading JSON specs from {self.json_dir}")
        self.load_json_specs()

        print(f"Found {len(self.domains)} domains")

        # Generate module for each domain
        generated = []
        for domain, objects in sorted(self.domains.items()):
            if not objects:
                continue

            # Skip empty or unknown domains
            if domain in ['', 'Unknown']:
                continue

            # Generate module content
            module_content = self.generate_domain_module(domain, objects)

            # Write to file
            output_file = self.output_dir / f"{domain}.uc"
            with open(output_file, 'w') as f:
                f.write(module_content)

            generated.append(output_file.name)
            print(f"  ✓ Generated {output_file.name} ({len(objects)} objects)")

        return generated

def main():
    parser = argparse.ArgumentParser(description='Generate ucode schemas from TR-181 JSON specs')
    parser.add_argument('--json-dir', default=str(DM_DIR / 'json_spec'),
                        help='Directory containing JSON specification files')
    parser.add_argument('--output-dir', default=str(DM_DIR / 'json_schema'),
                        help='Output directory for generated ucode modules')
    parser.add_argument('--domain', help='Generate only for specific domain')

    args = parser.parse_args()

    generator = UcodeSchemaGenerator(args.json_dir, args.output_dir)

    if args.domain:
        # Generate for specific domain only
        generator.load_json_specs()
        if args.domain in generator.domains:
            module_content = generator.generate_domain_module(
                args.domain,
                generator.domains[args.domain]
            )
            output_file = Path(args.output_dir) / f"{args.domain}.uc"
            output_file.parent.mkdir(parents=True, exist_ok=True)
            with open(output_file, 'w') as f:
                f.write(module_content)
            print(f"Generated {output_file.name}")
        else:
            print(f"Domain {args.domain} not found")
            return 1
    else:
        # Generate all domains
        generated = generator.generate_all_modules()
        print(f"\nGenerated {len(generated)} schema modules")

    return 0

if __name__ == '__main__':
    exit(main())