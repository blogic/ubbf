'use strict';

import { popen } from 'fs';
import * as ubus from 'ubus';
import * as ubbf from 'ubbf';

const easymesh_schema = {
	path: "Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.",
	schema: {
		"Bridge": dm_type.STRING | dm_type.WRITABLE,
	},
	defaults: {
		"Bridge": "",
	}
};

const easymesh_agent_schema = {
	path: "Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Agent.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"ReceivedPolicy": dm_type.STRING,
		"Reset()": {
			type: 'async',
			input: ['privkey', 'pubkey_x', 'pubkey_y', 'hash', 'curve', 'disable_dpp'],
			output: []
		}
	},
	defaults: {
		"Enable": "false",
		"ReceivedPolicy": "",
	}
};

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

const easymesh_controller_schema = {
	path: "Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Controller.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"PolicyNumberOfEntries": dm_type.UINT,
	},
	defaults: {
		"Enable": "false",
		"PolicyNumberOfEntries": "0",
	}
};

const controller_policy_schema = {
	path: "Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Controller.Policy.{i}.",
	schema: {
		"ALMAC": dm_type.STRING | dm_type.WRITABLE,
		"Data": dm_type.STRING | dm_type.WRITABLE,
	},
	defaults: {
		"ALMAC": "",
		"Data": "",
	}
};

const steering_schema = {
	path: "Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Steering.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"Backend": dm_type.STRING | dm_type.WRITABLE,
		"LogLevel": dm_type.UINT | dm_type.WRITABLE,
		"PeriodicInterval": dm_type.UINT | dm_type.WRITABLE,
		"MetricStaleInterval": dm_type.UINT | dm_type.WRITABLE,
		"APMetricsReportingInterval": dm_type.UINT | dm_type.WRITABLE,
	},
	defaults: {
		"Enable": "false",
		"Backend": "umap",
		"LogLevel": "3",
		"PeriodicInterval": "10000",
		"MetricStaleInterval": "30000",
		"APMetricsReportingInterval": "30",
	}
};

const steering_signal_quality_schema = {
	path: "Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Steering.SignalQuality.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"LowRCPICount": dm_type.UINT | dm_type.WRITABLE,
		"HighRCPICount": dm_type.UINT | dm_type.WRITABLE,
		"SignalThreshold2G": dm_type.INT | dm_type.WRITABLE,
		"SignalThreshold5G": dm_type.INT | dm_type.WRITABLE,
		"SignalThreshold6G": dm_type.INT | dm_type.WRITABLE,
		"ReportSignalThreshold2G": dm_type.INT | dm_type.WRITABLE,
		"ReportSignalThreshold5G": dm_type.INT | dm_type.WRITABLE,
		"ReportSignalThreshold6G": dm_type.INT | dm_type.WRITABLE,
		"Hysteresis": dm_type.UINT | dm_type.WRITABLE,
		"DiffSNRMargin": dm_type.UINT | dm_type.WRITABLE,
		"UnassocCollectTime": dm_type.UINT | dm_type.WRITABLE,
		"BeaconCollectTime": dm_type.UINT | dm_type.WRITABLE,
		"Cooldown": dm_type.UINT | dm_type.WRITABLE,
	},
	defaults: {
		"Enable": "true",
		"LowRCPICount": "3",
		"HighRCPICount": "4",
		"SignalThreshold2G": "-75",
		"SignalThreshold5G": "-67",
		"SignalThreshold6G": "-67",
		"ReportSignalThreshold2G": "-70",
		"ReportSignalThreshold5G": "-62",
		"ReportSignalThreshold6G": "-62",
		"Hysteresis": "2",
		"DiffSNRMargin": "8",
		"UnassocCollectTime": "5000",
		"BeaconCollectTime": "10000",
		"Cooldown": "180000",
	}
};

const steering_ap_load_schema = {
	path: "Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Steering.APLoad.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"OverloadThreshold": dm_type.UINT | dm_type.WRITABLE,
		"TargetThreshold": dm_type.UINT | dm_type.WRITABLE,
		"MinSteerSignal": dm_type.INT | dm_type.WRITABLE,
		"ConfinedDuration": dm_type.UINT | dm_type.WRITABLE,
		"Cooldown": dm_type.UINT | dm_type.WRITABLE,
		"MinConnectedTime": dm_type.UINT | dm_type.WRITABLE,
	},
	defaults: {
		"Enable": "true",
		"OverloadThreshold": "80",
		"TargetThreshold": "60",
		"MinSteerSignal": "-75",
		"ConfinedDuration": "300000",
		"Cooldown": "300000",
		"MinConnectedTime": "30000",
	}
};

