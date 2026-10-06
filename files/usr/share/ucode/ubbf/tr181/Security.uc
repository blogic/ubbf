'use strict';

import * as fs from 'fs';
import { cert_parse_file } from 'openssl';
import * as schemas from 'ubbf.schemas.Security';
import * as ubbf from 'ubbf';

const CERT_BUNDLES = [
	{ path: '/etc/ssl/certs', name: 'system-ca' },
	{ path: '/etc/ubbf', name: 'local-ca' },
];

/**
 * Scans a directory for PEM files and returns all parsed certificates.
 *
 * @param {string} dir - Directory path to scan
 * @returns {array} Array of certificate objects with file metadata
 */
function dir_scan(dir) {
	let entries = fs.lsdir(dir);
	if (!entries)
		return [];

	let certs = [];

	for (let name in sort(entries)) {
		let path = dir + '/' + name;
		let st = fs.stat(path);

		if (!st || st.type != 'file')
			continue;

		let parsed = cert_parse_file(path);
		if (!parsed)
			continue;

		let mtime = ubbf.iso8601_format(st.mtime);

		for (let cert in parsed) {
			cert.last_modif = mtime;
			cert.path = path;
			cert.dir = dir;
			push(certs, cert);
		}
	}

	return certs;
}

/**
 * Scans all configured certificate directories from disk.
 *
 * @returns {object} { certs: flat array, bundles: array of { name, start, end } }
 */
function certs_scan_live() {
	let all_certs = [];
	let bundles = [];

	for (let entry in CERT_BUNDLES) {
		let certs = dir_scan(entry.path);
		if (!length(certs))
			continue;

		let start = length(all_certs) + 1;

		for (let cert in certs)
			push(all_certs, cert);

		push(bundles, { name: entry.name, path: entry.path, start, end: length(all_certs) });
	}

	return { certs: all_certs, bundles };
}

let cached_scan;

/**
 * Returns the cached certificate scan populated at module load.
 *
 * @returns {object} Cached { certs, bundles } structure from certs_scan_live()
 */
function certs_scan() {
	return cached_scan;
}

/**
 * Resolves a Device.Security.Certificate.{i}. ref to its on-disk path.
 *
 * @param {string} ref - TR-181 path like 'Device.Security.Certificate.3.'
 * @returns {string|null} Filesystem path of the cert PEM, or null
 */
export function certificate_path_resolve(ref) {
	if (type(ref) != 'string')
		return null;
	let m = match(ref, /\.([0-9]+)\.?$/);
	if (!m)
		return null;
	let inst = +m[1];
	let scan = cached_scan ?? certs_scan_live();
	if (inst < 1 || inst > length(scan.certs))
		return null;
	return scan.certs[inst - 1].path ?? null;
};

/**
 * Resolves a Device.Security.CABundle.{i}. ref to its on-disk directory.
 *
 * @param {string} ref - TR-181 path like 'Device.Security.CABundle.2.'
 * @returns {string|null} Filesystem directory of the bundle, or null
 */
export function cabundle_path_resolve(ref) {
	if (type(ref) != 'string')
		return null;
	let m = match(ref, /\.([0-9]+)\.?$/);
	if (!m)
		return null;
	let inst = +m[1];
	let scan = cached_scan ?? certs_scan_live();
	if (inst < 1 || inst > length(scan.bundles))
		return null;
	return scan.bundles[inst - 1].path ?? null;
};

/**
 * Converts a parsed certificate to a TR-181 Certificate instance object.
 *
 * @param {object} cert - Certificate from openssl module with file metadata
 * @returns {object} TR-181 Certificate properties
 */
function cert_to_object(cert) {
	return {
		...schemas.Certificate.defaults,
		SerialNumber: cert.serial ?? '',
		Issuer: cert.issuer ?? '',
		Subject: cert.subject ?? '',
		SubjectAlt: cert.subject_alt ?? '',
		SignatureAlgorithm: cert.signature_algorithm ?? '',
		NotBefore: cert.not_before ?? '',
		NotAfter: cert.not_after ?? '',
		LastModif: cert.last_modif ?? ''
	};
}

/**
 * Builds the CACertificates CSV string for a range of Certificate instances.
 *
 * @param {number} start - First Certificate instance number
 * @param {number} end - Last Certificate instance number
 * @returns {string} Comma-separated list of Certificate path references
 */
function ca_certificates_build(start, end) {
	let refs = [];

	for (let i = start; i <= end; i++)
		push(refs, sprintf('Device.Security.Certificate.%d.', i));

	return join(',', refs);
}

/**
 * Get handler for Device.Security.
 *
 * @param {object} ctx - Handler context
 * @returns {object} Security container properties
 */
function security_get(ctx) {
	let scan = certs_scan();

	return {
		CertificateNumberOfEntries: sprintf('%d', length(scan.certs)),
		CABundleNumberOfEntries: sprintf('%d', length(scan.bundles))
	};
}

/**
 * Get handler for Device.Security.Certificate.{i}.
 *
 * @param {object} ctx - Handler context with optional instance number
 * @returns {object|null} Certificate properties or enumerated instances
 */
function certificate_get(ctx) {
	let scan = certs_scan();

	if (ctx.instance == null)
		return ubbf.enumerate_instances(scan.certs, cert_to_object);

	let cert = ubbf.get_by_instance(scan.certs, ctx.instance);
	if (!cert)
		return null;

	return cert_to_object(cert);
}

/**
 * Get handler for Device.Security.CABundle.{i}.
 *
 * @param {object} ctx - Handler context with optional instance number
 * @returns {object|null} CABundle properties
 */
function cabundle_get(ctx) {
	let scan = certs_scan();
	let num_bundles = length(scan.bundles);

	if (num_bundles == 0)
		return null;

	if (ctx.instance == null) {
		let result = {};

		for (let i = 0; i < num_bundles; i++) {
			let b = scan.bundles[i];

			result[sprintf('%d', i + 1)] = {
				...schemas.CABundle.defaults,
				Name: b.name,
				CACertificates: ca_certificates_build(b.start, b.end)
			};
		}

		return result;
	}

	if (ctx.instance < 1 || ctx.instance > num_bundles)
		return null;

	let b = scan.bundles[ctx.instance - 1];

	return {
		...schemas.CABundle.defaults,
		Name: b.name,
		CACertificates: ca_certificates_build(b.start, b.end)
	};
}

cached_scan = certs_scan_live();

export const model = {
	'Device.Security': {
		schema: schemas.Security,
		get: security_get
	},

	'Device.Security.Certificate': {
	},

	'Device.Security.Certificate.{i}': {
		schema: schemas.Certificate,
		get: certificate_get
	},

	'Device.Security.CABundle': {
	},

	'Device.Security.CABundle.{i}': {
		schema: schemas.CABundle,
		get: cabundle_get
	}
};
