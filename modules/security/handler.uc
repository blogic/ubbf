'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const utils = ubbf_module.utils;
const log_warn = ubbf_module.utils.logging.log_warn;
const model = ubbf_module.model;
const operations = ubbf_module.operations;
const config_apply = ubbf_module.config_apply;

const fs = require('fs');

const CONFIG_PATH = '/etc/ubbf/config.json';

const schema = ubbf_module.schema;
const schema_defaults = ubbf_module.schema_defaults;

// TR-181 "Unknown Time", for a validity date the certificate does not give.
const UNKNOWN_TIME = '0001-01-01T00:00:00Z';

let certificates = {};
include('./certificates.uc', { certificates, instance_map: utils['instance-map'] });

/**
 * Returns the certificate scan for the current request.
 *
 * The scan is not kept between requests: the parsed system CA store costs
 * the agent several hundred kB for its whole life.
 *
 * @returns {object} { certs, bundles } structure from certificates.scan()
 */
function certs_scan() {
	return utils.cache.call(certificates.scan);
}

/**
 * Converts a parsed certificate to a TR-181 Certificate instance object.
 *
 * @param {object} cert - Row from certificates.scan()
 * @returns {object} TR-181 Certificate properties
 */
function cert_to_object(cert) {
	return {
		...schema_defaults('Certificate'),
		Alias: certificates.certificate_alias(cert),
		Name: certificates.certificate_name(cert),
		SerialNumber: cert.serial ?? '',
		Issuer: cert.issuer ?? '',
		Subject: cert.subject ?? '',
		SubjectAlt: cert.subject_alt ?? '',
		SignatureAlgorithm: cert.signature_algorithm ?? '',
		NotBefore: cert.not_before ?? UNKNOWN_TIME,
		NotAfter: cert.not_after ?? UNKNOWN_TIME,
		LastModif: cert.last_modif ?? UNKNOWN_TIME
	};
}

/**
 * Converts a CA bundle to a TR-181 CABundle instance object.
 *
 * @param {object} bundle - Bundle from certificates.scan()
 * @returns {object} TR-181 CABundle properties
 */
function bundle_to_object(bundle) {
	let numbers = sort(map(bundle.members, (e) => e.instance), (a, b) => a - b);

	return {
		...schema_defaults('CABundle'),
		Name: bundle.name,
		CACertificates: join(',', map(numbers, (n) => sprintf('Device.Security.Certificate.%d.', n)))
	};
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
		...schema_defaults('Security'),
		CertificateNumberOfEntries: sprintf('%d', length(scan.certs)),
		CABundleNumberOfEntries: sprintf('%d', length(scan.bundles))
	};
}

/**
 * Get handler for Device.Security.Certificate.{i}. The instance numbers
 * are identifiers from a persistent map, not positions.
 *
 * @param {object} ctx - Handler context with optional instance number
 * @returns {object|null} Certificate properties or the rows by instance
 */
function certificate_get(ctx) {
	let scan = certs_scan();

	if (ctx.instance == null) {
		let rows = {};
		for (let cert in scan.certs)
			rows[sprintf('%d', cert.instance)] = cert_to_object(cert);
		return rows;
	}

	let cert = certificates.certificate_find(scan, ctx.instance);
	if (!cert)
		return null;

	return cert_to_object(cert);
}

/**
 * Get handler for Device.Security.CABundle.{i}.
 *
 * @param {object} ctx - Handler context with optional instance number
 * @returns {object|null} CABundle properties or enumerated instances
 */
function cabundle_get(ctx) {
	let scan = certs_scan();

	if (ctx.instance == null) {
		let rows = {};
		for (let bundle in scan.bundles)
			rows[sprintf('%d', bundle.instance)] = bundle_to_object(bundle);
		return rows;
	}

	let bundle = certificates.cabundle_find(scan, ctx.instance);
	if (!bundle)
		return null;

	return bundle_to_object(bundle);
}

/**
 * Finds the bundle of a CABundle command. A bundle without a certificate
 * has no directory or file that a service could use.
 *
 * @param {array} instances - [ CABundle instance ]
 * @param {string} command - Command name for the log
 * @returns {object|null} The bundle, or null
 */
function command_bundle(instances, command) {
	let bundle = certificates.cabundle_find(certs_scan(), instances?.[0]);

	if (!length(bundle?.members)) {
		log_warn('security: CABundle.%s.%s: the bundle has no certificate', instances?.[0], command);
		return null;
	}

	return bundle;
}

