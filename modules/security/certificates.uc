'use strict';

// Included with { certificates } as the scope, by handler.uc in the agent and
// by the syslog and userinterface modules, so all of them number the
// certificates the same way. Each function is added to that object.

const fs = require('fs');
const openssl = require('openssl');
const ubbf = require('ubbf');

// A stored reference, for example Syslog Network.Certificate, must keep its
// certificate when the CA store changes (TR-369 R-ARC.8), so the instance
// numbers come from this map and are never given to another certificate.
const INSTANCES_PATH = '/etc/ubbf/security-instances.json';
const INSTANCES_LOCK = '/var/run/ubbf-security-instances.lock';
const CAFILE_DIR = '/var/run/ubbf-security';

// Certificates with their keys from AddCertificateBundle(), and CA bundles
// from AddCABundle(), one directory each (TR-181 2.21).
const CERTS_DIR = '/etc/ubbf/certs';
const CABUNDLES_DIR = '/etc/ubbf/cabundles';
const CABUNDLE_FILE = 'bundle.pem';
const CABUNDLE_NUMBERS_PATH = '/etc/ubbf/security-cabundles.json';
const ALIASES_PATH = '/etc/ubbf/security-aliases.json';

// The CA bundles the device brings, as CABundle 1 and 2. A CA bundle added
// by a controller gets a number above them from CABUNDLE_NUMBERS_PATH.
const BUNDLE_SOURCES = [
	{ path: '/etc/ssl/certs', bundle: 'system-ca', file: '/etc/ssl/certs/ca-certificates.crt' },
	{ path: '/etc/ubbf/ca', bundle: 'local-ca' },
];

// The device certificates: they are Certificate rows, but no CA bundle
// trusts them.
const DEVICE_SOURCES = [
	{ path: '/etc/ubbf', pattern: /\.pem$/ },
	{ path: CERTS_DIR, pattern: /\.pem$/ },
];

const NAME_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/;
const ALIAS_PATTERN = /^[A-Za-z][A-Za-z0-9._-]{0,63}$/;

// TR-181 2.21 fault codes of the Security commands.
const ERR_BUNDLE_FORMAT = 7260;
const ERR_IMPORT_BUNDLE = 7262;
const ERR_IMPORT_CERTIFICATE = 7263;
const ERR_IMPORT_KEY = 7264;
const ERR_PEM_FORMAT = 7265;
const ERR_DISK_SPACE = 7266;
const ERR_DUPLICATE_BUNDLE = 7267;
const ERR_IDENTITY_CONFLICT = 7270;
const ERR_COMMAND_FAILURE = 7022;
const ERR_INVALID_ARGS = 7027;

/**
 * Parses the PEM files of a source directory. Symbolic links are skipped:
 * the hash links of a CA store point at files that the scan reads anyway.
 *
 * @param {object} source - Entry of CERT_SOURCES
 * @returns {array} { path, mtime, certs } for each file with a certificate
 */
function dir_scan(source) {
	let files = [];

	for (let name in sort(fs.lsdir(source.path) ?? [])) {
		if (source.pattern && !match(name, source.pattern))
			continue;

		let path = source.path + '/' + name;
		let st = fs.lstat(path);
		if (st?.type != 'file')
			continue;

		let certs = openssl.cert_parse_file(path);
		if (certs)
			push(files, { path, mtime: st.mtime, certs });
	}

	return files;
}

/**
 * Adds a certificate to the scan, once. The table has one row for each
 * certificate, and Issuer with SerialNumber is its unique key.
 *
 * A certificate alone in its file is known by the path, so a renewed
 * certificate keeps its row; one in a file of several by its fingerprint.
 *
 * @param {object} found - Scan state { certs, by_fingerprint, by_id }
 * @param {object} file - File from dir_scan()
 * @param {object} cert - Certificate from openssl.cert_parse_file()
 * @returns {object|null} The row, or null for a second certificate with
 *                        the Issuer and SerialNumber of another
 */
function entry_add(found, file, cert) {
	let entry = found.by_fingerprint[cert.fingerprint];
	if (entry)
		return entry;

	let id = `${cert.issuer}|${cert.serial}`;
	if (found.by_id[id])
		return null;

	entry = {
		...cert,
		path: file.path,
		last_modif: ubbf.iso8601_format(file.mtime),
		key: (length(file.certs) == 1) ? `file:${file.path}` : `sha256:${cert.fingerprint}`
	};

	found.by_fingerprint[cert.fingerprint] = entry;
	found.by_id[id] = entry;
	push(found.certs, entry);

	return entry;
}

