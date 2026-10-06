'use strict';

// Included by handler.uc with { em } as the scope. Like the handler, it binds
// at the top what its functions use later, and it adds its model entries to
// em, for dataelements.uc to place below Device.WiFi.DataElements.Network.

const ubbf = ubbf_module.ubbf;
const schema = ubbf_module.schema;

const fs = require('fs');
const ubus = require('ubus');
const popen = fs.popen;

/**
 * @param {object} ctx - Handler context
 * @returns {object} Agent properties with received policy from umap-agent
 */
function easymesh_agent_get(ctx) {
	let policy = ubus.call('umap-agent', 'get_agent_policy', {});
	return {
		...ubbf.ctx_config(ctx),
		ReceivedPolicy: policy ? sprintf('%J', policy) : "",
	};
}

/**
 * Generates DPP controller keys if not already present.
 *
 * Invokes /usr/libexec/umap-dpp-keygen which prints a JSON object on stdout
 * containing at minimum a 'connector' field (used as the presence sentinel)
 * plus the DPP key material; the parsed object is stored verbatim under
 * root.EasyMesh.Controller with an added ID field.
 *
 * @param {object} root - Root configuration object
 */
function controller_keys_generate(root) {
	if (root.EasyMesh?.Controller?.connector)
		return;

	let existing_id = root.EasyMesh?.Controller?.ID;
	let id = existing_id ?? ubbf.readfile_trim('/proc/sys/kernel/random/uuid', '');

	let p = popen('/usr/libexec/umap-dpp-keygen', 'r');
	if (!p)
		return;

	let output = p.read('all');
	p.close();

	let keys;
	try {
		keys = json(output);
	} catch (e) {
		return;
	}

	if (!keys)
		return;

	root.EasyMesh ??= {};
	root.EasyMesh.Controller = keys;
	root.EasyMesh.Controller.ID = id;
}

/**
 * Set handler for Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Controller.
 *
 * @param {object} ctx - Context with param, value and root config
 */
function easymesh_controller_set(ctx) {
	if (ctx.param != 'Enable')
		return;

	if (ubbf.to_bool(ctx.value))
		controller_keys_generate(ctx.root);
}

/**
 * Set handler for Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Controller.Policy.{i}.
 *
 * @param {object} ctx - Context with param, value, config and root
 */
function controller_policy_set(ctx) {
	if (ctx.param == 'ALMAC' && ctx.value != '') {
		let policy = ctx.root.Device?.WiFi?.DataElements?.Network?.X_UBBF_EasyMesh?.Controller?.Policy;
		for (let inst in policy) {
			if (policy[inst] == ctx.config)
				continue;
			if (policy[inst]?.ALMAC == ctx.value) {
				ctx.config.ALMAC = '';
				return;
			}
		}
	}

	if (ctx.param == 'Data' && ctx.value != '') {
		let parsed = json(ctx.value);
		if (type(parsed) != 'object') {
			ctx.config.Data = '';
			return;
		}
	}
}

/**
 * Set handler for Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Steering.
 * When Steering.Enable is set to true, ensures all sub-module config objects
 * exist and default their Enable to "true" if not already set.
 *
 * @param {object} ctx - Context with param, value and config
 */
function steering_set(ctx) {
	if (ctx.param != 'Enable' || !ubbf.to_bool(ctx.value))
		return;

	let modules = ['SignalQuality', 'APLoad', 'BandPreference', 'BackhaulLink', 'DFSEvacuation'];
	for (let name in modules) {
		ctx.config[name] ??= {};
		ctx.config[name].Enable ??= "true";
	}
}

const easymesh_model = {
	'Device.WiFi.DataElements.Network.X_UBBF_EasyMesh': {
		schema: schema('EasyMesh')
	},

	'Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Agent': {
		schema: schema('Agent'),
		get: easymesh_agent_get
	},

	'Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Controller': {
		schema: schema('Controller'),
		set: easymesh_controller_set
	},

	'Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Controller.Policy': {
	},

	'Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Controller.Policy.{i}': {
		schema: schema('Controller_Policy'),
		set: controller_policy_set
	},

	'Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Steering': {
		schema: schema('Steering'),
		set: steering_set
	},

	'Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Steering.SignalQuality': {
		schema: schema('Steering_SignalQuality')
	},

	'Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Steering.APLoad': {
		schema: schema('Steering_APLoad')
	},

	'Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Steering.BandPreference': {
		schema: schema('Steering_BandPreference')
	},

	'Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Steering.BackhaulLink': {
		schema: schema('Steering_BackhaulLink')
	},

	'Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Steering.DFSEvacuation': {
		schema: schema('Steering_DFSEvacuation')
	}
};

em.easymesh_model = easymesh_model;
