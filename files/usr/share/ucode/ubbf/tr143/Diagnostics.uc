'use strict';

import * as fs from 'fs';
import * as ubus from 'ubus';
import * as schemas from 'ubbf.schemas.Diagnostics';
import { handler as ping_handler } from 'ubbf.tr143.Ping';
import { handler as traceroute_handler } from 'ubbf.tr143.TraceRoute';
import { handler as download_handler } from 'ubbf.tr143.Download';
import { handler as upload_handler } from 'ubbf.tr143.Upload';
import { handler as udpecho_handler } from 'ubbf.tr143.UDPEcho';
import { handler as serverselection_handler } from 'ubbf.tr143.ServerSelection';
import * as ubbf from 'ubbf';
import { op_trigger_set, op_overlay_get } from 'ubbf.utils.cwmp-op-trigger';

const UDPECHO_STATS_PATH = '/tmp/ubbf/udpecho-stats.json';

/**
 * Builds a get handler returning stored config merged with the
 * diagnostic's result overlay written by the ubbf-device runner.
 *
 * @param {string} path - TR-181 object path
 * @returns {function} Get handler for the model entry
 */
function diag_get_for(path) {
	return op_overlay_get(path);
}

/**
 * Builds a set hook forwarding a DiagnosticsState='Requested' write to
 * the ubbf-device operation runner.
 *
 * @param {string} path - TR-181 object path
 * @returns {function} Set handler for the model entry
 */
function diag_set_for(path) {
	return op_trigger_set(path, 'DiagnosticsState');
}

/**
 * Get handler for Device.IP.Diagnostics.
 *
 * @param {object} ctx - Context
 * @returns {object} Supported diagnostics capabilities
 */
function ip_diagnostics_get(ctx) {
	return {
		IPv4PingSupported: 'true',
		IPv6PingSupported: 'true',
		IPv4TraceRouteSupported: 'true',
		IPv6TraceRouteSupported: 'true',
		IPv4DownloadDiagnosticsSupported: 'true',
		IPv6DownloadDiagnosticsSupported: 'true',
		IPv4UploadDiagnosticsSupported: 'true',
		IPv6UploadDiagnosticsSupported: 'true',
		IPv4UDPEchoDiagnosticsSupported: 'true',
		IPv6UDPEchoDiagnosticsSupported: 'true',
		IPv4ServerSelectionDiagnosticsSupported: 'true',
		IPv6ServerSelectionDiagnosticsSupported: 'true',
		IPLayerCapacitySupported: 'true',
		IPLayerMaxConnections: '1',
		IPLayerMaxIncrementalResult: '3600',
		IPLayerCapSupportedSoftwareVersion: 'UDPST-8.2.0',
		// PROTOCOL_VER of the shipped udpst (udpst_protocol.h)
		IPLayerCapSupportedControlProtocolVersion: '11',
		IPLayerCapSupportedMetrics: 'IPLR,Sampled_RTT,IPDV,IPRR,RIPR'
	};
}

/**
 * Get handler for Device.IP.Diagnostics.UDPEchoConfig.
 *
 * @param {object} ctx - Context with config
 * @returns {object} UDP echo configuration with statistics
 */
function udpecho_config_get(ctx) {
	let stats_data = fs.readfile(UDPECHO_STATS_PATH);
	let stats = {};
	try { stats = stats_data ? json(stats_data) : {}; } catch (e) {}

	return {
		...ubbf.ctx_config(ctx),
		EchoPlusSupported: 'true',
		PacketsReceived: stats.PacketsReceived ?? '0',
		PacketsResponded: stats.PacketsResponded ?? '0',
		BytesReceived: stats.BytesReceived ?? '0',
		BytesResponded: stats.BytesResponded ?? '0',
		TimeFirstPacketReceived: stats.TimeFirstPacketReceived ?? '0001-01-01T00:00:00Z',
		TimeLastPacketReceived: stats.TimeLastPacketReceived ?? '0001-01-01T00:00:00Z'
	};
}