/**
 * Adds the certificates of a source to the scan.
 *
 * A CA of the system store is in its own file and again in
 * ca-certificates.crt; the files with one certificate go first, so that the
 * row has the path of its own file.
 *
 * @param {object} source - Entry of CERT_SOURCES
 * @param {object} found - Scan state
 * @returns {array} The rows of the certificates of this source
 */
function source_collect(source, found) {
	let files = dir_scan(source);
	let ordered = [
		...filter(files, (f) => length(f.certs) == 1),
		...filter(files, (f) => length(f.certs) > 1)
	];
	let members = [];

	for (let file in ordered) {
		for (let cert in file.certs) {
			let entry = entry_add(found, file, cert);
			if (entry && index(members, entry) < 0)
				push(members, entry);
		}
	}

	return members;
}

/**
 * Reads a JSON map, for example of certificate keys to instance numbers.
 *
 * @param {string} path - File of the map
 * @returns {object} The map, empty when the file is missing or not valid
 */
function map_load(path) {
	let data = fs.readfile(path);
	if (data == null)
		return {};

	try {
		let map = json(data);
		if (type(map) == 'object')
			return map;
	} catch (e) {
	}

	warn(`security: ${path} is not valid, its entries are lost\n`);
	return {};
}

/**
 * Writes a JSON map in place of the old one.
 *
 * @param {string} path - File of the map
 * @param {object} map - The map
 */
function map_save(path, map) {
	let tmp = path + '.tmp';
	if (fs.writefile(tmp, sprintf('%J\n', map)) == null || !fs.rename(tmp, path))
		warn(`security: cannot write ${path}\n`);
}

/**
 * Gives the next free instance numbers to new keys and saves the map. The
 * agent and apply both scan, so the lock keeps them from giving one number
 * twice. A number is never given again, also after its row is deleted.
 *
 * @param {string} path - File of the map
 * @param {array} keys - Keys without a number
 * @param {number} first - Lowest number to give
 * @returns {object} The updated map
 */
function numbers_allocate(path, keys, first) {
	let lock = fs.open(INSTANCES_LOCK, 'w');
	lock?.lock('x');

	let numbers = map_load(path);
	let next = first;

	for (let key, num in numbers)
		if (num >= next)
			next = num + 1;

	for (let key in keys)
		if (!(key in numbers))
			numbers[key] = next++;

	map_save(path, numbers);
	lock?.close();

	return numbers;
}

/**
 * Lists the CA bundles that AddCABundle() installed, as scan sources.
 *
 * @returns {array} Sources sorted by name
 */
function added_bundle_sources() {
	let sources = [];

	for (let name in sort(fs.lsdir(CABUNDLES_DIR) ?? [])) {
		let path = `${CABUNDLES_DIR}/${name}`;
		if (!match(name, NAME_PATTERN) || fs.lstat(path)?.type != 'directory')
			continue;

		push(sources, { path, bundle: name, file: `${path}/${CABUNDLE_FILE}`, added: true });
	}

	return sources;
}

/**
 * Scans all certificate sources from disk.
 *
 * @returns {object} { certs: rows sorted by instance, bundles: array of
 *                   { instance, name, path, file, members } }
 */
function certs_scan_live() {
	let found = { certs: [], by_fingerprint: {}, by_id: {} };
	let bundles = [];
	let added = added_bundle_sources();

	for (let source in [ ...BUNDLE_SOURCES, ...added, ...DEVICE_SOURCES ]) {
		let members = source_collect(source, found);
		if (!source.bundle)
			continue;

		push(bundles, {
			instance: source.added ? null : length(bundles) + 1,
			name: source.bundle,
			path: source.path,
			file: source.file,
			added: source.added ?? false,
			members
		});
	}

	let numbers = map_load(INSTANCES_PATH);
	let missing = map(filter(found.certs, (e) => !(e.key in numbers)), (e) => e.key);
	if (length(missing))
		numbers = numbers_allocate(INSTANCES_PATH, missing, 1);

	let aliases = map_load(ALIASES_PATH);
	for (let entry in found.certs) {
		entry.instance = numbers[entry.key];
		entry.alias = aliases[entry.key];
		entry.added = index(entry.path, CERTS_DIR + '/') == 0;
	}

	let bundle_numbers = map_load(CABUNDLE_NUMBERS_PATH);
	let unnumbered = map(filter(added, (s) => !(s.bundle in bundle_numbers)), (s) => s.bundle);
	if (length(unnumbered))
		bundle_numbers = numbers_allocate(CABUNDLE_NUMBERS_PATH, unnumbered, length(BUNDLE_SOURCES) + 1);

	for (let bundle in bundles)
		bundle.instance ??= bundle_numbers[bundle.name];

	return {
		certs: sort(found.certs, (a, b) => a.instance - b.instance),
		bundles: sort(bundles, (a, b) => a.instance - b.instance)
	};
}