/**
 * Handles Device.Security.CABundle.{i}.CADir().
 *
 * @param {object} input - No input arguments
 * @param {string} command_key - Command key (unused)
 * @param {array} instances - [ CABundle instance ]
 * @param {object} root - Root configuration (unused)
 * @returns {object|number} { CADir } as an RFC 8089 file URI, or a
 *                          negative USP error code
 */
function cabundle_cadir(input, command_key, instances, root) {
	let bundle = command_bundle(instances, 'CADir()');
	if (!bundle)
		return -USP_ERR_COMMAND_FAILURE;

	return { CADir: `file://${bundle.path}` };
}

/**
 * Handles Device.Security.CABundle.{i}.CAFile().
 *
 * @param {object} input - No input arguments
 * @param {string} command_key - Command key (unused)
 * @param {array} instances - [ CABundle instance ]
 * @param {object} root - Root configuration (unused)
 * @returns {object|number} { CAFile } as an RFC 8089 file URI, or a
 *                          negative USP error code
 */
function cabundle_cafile(input, command_key, instances, root) {
	let bundle = command_bundle(instances, 'CAFile()');
	if (!bundle)
		return -USP_ERR_COMMAND_FAILURE;

	let path = certificates.cabundle_file_build(bundle);
	if (!path) {
		log_warn('security: CABundle.%s.CAFile(): cannot write the CA file', instances[0]);
		return -USP_ERR_COMMAND_FAILURE;
	}

	return { CAFile: `file://${path}` };
}

/**
 * Handles Device.Security.Certificate.{i}.GetCertificateURI() (TR-181
 * 2.20). PrivateKeyURI is a file URI: the device keeps its keys in files,
 * and has no RFC 7512 token. It is empty for a certificate without a key.
 *
 * @param {object} input - No input arguments
 * @param {string} command_key - Command key (unused)
 * @param {array} instances - [ Certificate instance ]
 * @param {object} root - Root configuration (unused)
 * @returns {object|number} { CertificateURI, PrivateKeyURI }, or a
 *                          negative USP error code
 */
function certificate_uri_get(input, command_key, instances, root) {
	let cert = certificates.certificate_find(certs_scan(), instances?.[0]);
	if (!cert) {
		log_warn('security: Certificate.%s.GetCertificateURI(): no such certificate', instances?.[0]);
		return -USP_ERR_COMMAND_FAILURE;
	}

	let key = certificates.certificate_key_path(cert.path);

	return {
		CertificateURI: `file://${cert.path}`,
		PrivateKeyURI: key ? `file://${key}` : ''
	};
}

/**
 * Ends a write command: the next read rescans the certificate store, and a
 * failure goes to the log, since the controller gets the code only.
 *
 * @param {string} command - Command path for the log
 * @param {number} err - Fault code, 0 on success
 * @returns {number|null} The negative fault code, or null on success
 */
function write_done(command, err) {
	utils.cache.invalidate(certificates.scan);

	if (!err)
		return null;

	log_warn('security: %s failed with %d', command, err);
	return -err;
}

/**
 * Collects a set operation for each stored parameter that refers to an
 * object: the reference leaves a list, and a single value becomes empty.
 *
 * @param {object} node - Configuration subtree
 * @param {string} path - Path of the subtree, with a trailing dot
 * @param {string} target - Object path without a trailing dot
 * @param {array} ops - Operations, appended to
 */
function refs_collect(node, path, target, ops) {
	for (let key, value in node) {
		if (type(value) == 'object') {
			refs_collect(value, `${path}${key}.`, target, ops);
			continue;
		}
		if (type(value) != 'string' || index(value, target) < 0)
			continue;

		let items = map(split(value, ','), (s) => trim(s));
		let kept = filter(items, (s) => rtrim(s, '.') != target);
		if (length(kept) != length(items))
			push(ops, { op: 'set', path: `${path}${key}`, value: join(',', kept) });
	}
}

/**
 * Removes the references to a deleted object from the stored configuration,
 * which holds only writable values, unlike the runtime tree. TR-181: "If the
 * referenced object is deleted, the parameter value MUST be set to an empty
 * string."
 *
 * @param {string} target - Object path without a trailing dot
 */
function refs_clear(target) {
	let config;
	try {
		config = json(fs.readfile(CONFIG_PATH) ?? '{}');
	} catch (e) {
		log_warn('security: %s is not valid JSON, references to %s stay', CONFIG_PATH, target);
		return;
	}

	let ops = [];
	refs_collect(config, '', target, ops);
	if (!length(ops))
		return;

	let report = (result) => {
		if (!result?.success)
			log_warn('security: failed to clear the references to %s', target);
	};
	let result = config_apply(ops, report);
	if (result)
		report(result);
}