const steering_band_pref_schema = {
	path: "Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Steering.BandPreference.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"RSSICutoff": dm_type.INT | dm_type.WRITABLE,
		"PathlossDelta": dm_type.UINT | dm_type.WRITABLE,
		"PathlossDelta5To6": dm_type.UINT | dm_type.WRITABLE,
		"UpgradeMargin": dm_type.UINT | dm_type.WRITABLE,
		"DowngradeCount": dm_type.UINT | dm_type.WRITABLE,
		"SettlingDelay": dm_type.UINT | dm_type.WRITABLE,
		"CooldownSuccess": dm_type.UINT | dm_type.WRITABLE,
		"CooldownFailure": dm_type.UINT | dm_type.WRITABLE,
		"MaxFailuresPerBand": dm_type.UINT | dm_type.WRITABLE,
		"FailureDecayTime": dm_type.UINT | dm_type.WRITABLE,
	},
	defaults: {
		"Enable": "true",
		"RSSICutoff": "-75",
		"PathlossDelta": "10",
		"PathlossDelta5To6": "3",
		"UpgradeMargin": "5",
		"DowngradeCount": "3",
		"SettlingDelay": "6000",
		"CooldownSuccess": "180000",
		"CooldownFailure": "30000",
		"MaxFailuresPerBand": "3",
		"FailureDecayTime": "600",
	}
};

const steering_backhaul_schema = {
	path: "Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Steering.BackhaulLink.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"SignalThreshold2G": dm_type.INT | dm_type.WRITABLE,
		"SignalThreshold5G": dm_type.INT | dm_type.WRITABLE,
		"SignalThreshold6G": dm_type.INT | dm_type.WRITABLE,
		"ReportSignalThreshold2G": dm_type.INT | dm_type.WRITABLE,
		"ReportSignalThreshold5G": dm_type.INT | dm_type.WRITABLE,
		"ReportSignalThreshold6G": dm_type.INT | dm_type.WRITABLE,
		"SignalDiffThreshold": dm_type.UINT | dm_type.WRITABLE,
		"RCPILowTrigger": dm_type.UINT | dm_type.WRITABLE,
		"RCPIRecoveryTrigger": dm_type.UINT | dm_type.WRITABLE,
		"ThroughputDropPct": dm_type.UINT | dm_type.WRITABLE,
		"ThroughputTrigger": dm_type.UINT | dm_type.WRITABLE,
		"TopologyImpactThreshold": dm_type.UINT | dm_type.WRITABLE,
		"MinAssocTime": dm_type.UINT | dm_type.WRITABLE,
		"UnassocCollectTime": dm_type.UINT | dm_type.WRITABLE,
		"BeaconCollectTime": dm_type.UINT | dm_type.WRITABLE,
		"Cooldown": dm_type.UINT | dm_type.WRITABLE,
	},
	defaults: {
		"Enable": "true",
		"SignalThreshold2G": "-72",
		"SignalThreshold5G": "-64",
		"SignalThreshold6G": "-64",
		"ReportSignalThreshold2G": "-67",
		"ReportSignalThreshold5G": "-59",
		"ReportSignalThreshold6G": "-59",
		"SignalDiffThreshold": "8",
		"RCPILowTrigger": "5",
		"RCPIRecoveryTrigger": "6",
		"ThroughputDropPct": "40",
		"ThroughputTrigger": "5",
		"TopologyImpactThreshold": "10",
		"MinAssocTime": "30",
		"UnassocCollectTime": "10000",
		"BeaconCollectTime": "10000",
		"Cooldown": "300000",
	}
};

const steering_dfs_schema = {
	path: "Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Steering.DFSEvacuation.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"DisassocTimer": dm_type.UINT | dm_type.WRITABLE,
		"EvacuateTimeout": dm_type.UINT | dm_type.WRITABLE,
		"CACTimeout": dm_type.UINT | dm_type.WRITABLE,
		"ReturnTimeout": dm_type.UINT | dm_type.WRITABLE,
	},
	defaults: {
		"Enable": "true",
		"DisassocTimer": "15000",
		"EvacuateTimeout": "60000",
		"CACTimeout": "660000",
		"ReturnTimeout": "60000",
	}
};

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

export const model = {
	'Device.WiFi.DataElements.Network.X_UBBF_EasyMesh': {
		schema: easymesh_schema
	},

	'Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Agent': {
		schema: easymesh_agent_schema,
		get: easymesh_agent_get
	},

	'Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Controller': {
		schema: easymesh_controller_schema,
		set: easymesh_controller_set
	},

	'Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Controller.Policy': {
	},

	'Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Controller.Policy.{i}': {
		schema: controller_policy_schema,
		set: controller_policy_set
	},

	'Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Steering': {
		schema: steering_schema,
		set: steering_set
	},

	'Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Steering.SignalQuality': {
		schema: steering_signal_quality_schema
	},

	'Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Steering.APLoad': {
		schema: steering_ap_load_schema
	},

	'Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Steering.BandPreference': {
		schema: steering_band_pref_schema
	},

	'Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Steering.BackhaulLink': {
		schema: steering_backhaul_schema
	},

	'Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Steering.DFSEvacuation': {
		schema: steering_dfs_schema
	}
};