/**
 * Finds the Certificate row with an instance number.
 *
 * @param {object} scan - Result of certs_scan_live()
 * @param {number} instance - Instance number
 * @returns {object|null} The row, or null
 */
function certificate_find(scan, instance) {
	for (let entry in scan.certs)
		if (entry.instance == instance)
			return entry;

	return null;
}

/**
 * Finds the CABundle row with an instance number.
 *
 * @param {object} scan - Result of certs_scan_live()
 * @param {number} instance - Instance number
 * @returns {object|null} The bundle, or null
 */
function cabundle_find(scan, instance) {
	for (let bundle in scan.bundles)
		if (bundle.instance == instance)
			return bundle;

	return null;
}

/**
 * Resolves a Device.Security.Certificate.{i}. reference to its file.
 *
 * @param {string} ref - TR-181 path like 'Device.Security.Certificate.3.'
 * @returns {string|null} Path of the PEM file, or null
 */
function certificate_path_resolve(ref) {
	let m = (type(ref) == 'string') ? match(ref, /^Device\.Security\.Certificate\.([0-9]+)\.?$/) : null;
	if (!m)
		return null;

	return certificate_find(certs_scan_live(), +m[1])?.path;
}

/**
 * Returns the private key of a certificate file: the `.key` file next to
 * it, as pkgen writes the device certificate, or the file itself when it
 * holds the key. TR-181 has no parameter for the key.
 *
 * @param {string} cert - Path of the certificate PEM
 * @returns {string|null} Path of the key, or null when there is none
 */
function certificate_key_path(cert) {
	let sibling = replace(cert, /\.(pem|crt)$/, '.key');
	if (sibling != cert && fs.access(sibling, 'r'))
		return sibling;

	return (index(fs.readfile(cert) ?? '', 'PRIVATE KEY-----') >= 0) ? cert : null;
}

/**
 * Returns the Name of a Certificate row (TR-181 2.21): the base name of its
 * file without the extension, at most 64 characters.
 *
 * @param {object} cert - Row from certs_scan_live()
 * @returns {string} Name
 */
