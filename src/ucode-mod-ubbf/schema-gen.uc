'use strict';

// Compiles TR-181 schema definitions into the read-only tables that schema.c
// loads from the schema-*.so files.
//
// Usage: ucode -L '<ucode dir>/*.uc' schema-gen.uc <ubbf.h> <schemas dir> <output> [<module> <schema.uc>]
//
// Without <module> it writes the core table: each `<Module>.<Export>` of
// schemas/*.uc becomes one object record keyed by that name, because two
// exports may describe the same path and one export describes no path at
// all. With <module> it writes the table of that module: each
// `schemas.<Key>` its schema.uc sets becomes the record `<module>.<Key>`.
// Strings live once in a pool and records refer to them by offset, so the
// tables need no relocations and stay in file-backed pages of the .so.

import { readfile, writefile, glob, basename } from 'fs';
import { tag_minor } from 'ubbf.utils.dm-version';

const NONE = 0xffffffff;
const COMMAND_TYPES = { sync: true, async: true, event: true };
const PROTOCOLS = { usp: 0, cwmp: 1, both: 2 };
const PROTO_ANY = 3;

let header_path = ARGV[0];
let schemas_dir = ARGV[1];
let out_path = ARGV[2];
let module_name = ARGV[3];
let module_path = ARGV[4];

function fail(msg) {
	warn(`schema-gen: ${msg}\n`);
	exit(1);
}

