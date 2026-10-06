'use strict';

import { glob } from 'fs';
import * as schemas from 'ubbf.schemas.DynamicDNS';
import * as ubbf from 'ubbf';

const DDNS_SERVICES_DIR = '/usr/share/ddns/default';

/**
 * Reads available DDNS service names from ddns-scripts JSON definitions.
 *
 * @returns {string} Comma-separated list of supported service names
 */
function supported_services_get() {
	let files = glob(DDNS_SERVICES_DIR + '/*.json') ?? [];
	let names = [];

	for (let file in files) {
		let m = match(file, /\/([^\/]+)\.json$/);
		if (m)
			push(names, m[1]);
	}

	sort(names);
	return join(',', names);
}

/**
 * Get handler for Device.DynamicDNS.
 *
 * @param {object} ctx - Context with config
 * @returns {object} DynamicDNS properties with instance counts
 */
function dynamicdns_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		ClientNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Client)),
		ServerNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Server)),
		SupportedServices: supported_services_get()
	};
}

/**
 * Get handler for Device.DynamicDNS.Client.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object} Client properties with hostname count
 */
function client_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		HostnameNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Hostname)),
		Password: ''
	};
}

export const model = {
	'Device.DynamicDNS': {
		schema: schemas.DynamicDNS,
		get: dynamicdns_get
	},

	'Device.DynamicDNS.Client': {
	},

	'Device.DynamicDNS.Client.{i}': {
		schema: schemas.Client,
		get: client_get
	},

	'Device.DynamicDNS.Client.{i}.Hostname': {
	},

	'Device.DynamicDNS.Client.{i}.Hostname.{i}': {
		schema: schemas.Client_Hostname
	},

	'Device.DynamicDNS.Server': {
	},

	'Device.DynamicDNS.Server.{i}': {
		schema: schemas.Server
	}
};