function certificate_name(cert) {
	let base = replace(cert.path ?? '', /^.*\//, '');
	return substr(replace(base, /\.[^.]*$/, ''), 0, 64);
}

/**
 * Resolves a Device.Security.CABundle.{i}. reference to its directory. A
 * bundle without a certificate does not resolve: uwsd and ubbf-logd refuse
 * a CA directory with no certificate in it.
 *
 * @param {string} ref - TR-181 path like 'Device.Security.CABundle.2.'
 * @returns {string|null} Directory of the bundle, or null
 */
function cabundle_path_resolve(ref) {
	let m = (type(ref) == 'string') ? match(ref, /^Device\.Security\.CABundle\.([0-9]+)\.?$/) : null;
	if (!m)
		return null;

	let bundle = cabundle_find(certs_scan_live(), +m[1]);

	return length(bundle?.members) ? bundle.path : null;
}

/**
 * Returns a file with all certificates of a bundle: the bundle file of the
 * store when it has one, else a file written from the certificates of the
 * bundle. A file of the directory can also hold a private key, which must
 * not reach the written file.
 *
 * @param {object} bundle - Bundle from certs_scan_live()
 * @returns {string|null} Path of the file, or null
 */
function cabundle_file_build(bundle) {
	if (!length(bundle.members))
		return null;

	if (bundle.file && fs.access(bundle.file, 'r'))
		return bundle.file;

	let wanted = {};
	for (let entry in bundle.members)
		wanted[entry.fingerprint] = true;

	let pems = [];
	for (let path in uniq(map(bundle.members, (e) => e.path))) {
		for (let cert in openssl.cert_pem_read(path) ?? []) {
			if (!wanted[cert.fingerprint])
				continue;
			delete wanted[cert.fingerprint];
			push(pems, cert.pem);
		}
	}

	let path = `${CAFILE_DIR}/${bundle.name}.pem`;
	let tmp = path + '.tmp';

	fs.mkdir(CAFILE_DIR, 0755);
	if (fs.writefile(tmp, join('', pems)) == null || !fs.rename(tmp, path)) {
		fs.unlink(tmp);
		return null;
	}

	return path;
}

/**
 * Returns the Alias of a Certificate row: the one AddCertificateBundle()
 * set, else cpe-cert-<instance>.
 *
 * @param {object} cert - Row from certs_scan_live()
 * @returns {string} Alias
 */
function certificate_alias(cert) {
	return cert.alias ?? sprintf('cpe-cert-%d', cert.instance);
}

/**
 * Decodes the hexBinary Bundle argument of a Security command.
 *
 * @param {string} bundle - Hex digits
 * @returns {string|null} The bytes, or null when the value is not hex
 */
function bundle_decode(bundle) {
	if (type(bundle) != 'string' || bundle == '' || length(bundle) % 2)
		return null;

	return hexdec(bundle);
}

/**
 * Writes a file that only its owner can read: it is made empty and closed
 * to others before any data goes in.
 *
 * @param {string} path - File to write
 * @param {string} data - Content
 * @returns {number|null} 0 on success, else a fault code
 */
function private_file_write(path, data) {
	if (fs.writefile(path, '') == null || !fs.chmod(path, 0600))
		return ERR_IMPORT_BUNDLE;

	if (fs.writefile(path, data) == null)
		return match(fs.error() ?? '', /space/i) ? ERR_DISK_SPACE : ERR_IMPORT_BUNDLE;

	return 0;
}

/**
 * Installs a certificate with its private key (Device.Security.
 * AddCertificateBundle(), TR-181 2.21) as CERTS_DIR/<name>.pem. A file of
 * the same Name is replaced, so the row keeps its instance number.
 *
 * @param {object} input - Alias, Name, BundleFormat, Bundle
 * @returns {object} { instance } or { error: fault code }
 */
function certificate_add(input) {
	let name = input?.Name;
	let alias = input?.Alias;

	if (input?.BundleFormat != 'PEM')
		return { error: ERR_BUNDLE_FORMAT };
	if (!match(name ?? '', NAME_PATTERN) || (alias != null && alias != '' && !match(alias, ALIAS_PATTERN)))
		return { error: ERR_INVALID_ARGS };

	let data = bundle_decode(input?.Bundle);
	if (!data)
		return { error: ERR_IMPORT_BUNDLE };

	let path = `${CERTS_DIR}/${name}.pem`;
	let scan = certs_scan_live();

	for (let entry in scan.certs) {
		if (entry.path == path)
			continue;
		if (certificate_name(entry) == name)
			return { error: ERR_COMMAND_FAILURE };
		if (alias && certificate_alias(entry) == alias)
			return { error: ERR_INVALID_ARGS };
	}

	fs.mkdir(CERTS_DIR, 0700);
	let tmp = `${CERTS_DIR}/.${name}.tmp`;
	let err = private_file_write(tmp, data);
	let check = err ? null : openssl.key_check(tmp);
	let leaf = check?.certificate ? openssl.cert_parse_file(tmp)?.[0] : null;

	if (!err && !leaf)
		err = ERR_IMPORT_CERTIFICATE;
	else if (!err && !check.match)
		err = ERR_IMPORT_KEY;

	for (let entry in (err ? [] : scan.certs))
		if (entry.path != path && entry.issuer == leaf.issuer && entry.serial == leaf.serial)
			err = ERR_IDENTITY_CONFLICT;

	if (err || !fs.rename(tmp, path)) {
		fs.unlink(tmp);
		return { error: err || ERR_IMPORT_BUNDLE };
	}

	let row = filter(certs_scan_live().certs, (e) => e.path == path && e.fingerprint == leaf.fingerprint)[0];
	if (row && alias) {
		let aliases = map_load(ALIASES_PATH);
		aliases[row.key] = alias;
		map_save(ALIASES_PATH, aliases);
	}

	return row ? { instance: row.instance } : { error: ERR_IMPORT_BUNDLE };
}

/**
 * Deletes a certificate that AddCertificateBundle() installed. Other
 * certificates come with the firmware or the CA store and stay.
 *
 * @param {number} instance - Certificate instance number
 * @returns {number} 0, or a fault code
 */
function certificate_delete(instance) {
	let cert = certificate_find(certs_scan_live(), instance);
	if (!cert?.added || !fs.unlink(cert.path))
		return ERR_COMMAND_FAILURE;

	let aliases = map_load(ALIASES_PATH);
	if (cert.key in aliases) {
		delete aliases[cert.key];
		map_save(ALIASES_PATH, aliases);
	}

	return 0;
}

/**
 * Checks the Bundle argument of AddCABundle() and Update() and writes it to
 * a file: CA certificates in PEM, and no private key.
 *
 * @param {string} hex - Bundle argument
 * @param {string} path - File to write
 * @returns {object} { count } or { error: fault code }
 */
function cabundle_write(hex, path) {
	let data = bundle_decode(hex);
	if (!data || index(data, 'PRIVATE KEY') >= 0)
		return { error: ERR_IMPORT_BUNDLE };

	let tmp = path + '.tmp';
	if (fs.writefile(tmp, data) == null) {
		let err = match(fs.error() ?? '', /space/i) ? ERR_DISK_SPACE : ERR_IMPORT_BUNDLE;
		fs.unlink(tmp);
		return { error: err };
	}

	let certs = openssl.cert_parse_file(tmp);
	if (!certs || !fs.rename(tmp, path)) {
		fs.unlink(tmp);
		return { error: certs ? ERR_IMPORT_BUNDLE : ERR_PEM_FORMAT };
	}

	return { count: length(certs) };
}

/**
 * Installs a CA bundle (Device.Security.AddCABundle(), TR-181 2.21) in a
 * directory of its own, so that CADir() and CAFile() serve it.
 *
 * @param {object} input - Name, Bundle
 * @returns {object} { instance, count } or { error: fault code }
 */
function cabundle_add(input) {
	let name = input?.Name;
	if (!match(name ?? '', NAME_PATTERN))
		return { error: ERR_INVALID_ARGS };

	for (let bundle in certs_scan_live().bundles)
		if (bundle.name == name)
			return { error: ERR_DUPLICATE_BUNDLE };

	let dir = `${CABUNDLES_DIR}/${name}`;
	fs.mkdir(CABUNDLES_DIR, 0755);
	if (!fs.mkdir(dir, 0755))
		return { error: ERR_IMPORT_BUNDLE };

	let result = cabundle_write(input?.Bundle, `${dir}/${CABUNDLE_FILE}`);
	if (result.error) {
		fs.rmdir(dir);
		return result;
	}

	let bundle = filter(certs_scan_live().bundles, (b) => b.name == name)[0];

	return { instance: bundle.instance, count: result.count };
}

/**
 * Replaces the certificates of a CA bundle that AddCABundle() installed
 * (CABundle.{i}.Update(), TR-181 2.21); on a failure the old ones stay.
 *
 * @param {number} instance - CABundle instance number
 * @param {object} input - Bundle
 * @returns {object} { count } or { error: fault code }
 */
function cabundle_update(instance, input) {
	let bundle = cabundle_find(certs_scan_live(), instance);
	if (!bundle?.added)
		return { error: ERR_COMMAND_FAILURE };

	return cabundle_write(input?.Bundle, bundle.file);
}

/**
 * Deletes a CA bundle that AddCABundle() installed (CABundle.{i}.Delete(),
 * TR-181 2.21). Its instance number stays taken, under a key that no name
 * can have, so a new bundle of the same name gets a new number.
 *
 * @param {number} instance - CABundle instance number
 * @returns {number} 0, or a fault code
 */
function cabundle_delete(instance) {
	let bundle = cabundle_find(certs_scan_live(), instance);
	if (!bundle?.added)
		return ERR_COMMAND_FAILURE;

	for (let name in fs.lsdir(bundle.path) ?? [])
		fs.unlink(`${bundle.path}/${name}`);
	if (!fs.rmdir(bundle.path))
		return ERR_COMMAND_FAILURE;

	let lock = fs.open(INSTANCES_LOCK, 'w');
	lock?.lock('x');
	let numbers = map_load(CABUNDLE_NUMBERS_PATH);
	numbers[sprintf('#%d', bundle.instance)] = bundle.instance;
	delete numbers[bundle.name];
	map_save(CABUNDLE_NUMBERS_PATH, numbers);
	lock?.close();

	return 0;
}

certificates.scan = certs_scan_live;
certificates.certificate_find = certificate_find;
certificates.cabundle_find = cabundle_find;
certificates.certificate_path_resolve = certificate_path_resolve;
certificates.certificate_key_path = certificate_key_path;
certificates.certificate_name = certificate_name;
certificates.certificate_alias = certificate_alias;
certificates.certificate_add = certificate_add;
certificates.certificate_delete = certificate_delete;
certificates.cabundle_add = cabundle_add;
certificates.cabundle_update = cabundle_update;
certificates.cabundle_delete = cabundle_delete;
certificates.cabundle_path_resolve = cabundle_path_resolve;
certificates.cabundle_file_build = cabundle_file_build;
