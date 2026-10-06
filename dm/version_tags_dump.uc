'use strict';

// Prints the schema exports as JSON: members, their types, version tags,
// rules and table facts, for dm/check_version_tags.py and dm/check_constraints.py. Run from the repository root with a host build
// of src/ucode-mod-ubbf, which defines dm_type:
//   ucode -L "$PWD/files/usr/share/ucode/*.uc" -L "$B/*.so" dm/version_tags_dump.uc

import { glob, basename } from 'fs';

require('ubbf');

const ROOT = sourcepath(0, true) + '/..';
const SCHEMAS_DIR = ROOT + '/files/usr/share/ucode/ubbf/schemas';

let out = [];

function type_name(bits) {
	for (let name, value in dm_type)
		if (name != 'WRITABLE' && value == (bits & ~dm_type.WRITABLE))
			return name;
	return null;
}

function schema_types(schema) {
	let types = {};
	for (let name, bits in schema)
		if (type(bits) == 'int')
			types[name] = type_name(bits);
	return types;
}

function export_add(source, id, def) {
	if (type(def) != 'object' || type(def.schema) != 'object' || !def.path)
		return;

	push(out, {
		source, id,
		path: def.path,
		members: keys(def.schema),
		writable: filter(keys(def.schema), (k) => type(def.schema[k]) == 'int' &&
				 (def.schema[k] & dm_type.WRITABLE)),
		types: schema_types(def.schema),
		since: def.since ?? {},
		until: def.until ?? {},
		constraints: def.constraints ?? {},
		defaults: def.defaults ?? {},
		addable: def.addable ?? true,
		max_instances: def.max_instances
	});
}

for (let file in sort(glob(SCHEMAS_DIR + '/*.uc'))) {
	let name = replace(basename(file), /\.uc$/, '');
	let mod = loadstring(`import * as m from 'ubbf.schemas.${name}'; return m;`)();

	for (let key, def in mod)
		export_add(file, `${name}.${key}`, def);
}

for (let file in sort(glob(ROOT + '/modules/*/schema.uc'))) {
	let schemas = {};

	include(file, { schemas });

	for (let key, def in schemas)
		export_add(file, `${split(file, '/')[-2]}.${key}`, def);
}

printf('%J\n', out);