/**
 * Handles Device.Security.AddCertificateBundle() (TR-181 2.21).
 *
 * @param {object} input - Alias, Name, BundleFormat, Bundle
 * @param {string} command_key - Command key (unused)
 * @param {object} root - Root configuration (unused)
 * @returns {object|number} { Certificate }, or a negative fault code
 */
function certificate_bundle_add(input, command_key, root) {
	let result = certificates.certificate_add(input);

	return write_done('AddCertificateBundle()', result.error) ??
		{ Certificate: sprintf('Device.Security.Certificate.%d.', result.instance) };
}

/**
 * Handles Device.Security.Certificate.{i}.Delete() (TR-181 2.21).
 *
 * @param {object} input - No input arguments
 * @param {string} command_key - Command key (unused)
 * @param {array} instances - [ Certificate instance ]
 * @param {object} root - Root configuration (unused)
 * @returns {object|number} Empty result, or a negative fault code
 */
function certificate_delete(input, command_key, instances, root) {
	let fault = write_done(`Certificate.${instances?.[0]}.Delete()`,
		certificates.certificate_delete(instances?.[0]));
	if (fault)
		return fault;

	refs_clear(`Device.Security.Certificate.${instances[0]}`);
	return {};
}

/**
 * Handles Device.Security.AddCABundle() (TR-181 2.21).
 *
 * @param {object} input - Name, Bundle
 * @param {string} command_key - Command key (unused)
 * @param {object} root - Root configuration (unused)
 * @returns {object|number} { CABundle, NumberOfCertificates }, or a
 *                          negative fault code
 */
function cabundle_add(input, command_key, root) {
	let result = certificates.cabundle_add(input);

	return write_done('AddCABundle()', result.error) ?? {
		CABundle: sprintf('Device.Security.CABundle.%d.', result.instance),
		NumberOfCertificates: sprintf('%d', result.count)
	};
}

/**
 * Handles Device.Security.CABundle.{i}.Update() (TR-181 2.21).
 *
 * @param {object} input - Bundle
 * @param {string} command_key - Command key (unused)
 * @param {array} instances - [ CABundle instance ]
 * @param {object} root - Root configuration (unused)
 * @returns {object|number} { NumberOfCertificates }, or a negative fault code
 */
function cabundle_update(input, command_key, instances, root) {
	let result = certificates.cabundle_update(instances?.[0], input);

	return write_done(`CABundle.${instances?.[0]}.Update()`, result.error) ??
		{ NumberOfCertificates: sprintf('%d', result.count) };
}

/**
 * Handles Device.Security.CABundle.{i}.Delete() (TR-181 2.21).
 *
 * @param {object} input - No input arguments
 * @param {string} command_key - Command key (unused)
 * @param {array} instances - [ CABundle instance ]
 * @param {object} root - Root configuration (unused)
 * @returns {object|number} Empty result, or a negative fault code
 */
function cabundle_delete(input, command_key, instances, root) {
	let fault = write_done(`CABundle.${instances?.[0]}.Delete()`,
		certificates.cabundle_delete(instances?.[0]));
	if (fault)
		return fault;

	refs_clear(`Device.Security.CABundle.${instances[0]}`);
	return {};
}

model['Device.Security'] = {
	schema: schema('Security'),
	get: security_get
};

model['Device.Security.Certificate'] = {
};

model['Device.Security.Certificate.{i}'] = {
	schema: schema('Certificate'),
	get: certificate_get
};

model['Device.Security.CABundle'] = {
};

model['Device.Security.CABundle.{i}'] = {
	schema: schema('CABundle'),
	get: cabundle_get
};

operations['Device.Security.Certificate.{i}.GetCertificateURI()'] = {
	type: 'sync',
	handler: certificate_uri_get
};

operations['Device.Security.CABundle.{i}.CADir()'] = {
	type: 'sync',
	handler: cabundle_cadir
};

operations['Device.Security.CABundle.{i}.CAFile()'] = {
	type: 'sync',
	handler: cabundle_cafile
};

operations['Device.Security.AddCertificateBundle()'] = {
	type: 'sync',
	handler: certificate_bundle_add
};

operations['Device.Security.AddCABundle()'] = {
	type: 'sync',
	handler: cabundle_add
};

operations['Device.Security.Certificate.{i}.Delete()'] = {
	type: 'sync',
	handler: certificate_delete
};

operations['Device.Security.CABundle.{i}.Update()'] = {
	type: 'sync',
	handler: cabundle_update
};

operations['Device.Security.CABundle.{i}.Delete()'] = {
	type: 'sync',
	handler: cabundle_delete
};