function dm_types_parse(path) {
	let types = {};

	for (let line in split(readfile(path) ?? fail(`cannot read ${path}`), '\n')) {
		let m = match(line, /^#define DM_([A-Z0-9_]+)[ \t]+(0x[0-9a-fA-F]+)/);
		if (m)
			types[m[1]] = hex(m[2]);
	}

	if (!types.WRITABLE)
		fail(`no DM_WRITABLE in ${path}`);

	return types;
}

function modules_load(dir) {
	let names = map(sort(glob(dir + '/*.uc')), (f) => replace(basename(f), /\.uc$/, ''));
	let src = '';

	for (let n in names)
		src += `import * as m_${n} from 'ubbf.schemas.${n}';\n`;

	src += 'return { ' + join(', ', map(names, (n) => `${n}: m_${n}`)) + ' };\n';

	return loadstring(src)();
}

// schema.c tells a module table from the core table by the prefix of the
// name, and the core table is called core.
function module_load(name, path) {
	if (!match(name, /^[a-z0-9_]+$/) || name == 'core')
		fail(`module name ${name}: needs lower case letters, digits or _, and not core`);

	let schemas = {};
	include(path, { schemas });

	return { [name]: schemas };
}

let pool = '';
let pool_offsets = {};

function str_add(s) {
	if (s == null)
		return NONE;

	if (exists(pool_offsets, s))
		return pool_offsets[s];

	if (index(s, '\0') >= 0)
		fail(`NUL byte in ${s}`);

	let off = length(pool);
	pool_offsets[s] = off;
	pool += s + '\0';

	return off;
}

function c_string(s) {
	let out = '';

	for (let i = 0; i < length(s); i++) {
		let c = ord(s, i);

		if (c == 34 || c == 92)
			out += '\\' + chr(c);
		else if (c < 32 || c > 126)
			out += sprintf('\\%03o', c);
		else
			out += chr(c);
	}

	return out;
}

function pool_emit() {
	let lines = [];

	// One literal per string keeps the file readable and each line short;
	// the explicit "\0" ends every string inside the concatenation.
	for (let s in sort(keys(pool_offsets), (a, b) => pool_offsets[a] - pool_offsets[b]))
		push(lines, `\t"${c_string(s)}\\0"`);

	return join('\n', lines);
}

let dm_types = dm_types_parse(header_path);
global.dm_type = dm_types;

let mods = module_name ? module_load(module_name, module_path) : modules_load(schemas_dir);

let objects = [];

for (let mod_name, mod in mods) {
	for (let export_name, def in mod) {
		if (type(def) != 'object' || type(def.schema) != 'object')
			fail(`${mod_name}.${export_name} is not a schema`);

		push(objects, { id: `${mod_name}.${export_name}`, def });
	}
}

if (!length(objects))
	fail(`no schema in ${module_path ?? schemas_dir}`);

objects = sort(objects, (a, b) => (a.id < b.id) ? -1 : (a.id > b.id) ? 1 : 0);

let members = [];
let defaults = [];
let object_rows = [];
let rules = [];
let ranges = [];
let enums = [];

// Flags of struct schema_rule in schema-table.h.
const RULE_FLAGS = {
	min: 0x0001, max: 0x0002, min_length: 0x0004, max_length: 0x0008,
	list: 0x0010, list_min_length: 0x0020, list_max_length: 0x0040,
	secured: 0x0080
};
const RULE_KEYS = { ...RULE_FLAGS, enum: true, ranges: true, lengths: true };

function int_check(where, v) {
	if (type(v) != 'int')
		fail(`${where} is ${type(v)}, not an integer`);
	return v;
}

// Appends [lo, hi] pairs to `ranges`; null stands for an open end.
function ranges_add(where, list) {
	if (type(list) != 'array' || !length(list))
		fail(`${where} is not a list of [lo, hi]`);

	let first = length(ranges);

	for (let r in list) {
		if (type(r) != 'array' || length(r) != 2)
			fail(`${where}: ${r} is not [lo, hi]`);
		push(ranges, [ r[0] == null ? null : int_check(where, r[0]),
			       r[1] == null ? null : int_check(where, r[1]) ]);
	}

	return [ first, length(list) ];
}

// Compiles the `constraints` entry of one parameter into a rule record and
// returns its index, or NONE when the parameter has no rules.
function rule_row(where, facts) {
	if (facts == null)
		return NONE;
	if (type(facts) != 'object')
		fail(`${where} is ${type(facts)}, not an object`);

	let row = {
		min: 0, max: 0, min_length: 0, max_length: 0, list_min_length: 0,
		list_max_length: 0, enum_first: 0, enum_count: 0, range_first: 0,
		range_count: 0, length_first: 0, length_count: 0, flags: 0
	};

	for (let key, value in facts) {
		if (!RULE_KEYS[key])
			fail(`${where}: unknown key ${key}`);

		// null takes back a fact, as in min: null next to ranges.
		if (value == null)
			continue;

		if (key == 'list' || key == 'secured') {
			if (type(value) != 'bool')
				fail(`${where}.${key} is ${type(value)}, not a boolean`);
			if (value)
				row.flags |= RULE_FLAGS[key];
		}
		else if (key == 'enum') {
			if (type(value) != 'array' || !length(value))
				fail(`${where}.enum is not a list of strings`);
			row.enum_first = length(enums);
			row.enum_count = length(value);
			for (let e in value) {
				if (type(e) != 'string')
					fail(`${where}.enum: ${e} is not a string`);
				push(enums, str_add(e));
			}
		}
		else if (key == 'ranges') {
			let r = ranges_add(`${where}.ranges`, value);
			row.range_first = r[0];
			row.range_count = r[1];
		}
		else if (key == 'lengths') {
			let r = ranges_add(`${where}.lengths`, value);
			row.length_first = r[0];
			row.length_count = r[1];
		}
		else {
			row[key] = int_check(`${where}.${key}`, value);
			row.flags |= RULE_FLAGS[key];
		}
	}

	push(rules, row);
	return length(rules) - 1;
}

// A table export may state `addable: false` and `max_instances: <n>`.
function table_facts(id, def) {
	let table = match(def.path ?? '', /\.\{i\}\.$/) != null;

	if (def.addable != null && (def.addable !== false || !table))
		fail(`${id}.addable: only false, and only on a table`);
	if (def.max_instances != null &&
	    (type(def.max_instances) != 'int' || def.max_instances < 0 || !table))
		fail(`${id}.max_instances: a count, and only on a table`);

	for (let name in keys(def.constraints ?? {}))
		if (!exists(def.schema, name))
			fail(`${id}.constraints.${name}: no such member`);

	return {
		addable: def.addable === false ? 0 : 1,
		max_instances: def.max_instances ?? NONE
	};
}

// A `since` or `until` table of an export maps member names to version
// tags such as '2.21'.
function version_tags_check(id, def) {
	for (let key in [ 'since', 'until' ]) {
		let tags = def[key];

		if (tags == null)
			continue;
		if (type(tags) != 'object')
			fail(`${id}.${key} is ${type(tags)}, not an object`);

		for (let name, tag in tags) {
			if (!exists(def.schema, name))
				fail(`${id}.${key}.${name}: no such member`);
			if (tag_minor(tag) == null || tag_minor(tag) > 255)
				fail(`${id}.${key}.${name}: tag ${tag} is not 2.<minor>`);
		}
	}
}

function version_tag(def, key, name) {
	let tag = def[key]?.[name];

	return tag == null ? 0 : tag_minor(tag);
}

function member_row(id, def, name, value) {
	let since = version_tag(def, 'since', name);
	let until = version_tag(def, 'until', name);

	if (type(value) == 'object') {
		if (!COMMAND_TYPES[value.type])
			fail(`${name}: unknown member type ${value.type}`);

		let proto = value.protocol ?? 'usp';
		if (!exists(PROTOCOLS, proto))
			fail(`${name}: unknown protocol ${proto}`);

		return { name: str_add(name), type: 0, info: str_add(sprintf('%J', value)),
			 kind: 1, proto: PROTOCOLS[proto], since, until };
	}

	if (type(value) != 'int')
		fail(`${name}: member is ${type(value)}`);

	return { name: str_add(name), type: value,
		 info: rule_row(`${id}.constraints.${name}`, def.constraints?.[name]),
		 kind: 0, proto: PROTO_ANY, since, until };
}

for (let obj in objects) {
	let def = obj.def;

	version_tags_check(obj.id, def);

	let row = {
		id: str_add(obj.id),
		path: str_add(def.path),
		member_first: length(members),
		default_first: length(defaults),
		...table_facts(obj.id, def)
	};

	for (let name, value in def.schema)
		push(members, member_row(obj.id, def, name, value));

	for (let name, value in (def.defaults ?? {})) {
		if (type(value) != 'string')
			fail(`${obj.id}.${name}: default is ${type(value)}`);
		if (!exists(def.schema, name))
			fail(`${obj.id}.${name}: default without a member`);

		push(defaults, { name: str_add(name), value: str_add(value) });
	}

	row.member_count = length(members) - row.member_first;
	row.default_count = length(defaults) - row.default_first;
	push(object_rows, row);
}

// Every array ends in a zero row, because C has no empty arrays and a table
// may have no defaults or no rules.
function array_emit(out, decl, rows, zero) {
	push(out, `${decl}[] = {`);

	for (let row in rows)
		push(out, row);

	push(out, zero ?? '\t{ 0 }', '};', '');
}

function int64_text(v, open) {
	return v == null ? open : sprintf('%dLL', v);
}

let source = module_name ? `modules/${module_name}/schema.uc` : 'the schemas/ directory';

let out = [
	`/* Generated by schema-gen.uc from ${source}. Do not edit. */`,
	'',
	'#include <stdint.h>',
	'#include "schema-table.h"',
	'',
	'/* The pool is one literal well past the 4095 bytes C99 guarantees; GCC and',
	' * Clang accept it, and splitting it would break the offsets. */',
	'#pragma GCC diagnostic ignored "-Woverlength-strings"',
	'',
	'const uint32_t ubbf_schema_abi = SCHEMA_TABLE_ABI;',
	`const uint32_t ubbf_schema_object_count = ${length(object_rows)};`,
	'',
	'const char ubbf_schema_pool[] =',
	pool_emit() + ';',
	''
];

array_emit(out, 'const struct schema_object ubbf_schema_objects',
	map(object_rows, (r) => sprintf('\t{ %du, %du, %d, %d, %d, %d, %du, %d },', r.id, r.path,
					r.member_first, r.member_count, r.default_first, r.default_count,
					r.max_instances, r.addable)));

array_emit(out, 'const struct schema_member ubbf_schema_members',
	map(members, (m) => sprintf('\t{ %du, 0x%08xu, %du, %d, %d, %d, %d },',
				    m.name, m.type, m.info, m.kind, m.proto, m.since, m.until)));

array_emit(out, 'const struct schema_default ubbf_schema_defaults',
	map(defaults, (d) => sprintf('\t{ %du, %du },', d.name, d.value)));

array_emit(out, 'const struct schema_rule ubbf_schema_rules',
	map(rules, (r) => sprintf('\t{ %s, %s, %du, %du, %du, %du, %d, %d, %d, %d, %d, %d, 0x%04x },',
				  int64_text(r.min, '0'), int64_text(r.max, '0'),
				  r.min_length, r.max_length, r.list_min_length, r.list_max_length,
				  r.enum_first, r.range_first, r.length_first,
				  r.enum_count, r.range_count, r.length_count, r.flags)));

array_emit(out, 'const struct schema_range ubbf_schema_ranges',
	map(ranges, (r) => sprintf('\t{ %s, %s },', int64_text(r[0], 'INT64_MIN'),
				   int64_text(r[1], 'INT64_MAX'))));

array_emit(out, 'const uint32_t ubbf_schema_enums',
	map(enums, (e) => sprintf('\t%du,', e)), '\t0');

if (!writefile(out_path, join('\n', out)))
	fail(`cannot write ${out_path}`);