/**
 * Firewall hook for Device.IP.Diagnostics.UDPEchoConfig.
 *
 * Returns an array (not a single object) because the firewall renderer
 * expects every hook to emit zero or more service descriptors; here we
 * only ever emit one, but the contract is array-typed.
 *
 * @param {object} inst - UDPEchoConfig data
 * @param {object} root - Root config data
 * @param {string} path - Instance path
 * @returns {array|null} Array with one Service descriptor for the UDP echo port, or null when disabled
 */
function udpecho_config_firewall(inst, root, path) {
	if (inst.Enable != 'true')
		return null;
	if (!inst.Interface || inst.Interface == '')
		return null;

	let iface = ubbf.get(root, inst.Interface);
	if (!iface?.Name)
		return null;

	let port = inst.UDPPort ?? '7';

	return [{
		type: 'Service',
		alias: sprintf('cpe-udpecho-%s', iface.Name),
		Interface: inst.Interface,
		Protocol: 'udp',
		DestPort: sprintf('%s', port),
		Action: 'Accept'
	}];
}

export const model = {
	'Device.IP.Diagnostics': {
		schema: schemas.Diagnostics,
		get: ip_diagnostics_get
	},

	'Device.IP.Diagnostics.IPPing': {
		schema: schemas.IPPing,
		get: diag_get_for('Device.IP.Diagnostics.IPPing'),
		set: diag_set_for('Device.IP.Diagnostics.IPPing')
	},

	'Device.IP.Diagnostics.TraceRoute': {
		schema: schemas.TraceRoute,
		get: diag_get_for('Device.IP.Diagnostics.TraceRoute'),
		set: diag_set_for('Device.IP.Diagnostics.TraceRoute')
	},

	'Device.IP.Diagnostics.UDPEchoConfig': {
		schema: schemas.UDPEchoConfig,
		get: udpecho_config_get,
		firewall: udpecho_config_firewall
	},

	'Device.IP.Diagnostics.UDPEchoDiagnostics': {
		schema: schemas.UDPEchoDiagnostics,
		get: diag_get_for('Device.IP.Diagnostics.UDPEchoDiagnostics'),
		set: diag_set_for('Device.IP.Diagnostics.UDPEchoDiagnostics')
	},

	'Device.IP.Diagnostics.ServerSelectionDiagnostics': {
		schema: schemas.ServerSelectionDiagnostics,
		get: diag_get_for('Device.IP.Diagnostics.ServerSelectionDiagnostics'),
		set: diag_set_for('Device.IP.Diagnostics.ServerSelectionDiagnostics')
	}
};

// Maps the handler-internal output key 'Status' onto the TR-181
// stored-result key 'DiagnosticsState' (the datamodel field used to
// expose the final state of the most recent diagnostics run).
const diag_key_map = { Status: 'DiagnosticsState' };

export const operations = {
	'Device.IP.Diagnostics.IPPing()': {
		type: 'async',
		handler: ping_handler,
		store_results: 'Device.IP.Diagnostics.IPPing',
		output_key_map: diag_key_map
	},

	'Device.IP.Diagnostics.TraceRoute()': {
		type: 'async',
		handler: traceroute_handler,
		store_results: 'Device.IP.Diagnostics.TraceRoute',
		output_key_map: diag_key_map
	},

	'Device.IP.Diagnostics.DownloadDiagnostics()': {
		type: 'async',
		handler: download_handler
	},

	'Device.IP.Diagnostics.UploadDiagnostics()': {
		type: 'async',
		handler: upload_handler
	},

	'Device.IP.Diagnostics.UDPEchoDiagnostics()': {
		type: 'async',
		handler: udpecho_handler,
		store_results: 'Device.IP.Diagnostics.UDPEchoDiagnostics',
		output_key_map: diag_key_map
	},

	'Device.IP.Diagnostics.ServerSelectionDiagnostics()': {
		type: 'async',
		handler: serverselection_handler,
		store_results: 'Device.IP.Diagnostics.ServerSelectionDiagnostics',
		output_key_map: diag_key_map
	}
};
