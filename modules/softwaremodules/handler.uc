'use strict';

const ubbf = ubbf_module.ubbf;
const utils = ubbf_module.utils;
const model = ubbf_module.model;
const operations = ubbf_module.operations;

const fs = require('fs');
const ubus = require('ubus');
const digest = require('digest');

let schemas = {};
include('schema.uc', { schemas });

const SM = 'Device.SoftwareModules';
const EE_REF = SM + '.ExecEnv.1';
const CLASS_REF = SM + '.ExecEnvClass.1';
const META_DIR = '/tmp/run/uvol/.meta';
const DISABLED_MARKER = META_DIR + '/uxc/disabled';
const SECRETS_DIR = META_DIR + '/secrets';
const UVOL_DIR = '/tmp/run/uvol';
const CGROUP_ROOT = '/sys/fs/cgroup';
const WORK_DIR = '/tmp/ubbf';
const REQUEST_FILE = WORK_DIR + '/softwaremodules-request.json';
const RESOURCES_FILE = WORK_DIR + '/softwaremodules-resources.json';
const UNKNOWN_TIME = '0001-01-01T00:00:00Z';
const INFINITE_TIME = '9999-12-31T23:59:59Z';
const UUID_NAMESPACE_DNS = '6ba7b8109dad11d180b400c04fd430c8';
const TAG_PREFIX = 'openwrt.req:';
const CPU_PERIOD_DEFAULT = 100000;

const FAULT_REQUEST_DENIED = 7002;
const FAULT_INVALID_ARGUMENTS = 7004;
const FAULT_UNKNOWN_EE = 7223;
const FAULT_INVALID_DU_STATE = 7229;

const STATUS_MAP = {
	running: 'Active',
	paused: 'Active',
	creating: 'Starting',
	created: 'Starting'
};

const RESPAWN_KEYS = {
	Enable: 'enable',
	RetryMinimumWaitInterval: 'min',
	RetryMaximumWaitInterval: 'max',
	RetryIntervalMultiplier: 'multiplier',
	MaximumRetryCount: 'max-retries',
	ResetPeriod: 'reset-period'
};

const SIZE_UNITS = { k: 1024, m: 1048576, g: 1073741824 };

let pending = {};
let ee_restart = { count: 0, reason: '', time: 0 };

function command_build(parts) {
	return join(' ', map(parts, (p) => ubbf.shell_escape(sprintf('%s', p))));
}

function command_run(parts, merge_stderr) {
	let cmd = command_build(parts) + (merge_stderr ? ' 2>&1' : ' 2>/dev/null');
	let pipe = fs.popen(cmd, 'r');
	if (!pipe)
		return { data: '', exitcode: -1 };

	let data = pipe.read('all') ?? '';
	let exitcode = pipe.close();

	return { data, exitcode };
}

function command_json(parts) {
	let result = command_run(parts, false);
	if (result.exitcode != 0)
		return null;

	try {
		return json(result.data);
	} catch (e) {
		utils.logging.log_err('softwaremodules: %s printed no JSON', parts[0]);
		return null;
	}
}

function steps_run(steps, done, results) {
	results ??= [];
	if (!length(steps)) {
		done(results, null);
		return;
	}

	let step = steps[0];
	let rest = slice(steps, 1);

	utils.process.popen_async([ ...step, { raw: '2>&1' } ], (result) => {
		result.command = step;
		push(results, result);
		if (result.error || result.exitcode != 0) {
			done(results, result);
			return;
		}
		steps_run(rest, done, results);
	});
}

function result_message(result) {
	if (result?.error)
		return result.error;

	let lines = filter(split(result?.data ?? '', '\n'), (l) => trim(l) != '');
	return length(lines) ? trim(lines[-1]) : sprintf('exit code %d', result?.exitcode ?? -1);
}

function size_bytes(value) {
	if (type(value) == 'int')
		return value;

	let m = match(lc(sprintf('%s', value ?? '')), /^([0-9]+)([kmg]?)$/);
	if (!m)
		return null;

	return int(m[1]) * (m[2] ? SIZE_UNITS[m[2]] : 1);
}

function kib(bytes) {
	return bytes == null ? -1 : int(bytes / 1024);
}

function rfc3339_parse(text) {
	let m = match(text ?? '', /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/);
	if (!m)
		return null;

	return timegm({
		year: int(m[1]), mon: int(m[2]), mday: int(m[3]),
		hour: int(m[4]), min: int(m[5]), sec: int(m[6])
	});
}

function tags_parse(list) {
	let tags = {};
	for (let tag in (list ?? [])) {
		if (substr(tag, 0, length(TAG_PREFIX)) != TAG_PREFIX)
			continue;
		let kv = substr(tag, length(TAG_PREFIX));
		let eq = index(kv, '=');
		if (eq <= 0)
			continue;
		tags[substr(kv, 0, eq)] = substr(kv, eq + 1);
	}
	return tags;
}

function name_percent_encode(name) {
	let out = '';
	for (let i = 0; i < length(name); i++) {
		let ch = substr(name, i, 1);
		if (match(ch, /^[0-9A-Za-z_-]$/))
			out += ch;
		else
			out += sprintf('%%%02x', ord(name, i));
	}
	return out;
}

function du_uuid(name, vendor) {
	let fqdn = name_percent_encode(name) + '.' + vendor + '.';
	let sha = digest.sha1(hexdec(UUID_NAMESPACE_DNS) + fqdn);
	let byte6 = (hex(substr(sha, 12, 2)) & 0x0f) | 0x50;
	let byte8 = (hex(substr(sha, 16, 2)) & 0x3f) | 0x80;

	return sprintf('%s-%s-%02x%s-%02x%s-%s',
		substr(sha, 0, 8), substr(sha, 8, 4),
		byte6, substr(sha, 14, 2),
		byte8, substr(sha, 18, 2),
		substr(sha, 20, 12));
}

function containers_fetch() {
	let list = command_json([ 'uxc', 'list', '--format', 'json' ]);
	return type(list) == 'array' ? list : [];
}

function packages_fetch() {
	let list = command_json([ 'apk', 'query', '--installed', '--format', 'json',
		'--fields', 'name,version,description,url,tags', 'container-*', 'stack-*' ]);
	let packages = {};

	for (let pkg in (type(list) == 'array' ? list : [])) {
		if (pkg?.name)
			packages[pkg.name] = pkg;
	}
	return packages;
}

function uvol_call(method, args) {
	return ubus.call('uvol', method, args ?? {});
}

function uvol_bytes(method) {
	return utils.cache.call(uvol_call, method, {})?.bytes;
}

function uxc_version_fetch() {
	let m = match(command_run([ 'uxc', '--version' ], false).data, /^uxc (\S+)/);
	return m ? m[1] : '';
}

function package_of(info) {
	if (info.package)
		return info.package;

	let m = match(info.origin ?? '', /^stack:(.+)$/);
	return m ? 'stack-' + m[1] : null;
}

function du_name(pkg, info) {
	let m = match(info?.origin ?? '', /^stack:(.+)$/);
	if (m)
		return m[1];
	if (info?.name)
		return info.name;
	return replace(pkg, /^(container|stack)-/, '');
}

function view_build() {
	let containers = sort(utils.cache.call(containers_fetch),
		(a, b) => (a.id < b.id) ? -1 : ((a.id > b.id) ? 1 : 0));
	let packages = utils.cache.call(packages_fetch);
	let dus_by_pkg = {};
	let eus = [];

	for (let entry in containers) {
		let info = entry['org.openwrt.uxc'] ?? {};
		let name = entry.id ?? info.name;
		if (!name)
			continue;

		let eu = { name, entry, info, pkg: package_of(info), index: length(eus) + 1 };
		push(eus, eu);
		if (!eu.pkg)
			continue;

		dus_by_pkg[eu.pkg] ??= { pkg: eu.pkg, name: du_name(eu.pkg, info), eus: [] };
		push(dus_by_pkg[eu.pkg].eus, eu);
	}

	for (let pkg in packages)
		dus_by_pkg[pkg] ??= { pkg, name: du_name(pkg, null), eus: [] };

	let dus = [];
	for (let pkg in sort(keys(dus_by_pkg))) {
		let du = dus_by_pkg[pkg];
		du.index = length(dus) + 1;
		du.pkg_info = packages[pkg];
		du.tags = tags_parse(du.pkg_info?.tags);
		du.vendor = du.eus[0]?.info?.publisher ?? du.tags.publisher ?? '';
		du.version = du.pkg_info?.version ?? du.eus[0]?.info?.['package-version'] ?? '';
		du.uuid = du.vendor ? du_uuid(du.name, du.vendor) : '';
		for (let eu in du.eus)
			eu.du = du;
		push(dus, du);
	}

	return { eus, dus };
}

function view_get() {
	return utils.cache.call(view_build);
}

function eu_by_instance(instance) {
	return ubbf.get_by_instance(view_get().eus, instance);
}

function du_by_instance(instance) {
	return ubbf.get_by_instance(view_get().dus, instance);
}

function eu_by_package(pkg) {
	for (let eu in view_get().eus) {
		if (eu.pkg == pkg)
			return eu;
	}
	return null;
}

function eu_ref(eu) {
	return sprintf('%s.ExecutionUnit.%d', SM, eu.index);
}

function eu_live(eu) {
	return STATUS_MAP[eu.entry.status] != null;
}

function containers_disabled(view) {
	for (let eu in view.eus) {
		if (eu.info['containers-disabled'])
			return true;
	}
	return !!fs.stat(DISABLED_MARKER);
}

function eu_fault(eu) {
	let exit = eu.info['last-exit'];
	if (eu_live(eu) || !exit || exit.requested)
		return { code: 'NoFault', message: '' };

	let message = exit.reason ?? '';
	if (exit.errno)
		message += sprintf(' (errno %d)', exit.errno);

	if (exit.reason == 'uxc.image-volume')
		return { code: 'UnStartable', message };
	if (!exit.started)
		return { code: exit['started-by'] == 'boot' ? 'FailureOnAutoStart' : 'FailureOnStart', message };
	if (exit['exit-code'])
		return { code: 'FailureWhileActive', message: sprintf('exited with code %d', exit['exit-code']) };

	return { code: 'NoFault', message: '' };
}

function cgroup_dir(eu) {
	if (!eu.entry.pid)
		return null;

	let m = match(fs.readfile(sprintf('/proc/%d/cgroup', eu.entry.pid)) ?? '', /0::(\S+)/);
	return m ? CGROUP_ROOT + m[1] : null;
}

function cgroup_int(dir, attr) {
	if (!dir)
		return null;

	let text = ubbf.readfile_trim(dir + '/' + attr, '');
	return match(text, /^[0-9]+$/) ? int(text) : null;
}

function cpu_percent(eu, dir) {
	let m = dir ? match(ubbf.readfile_trim(dir + '/cpu.max', ''), /^([0-9]+) ([0-9]+)$/) : null;
	if (m)
		return int(int(m[1]) * 100 / int(m[2]));

	let tag = match(eu.du?.tags?.cpu ?? '', /^([0-9]+)$/);
	return tag ? int(tag[1]) : -1;
}

function memory_limit_kib(eu, dir) {
	let limit = cgroup_int(dir, 'memory.max');
	if (limit != null)
		return kib(limit);

	let tag = eu.du?.tags?.memory;
	let pct = match(tag ?? '', /^([0-9]+)pct$/);
	if (pct) {
		let total = match(fs.readfile('/proc/meminfo') ?? '', /MemTotal:\s+(\d+) kB/);
		return total ? int(int(total[1]) * int(pct[1]) / 100) : -1;
	}
	return kib(size_bytes(tag));
}

function id_map(eu, file) {
	if (!eu.entry.pid)
		return null;

	let m = match(fs.readfile(sprintf('/proc/%d/%s', eu.entry.pid, file)) ?? '', /^\s*(\d+)\s+(\d+)\s+(\d+)/);
	return m ? [ int(m[1]), int(m[2]) ] : null;
}

function volume_used_kib(vol) {
	if (!vol?.up)
		return null;

	let st = ubbf.statvfs_info(UVOL_DIR + '/' + vol.name);
	return st ? st.total_kib - st.free_kib : null;
}

function eu_volumes(eu) {
	let rows = [];

	for (let vol in (eu.info['data-volumes'] ?? [])) {
		push(rows, {
			eu, kind: 'data', name: vol.name, volume: vol.volume,
			path: vol.mountpoint, from: vol.from,
			bytes: vol['size-bytes'] ?? size_bytes(vol.size),
			up: !!vol.up
		});
	}

	let overlay = eu.info.overlay ?? {};
	if (overlay.kind == 'volume') {
		push(rows, {
			eu, kind: 'overlay', name: 'overlay', volume: overlay.volume?.name,
			path: '/', from: 'registration',
			bytes: overlay.volume?.size ?? size_bytes(overlay.size),
			up: !!overlay.volume?.up
		});
	} else if (overlay.kind == 'tmpfs') {
		push(rows, {
			eu, kind: 'tmpfs', name: 'overlay', path: '/', from: 'registration',
			bytes: size_bytes(overlay.size), up: eu_live(eu)
		});
	}

	return rows;
}

function appdata_rows(view) {
	let rows = [];
	for (let eu in view.eus) {
		for (let row in eu_volumes(eu)) {
			row.index = length(rows) + 1;
			push(rows, row);
		}
	}
	return rows;
}

function appdata_to_object(row) {
	let volume = row.volume ?? sprintf('%s.%s', row.eu.name, row.name);
	let used = row.kind == 'tmpfs' ? null : volume_used_kib({ name: volume, up: row.up });

	return {
		Name: volume,
		Capacity: sprintf('%d', kib(row.bytes) < 0 ? 0 : kib(row.bytes)),
		Encrypted: 'false',
		Retain: row.kind == 'tmpfs' ? 'UntilStopped' : 'Forever',
		AccessPath: row.path ?? '',
		Alias: ubbf.alias_from_name(volume),
		ApplicationUUID: row.eu.du?.uuid ?? '',
		Utilization: sprintf('%d', used ?? 0)
	};
}

function ip_interface_refs(root, names) {
	let table = root?.Device?.IP?.Interface ?? {};
	let refs = [];

	for (let key in sort(keys(table), (a, b) => int(a) - int(b))) {
		if (!ubbf.is_instance_key(key))
			continue;
		let name = table[key]?.Name;
		if (!name || (names && index(names, name) < 0))
			continue;
		push(refs, sprintf('Device.IP.Interface.%s', key));
	}
	return refs;
}

function ip_interface_names(root) {
	let names = [];
	for (let key, row in (root?.Device?.IP?.Interface ?? {})) {
		if (ubbf.is_instance_key(key) && row?.Name)
			push(names, row.Name);
	}
	return names;
}

function access_networks(eu) {
	let net = eu.info['container-network'] ?? {};
	let attach = net.attach ?? 'none';

	if (attach == 'host')
		return null;
	if (attach == 'bridged')
		return net.network ? [ net.network ] : [];
	if (attach != 'routed')
		return [];

	return filter(net.egress ?? [], (zone) => !match(zone, /^(vpn|container):/));
}

function networkconfig_to_object(eu, root) {
	// The ingress redirects are fw4 state uxc-net creates over ubus; no Device.NAT.PortMapping row exists for them.
	return {
		AccessInterfaceRefList: join(',', ip_interface_refs(root, access_networks(eu))),
		PortMappingRefList: ''
	};
}

function hostobjects_of(eu) {
	let rows = [];

	for (let prov in (eu.info.provision ?? [])) {
		let options = [ 'ro', prov.from ];
		if (prov.secret)
			push(options, 'secret');
		if (prov.shadowed)
			push(options, 'shadowed');
		push(rows, { Source: prov.source, Destination: prov.destination, Options: join(',', options) });
	}

	for (let vol in (eu.info['data-volumes'] ?? []))
		push(rows, { Source: UVOL_DIR + '/' + vol.volume, Destination: vol.mountpoint, Options: 'rw,' + vol.from });

	if (eu.info['hosts-file'])
		push(rows, { Source: eu.info['hosts-file'], Destination: '/etc/hosts', Options: 'ro,registration' });

	return rows;
}

function hostobject_to_object(row) {
	return {
		Source: row.Source ?? '',
		Destination: row.Destination ?? '',
		Options: row.Options ?? '',
		Alias: ubbf.alias_from_name(row.Destination ?? '')
	};
}

function envvariables_of(eu) {
	let env = eu.info.env ?? {};
	return map(sort(keys(env)), (key) => ({ Key: key, Value: sprintf('%s', env[key]) }));
}

function envvariable_to_object(row) {
	return {
		Key: row.Key,
		Value: row.Value,
		Alias: ubbf.alias_from_name(row.Key)
	};
}

function autorestart_to_object(eu) {
	let respawn = eu.info.respawn ?? {};

	return {
		Enable: respawn.enable ? 'true' : 'false',
		RetryMinimumWaitInterval: sprintf('%d', respawn.min ?? 0),
		RetryMaximumWaitInterval: sprintf('%d', respawn.max ?? 0),
		RetryIntervalMultiplier: sprintf('%d', respawn.multiplier ?? 0),
		MaximumRetryCount: sprintf('%d', respawn['max-retries'] ?? 0),
		ResetPeriod: sprintf('%d', respawn['reset-period'] ?? 0),
		RetryCount: sprintf('%d', respawn['retry-count'] ?? 0),
		LastRestarted: respawn['last-restarted'] ?? UNKNOWN_TIME,
		NextRestart: respawn['next-restart'] ?? INFINITE_TIME
	};
}

function process_refs(dir) {
	if (!dir)
		return [];

	let pids = filter(split(fs.readfile(dir + '/cgroup.procs') ?? '', '\n'), (p) => match(p, /^[0-9]+$/));
	return map(pids, (pid) => sprintf('Device.DeviceInfo.ProcessStatus.Process.%s', pid));
}

function eu_to_object(eu, view, root) {
	let fault = eu_fault(eu);
	let dir = cgroup_dir(eu);
	let uid = id_map(eu, 'uid_map');
	let gid = id_map(eu, 'gid_map');
	let host_uid = eu.du?.tags?.uid ? int(eu.du.tags.uid) : 0;
	let created = rfc3339_parse(eu.entry.created);
	let volumes = eu_volumes(eu);
	let image = eu.info['image-volume'];
	let hostobjects = hostobjects_of(eu);
	let envvariables = envvariables_of(eu);
	let allocated = image?.size ?? null;
	let in_use = volume_used_kib(image);

	for (let vol in volumes) {
		if (vol.bytes != null)
			allocated = (allocated ?? 0) + vol.bytes;
		let used = vol.kind == 'tmpfs' ? null : volume_used_kib({ name: vol.volume, up: vol.up });
		if (used != null)
			in_use = (in_use ?? 0) + used;
	}

	let appdata = filter(appdata_rows(view), (row) => row.eu == eu);
	let refs = ip_interface_refs(root, access_networks(eu));

	return {
		EUID: eu.name,
		Alias: ubbf.alias_from_name(eu.name),
		Name: eu.name,
		ExecEnvLabel: eu.name,
		Status: STATUS_MAP[eu.entry.status] ?? 'Idle',
		ExecutionFaultCode: fault.code,
		ExecutionFaultMessage: fault.message,
		AutoStart: eu.info.autostart ? 'true' : 'false',
		RunLevel: '0',
		Vendor: eu.du?.vendor ?? '',
		Version: eu.du?.version ?? '',
		Description: eu.du?.pkg_info?.description ?? '',
		Privileged: (eu.du?.tags?.userns == 'off') ? 'true' : 'false',
		AllocatedDiskSpace: sprintf('%d', kib(allocated)),
		DiskSpaceInUse: sprintf('%d', in_use ?? -1),
		AllocatedMemory: sprintf('%d', memory_limit_kib(eu, dir)),
		MemoryInUse: sprintf('%d', kib(cgroup_int(dir, 'memory.current'))),
		AllocatedCPUPercent: sprintf('%d', cpu_percent(eu, dir)),
		CPUPercentInUse: '-1',
		AllocatedEUUID: sprintf('%d', uid ? uid[0] : 0),
		AllocatedEUGID: sprintf('%d', gid ? gid[0] : 0),
		AllocatedHostUID: sprintf('%d', uid ? uid[1] : host_uid),
		AllocatedHostGID: sprintf('%d', gid ? gid[1] : host_uid),
		CreationTime: created ? eu.entry.created : UNKNOWN_TIME,
		Uptime: sprintf('%d', (created && eu_live(eu)) ? time() - created : 0),
		ShutdownDelay: sprintf('%d', eu.info['stop-timeout'] ?? 10),
		References: join(',', refs),
		AssociatedProcessList: join(',', process_refs(dir)),
		VendorLogList: '',
		VendorConfigList: '',
		ApplicationDataList: join(',', map(appdata, (row) => sprintf('%s.ApplicationData.%d', EE_REF, row.index))),
		ExecutionEnvRef: EE_REF,
		HostObjectNumberOfEntries: sprintf('%d', length(hostobjects)),
		EnvVariableNumberOfEntries: sprintf('%d', length(envvariables)),
		HostObject: ubbf.enumerate_instances(hostobjects, hostobject_to_object),
		EnvVariable: ubbf.enumerate_instances(envvariables, envvariable_to_object),
		AutoRestart: autorestart_to_object(eu),
		NetworkConfig: networkconfig_to_object(eu, root)
	};
}

function du_to_object(du) {
	let resolved = true;
	for (let eu in du.eus) {
		if (!eu.info['image-volume']?.up)
			resolved = false;
	}

	return {
		UUID: du.uuid,
		DUID: du.pkg,
		Alias: ubbf.alias_from_name(du.pkg),
		Name: du.name,
		Status: pending[du.pkg] ?? 'Installed',
		Resolved: resolved ? 'true' : 'false',
		URL: 'apk://' + du.pkg,
		Description: du.pkg_info?.description ?? '',
		Vendor: du.vendor,
		Version: du.version,
		VendorLogList: '',
		VendorConfigList: '',
		ExecutionUnitList: join(',', map(du.eus, eu_ref)),
		ExecutionEnvRef: EE_REF,
		InternalController: '',
		Installed: UNKNOWN_TIME,
		LastUpdate: UNKNOWN_TIME,
		ModuleVersion: du.eus[0]?.info?.['module-version'] ?? ''
	};
}

function execenv_to_object(root) {
	let view = view_get();
	let disabled = containers_disabled(view);
	let ready = index(ubus.list() ?? [], 'container') >= 0;
	let active = filter(view.eus, eu_live);
	let appdata = appdata_rows(view);
	let meminfo = match(fs.readfile('/proc/meminfo') ?? '', /MemAvailable:\s+(\d+) kB/);

	return {
		Enable: disabled ? 'false' : 'true',
		Status: disabled ? 'Disabled' : (ready ? 'Up' : 'Error'),
		Alias: 'cpe-uxc',
		Name: 'uxc',
		Type: 'OCI Runtime',
		InitialRunLevel: '0',
		CurrentRunLevel: '-1',
		InitialExecutionUnitRunLevel: '-1',
		Vendor: 'openwrt.org',
		Version: utils.cache.call(uxc_version_fetch),
		ParentExecEnv: '',
		AllocatedDiskSpace: sprintf('%d', kib(uvol_bytes('total'))),
		AllocatedMemory: '-1',
		AllocatedCPUPercent: '-1',
		AvailableDiskSpace: sprintf('%d', kib(uvol_bytes('free'))),
		AvailableMemory: sprintf('%d', meminfo ? int(meminfo[1]) : -1),
		AvailableCPUPercent: '-1',
		ActiveExecutionUnits: join(',', map(active, eu_ref)),
		ProcessorRefList: '',
		CreatedAt: UNKNOWN_TIME,
		ExecEnvClassRef: CLASS_REF,
		ApplicationDataNumberOfEntries: sprintf('%d', length(appdata)),
		RestartReason: ee_restart.reason,
		RestartCount: sprintf('%d', ee_restart.count),
		LastRestarted: utils.helpers.datetime_format(ee_restart.time),
		Signers: '',
		AvailableRoles: '',
		AvailableAccessInterfaces: join(',', ip_interface_names(root)),
		AvailableUserRoles: '',
		ApplicationData: ubbf.enumerate_instances(appdata, appdata_to_object)
	};
}

function execenvclass_to_object() {
	return {
		Alias: 'cpe-uxc',
		Name: 'uxc',
		Vendor: 'openwrt.org',
		Version: utils.cache.call(uxc_version_fetch),
		DeploymentUnitRef: '',
		CapabilityNumberOfEntries: '1',
		Capability: {
			'1': {
				Specification: 'OCIImage',
				SpecificationVersion: '[1.1.0,1.3.0]',
				SpecificationURI: 'https://github.com/opencontainers/runtime-spec'
			}
		}
	};
}

function softwaremodules_get(ctx) {
	let view = view_get();

	return {
		ExecEnvClassNumberOfEntries: '1',
		ExecEnvNumberOfEntries: '1',
		DeploymentUnitNumberOfEntries: sprintf('%d', length(view.dus)),
		ExecutionUnitNumberOfEntries: sprintf('%d', length(view.eus))
	};
}

function execenvclass_get(ctx) {
	if (ctx.instance == null)
		return { '1': execenvclass_to_object() };

	return ctx.instance == 1 ? execenvclass_to_object() : null;
}

function execenv_get(ctx) {
	if (ctx.instance == null)
		return { '1': execenv_to_object(ctx.root) };

	return ctx.instance == 1 ? execenv_to_object(ctx.root) : null;
}

function du_get(ctx) {
	let view = view_get();

	if (ctx.instance == null)
		return ubbf.enumerate_instances(view.dus, du_to_object);

	let du = ubbf.get_by_instance(view.dus, ctx.instance);
	return du ? du_to_object(du) : null;
}

function eu_get(ctx) {
	let view = view_get();
	let to_object = (eu) => eu_to_object(eu, view, ctx.root);

	if (ctx.instance == null)
		return ubbf.enumerate_instances(view.eus, to_object);

	let eu = ubbf.get_by_instance(view.eus, ctx.instance);
	return eu ? to_object(eu) : null;
}

function stored_rows_drop(ctx, table) {
	// A stored row hides the rows enumerated from the stack, so a write is applied to uxc and its stored copy removed.
	let sm = ctx.root?.Device?.SoftwareModules;
	if (sm)
		delete sm[table];
}

function uxc_apply(parts) {
	let result = command_run(parts, true);
	if (result.exitcode == 0)
		return 0;

	utils.logging.log_err('softwaremodules: %s: %s', join(' ', parts), result_message(result));
	return -1;
}

function execenv_set(ctx) {
	stored_rows_drop(ctx, 'ExecEnv');
	if (ctx.instance != 1 || ctx.param != 'Enable')
		return -1;

	return uxc_apply([ 'uxc', ubbf.to_bool(ctx.value) ? 'enable-all' : 'disable-all' ]);
}

function eu_set(ctx) {
	let eu = eu_by_instance(ctx.instance);

	stored_rows_drop(ctx, 'ExecutionUnit');
	if (!eu)
		return -1;
	if (ctx.param == 'AutoStart')
		return uxc_apply([ 'uxc', ubbf.to_bool(ctx.value) ? 'enable' : 'disable', eu.name ]);
	if (ctx.param == 'ShutdownDelay')
		return uxc_apply([ 'uxc', 'set', eu.name, '--stop-timeout', int(ctx.value) ]);

	return -1;
}

function autorestart_set(ctx) {
	let eu = eu_by_instance(ctx.instance);

	stored_rows_drop(ctx, 'ExecutionUnit');
	if (!eu)
		return -1;
	if (ctx.param == 'RetryCount')
		return uxc_apply([ 'uxc', 'respawn-reset', eu.name, int(ctx.value) ]);

	let key = RESPAWN_KEYS[ctx.param];
	if (!key)
		return -1;

	let value = (key == 'enable') ? (ubbf.to_bool(ctx.value) ? 1 : 0) : int(ctx.value);
	return uxc_apply([ 'uxc', 'set', eu.name, '--respawn', sprintf('%s=%d', key, value) ]);
}

function input_rows(input, prefix) {
	let rows = {};
	let pattern = regexp('^' + replace(prefix, '.', '\\.') + '\\.([0-9]+)\\.([A-Za-z]+)$');

	for (let key, value in input) {
		let m = match(key, pattern);
		if (!m)
			continue;
		rows[m[1]] ??= {};
		rows[m[1]][m[2]] = value;
	}

	return map(sort(keys(rows), (a, b) => int(a) - int(b)), (k) => rows[k]);
}

function du_state_change_emit(ev) {
	usp_datamodel_event(SM + '.DUStateChange!', {
		UUID: ev.uuid ?? '',
		DeploymentUnitRef: ev.du ? sprintf('%s.DeploymentUnit.%d', SM, ev.du.index) : '',
		Version: ev.version ?? '',
		CurrentState: ev.state,
		Resolved: ev.du ? du_to_object(ev.du).Resolved : 'false',
		ExecutionUnitRefList: ev.du ? join(',', map(ev.du.eus, eu_ref)) : '',
		StartTime: utils.helpers.datetime_format(ev.start),
		CompleteTime: utils.helpers.datetime_format(time()),
		OperationPerformed: ev.operation,
		'Fault.FaultCode': sprintf('%d', ev.fault_code ?? 0),
		'Fault.FaultString': ev.fault_string ?? ''
	});
}

function apk_url_parse(url) {
	let m = match(url ?? '', /^apk:\/\/([A-Za-z0-9][A-Za-z0-9._+-]*)(=([A-Za-z0-9._+~-]+))?$/);
	if (!m)
		return null;

	return { pkg: m[1], version: m[3], spec: m[3] ? m[1] + '=' + m[3] : m[1] };
}

function zone_of_ref(root, ref) {
	return ubbf.interface_to_name(root, rtrim(ref ?? '', '.'));
}

function request_build(input, root) {
	let req = {};

	if (input.Privileged != null)
		req.privileged = ubbf.to_bool(input.Privileged);
	if (input['NetworkConfig.AccessInterfaces'] != null)
		req.access_interfaces = ubbf.csv_to_list(input['NetworkConfig.AccessInterfaces']);
	if (input['Resources.AllocatedMemory'] != null && int(input['Resources.AllocatedMemory']) >= 0)
		req.memory = sprintf('%dk', int(input['Resources.AllocatedMemory']));
	if (input['Resources.AllocatedCPUPercent'] != null && int(input['Resources.AllocatedCPUPercent']) >= 0)
		req.cpu = sprintf('%d', int(input['Resources.AllocatedCPUPercent']));

	let volumes = input_rows(input, 'ApplicationData');
	if (length(volumes)) {
		req.volumes = {};
		for (let vol in volumes)
			req.volumes[vol.Name] = sprintf('%dk', int(vol.Capacity ?? '0'));
	}

	let ingress = [];
	for (let pm in input_rows(input, 'NetworkConfig.PortMapping')) {
		let zone = zone_of_ref(root, pm.Interface);
		if (!zone)
			return { error: sprintf('PortMapping Interface %s is not a Device.IP.Interface row', pm.Interface) };
		push(ingress, sprintf('%s:%s:%s/%s', zone, pm.ExternalPort, pm.InternalPort ?? pm.ExternalPort,
			lc(pm.Protocol ?? 'tcp')));
	}
	if (length(ingress))
		req.ingress = ingress;

	return req;
}

function settings_args(input, with_autorestart) {
	let args = [];
	let respawn = [];

	if (input.ShutdownDelay != null && int(input.ShutdownDelay) > 0)
		push(args, '--stop-timeout', int(input.ShutdownDelay));
	if (input.ModuleVersion != null && input.ModuleVersion != '')
		push(args, '--module-version', input.ModuleVersion);

	for (let name, key in RESPAWN_KEYS) {
		let value = input['AutoRestart.' + name];
		if (!with_autorestart || value == null)
			continue;
		push(respawn, sprintf('%s=%d', key, key == 'enable' ? (ubbf.to_bool(value) ? 1 : 0) : int(value)));
	}
	if (length(respawn))
		push(args, '--respawn', join(',', respawn));

	for (let env in input_rows(input, 'EnvVariable')) {
		if (env.Key)
			push(args, '--env', sprintf('%s=%s', env.Key, env.Value ?? ''));
	}

	for (let obj in input_rows(input, 'HostObject')) {
		if (!obj.Source || !obj.Destination)
			continue;
		let secret = index(ubbf.csv_to_list(obj.Options ?? ''), 'secret') >= 0;
		push(args, '--provision', sprintf('%s:%s%s', obj.Source, obj.Destination, secret ? ':secret' : ''));
	}

	for (let vol in input_rows(input, 'ApplicationData')) {
		if (!vol.Name || !vol.AccessPath)
			continue;
		push(args, '--data-volume', sprintf('%s:%s:%dk', vol.Name, vol.AccessPath, int(vol.Capacity ?? '0')));
	}

	return args;
}

function resources_file_write(input) {
	let resources = {};
	let memory = int(input['Resources.AllocatedMemory'] ?? '-1');
	let cpu = int(input['Resources.AllocatedCPUPercent'] ?? '-1');

	if (memory >= 0)
		resources.memory = { limit: memory * 1024 };
	if (cpu >= 0)
		resources.cpu = { quota: cpu * CPU_PERIOD_DEFAULT / 100, period: CPU_PERIOD_DEFAULT };
	if (!length(resources))
		return null;

	fs.mkdir(WORK_DIR, 0755);
	return fs.writefile(RESOURCES_FILE, sprintf('%J', resources)) ? RESOURCES_FILE : null;
}

function settings_steps(name, input, with_autorestart) {
	let steps = [];
	let args = settings_args(input, with_autorestart);
	let resources = resources_file_write(input);

	if (resources)
		push(args, '--resources', resources);
	if (length(args))
		push(steps, [ 'uxc', 'set', name, ...args ]);

	return steps;
}

function request_check(pkg, req, done) {
	fs.mkdir(WORK_DIR, 0755);
	if (!fs.writefile(REQUEST_FILE, sprintf('%J', req))) {
		done('cannot write ' + REQUEST_FILE);
		return;
	}

	utils.process.popen_async([ 'uxc-req', 'check', pkg, REQUEST_FILE ], (result) => {
		if (result.error) {
			done(result.error);
			return;
		}

		let verdict;
		try {
			verdict = json(result.data);
		} catch (e) {
			verdict = null;
		}

		if (result.exitcode == 0)
			done(null);
		else if (result.exitcode == 1)
			done('request refused: ' + join('; ', verdict?.violations ?? [ 'package tags' ]));
		else
			done(verdict?.error ?? sprintf('cannot evaluate %s', pkg));
	});
}

function du_op_fail(op, fault_code, fault_string) {
	delete pending[op.pkg];
	utils.logging.log_err('softwaremodules: %s %s: %s', op.operation, op.pkg, fault_string);
	du_state_change_emit({
		operation: op.operation, state: 'Failed', uuid: op.uuid, version: op.version,
		du: op.du, start: op.start, fault_code, fault_string
	});
	op.complete(op.instance, USP_ERR_COMMAND_FAILURE, fault_string, {});
}

function du_op_done(op) {
	let du = null;
	for (let candidate in view_get().dus) {
		if (candidate.pkg == op.pkg)
			du = candidate;
	}

	delete pending[op.pkg];
	du_state_change_emit({
		operation: op.operation, state: 'Installed', uuid: du?.uuid,
		version: du?.version, du, start: op.start
	});
	op.complete(op.instance, 0, null, (op.operation == 'Install')
		? { UUID: du?.uuid ?? '', Version: du?.version ?? '', ExecEnvRef: EE_REF }
		: {});
}

function du_op_settings(op, with_autorestart) {
	let eu = eu_by_package(op.pkg);
	let steps = eu ? settings_steps(eu.name, op.input, with_autorestart) : [];

	steps_run(steps, (results, failed) => {
		if (failed)
			du_op_fail(op, FAULT_INVALID_ARGUMENTS, result_message(failed));
		else
			du_op_done(op);
	});
}

function install_du(input, instance, complete, command_key, root) {
	let url = apk_url_parse(input?.URL);
	let ee = rtrim(input?.ExecutionEnvRef ?? '', '.');
	let op = { operation: 'Install', pkg: url?.pkg ?? '', input: input ?? {}, instance, complete, start: time() };

	if (!url) {
		du_op_fail(op, FAULT_INVALID_ARGUMENTS, 'URL must be apk://<package>[=<version>]');
		return;
	}
	if (ee != '' && ee != EE_REF) {
		du_op_fail(op, FAULT_UNKNOWN_EE, 'unknown ExecutionEnvRef ' + ee);
		return;
	}
	if (containers_disabled(view_get())) {
		du_op_fail(op, FAULT_REQUEST_DENIED, 'the execution environment is disabled');
		return;
	}
	if (pending[url.pkg]) {
		du_op_fail(op, FAULT_INVALID_DU_STATE, sprintf('%s is %s', url.pkg, pending[url.pkg]));
		return;
	}

	let req = request_build(op.input, root);
	if (req.error) {
		du_op_fail(op, FAULT_INVALID_ARGUMENTS, req.error);
		return;
	}

	pending[url.pkg] = 'Installing';
	request_check(url.pkg, req, (fault) => {
		if (fault) {
			du_op_fail(op, FAULT_INVALID_ARGUMENTS, fault);
			return;
		}

		steps_run([ [ 'apk', 'add', url.spec ] ], (results, failed) => {
			if (failed)
				du_op_fail(op, FAULT_REQUEST_DENIED, result_message(failed));
			else
				du_op_settings(op, true);
		});
	});
}

function secrets_remove(path) {
	if (substr(path, 0, length(SECRETS_DIR) + 1) != SECRETS_DIR + '/')
		return false;
	if (!fs.lstat(path))
		return true;

	for (let entry in (fs.lsdir(path) ?? [])) {
		let child = path + '/' + entry;
		if (fs.lstat(child)?.type == 'directory')
			secrets_remove(child);
		else
			fs.unlink(child);
	}
	return !!fs.rmdir(path);
}

function leftovers_parse(output) {
	let left = { volumes: [], secrets: [] };

	for (let line in split(output ?? '', '\n')) {
		let vol = match(line, /^\s*uvol remove (\S+)\s*$/);
		let dir = match(line, /^\s*rm -rf (\S+)\s*$/);
		if (vol)
			push(left.volumes, vol[1]);
		else if (dir)
			push(left.secrets, dir[1]);
	}
	return left;
}

function leftovers_remove(left) {
	for (let vol in left.volumes) {
		let reply = uvol_call('remove', { name: vol });
		if (reply?.code)
			return sprintf('uvol remove %s: %s', vol, reply.error ?? reply.code);
	}
	for (let dir in left.secrets) {
		if (!secrets_remove(dir))
			return 'cannot remove ' + dir;
	}
	return null;
}

function uninstall_du(input, instance, complete, instances, command_key) {
	let du = du_by_instance(instances[0]);
	if (!du) {
		complete(instance, USP_ERR_OBJECT_DOES_NOT_EXIST, 'no such DeploymentUnit', {});
		return;
	}

	let op = { operation: 'Uninstall', pkg: du.pkg, du, uuid: du.uuid, version: du.version,
		   instance, complete, start: time() };
	let retain = ubbf.to_bool(input?.RetainData);

	if (pending[du.pkg]) {
		du_op_fail(op, FAULT_INVALID_DU_STATE, sprintf('%s is %s', du.pkg, pending[du.pkg]));
		return;
	}

	pending[du.pkg] = 'Uninstalling';
	steps_run([ [ 'apk', 'del', du.pkg ] ], (results, failed) => {
		if (failed) {
			du_op_fail(op, FAULT_REQUEST_DENIED, result_message(failed));
			return;
		}

		let fault = retain ? null : leftovers_remove(leftovers_parse(results[0].data));
		delete pending[du.pkg];
		du_state_change_emit({
			operation: 'Uninstall', state: 'Uninstalled', uuid: du.uuid, version: du.version,
			start: op.start, fault_code: fault ? FAULT_REQUEST_DENIED : 0, fault_string: fault
		});
		complete(instance, fault ? USP_ERR_COMMAND_FAILURE : 0, fault, {});
	});
}

function du_leftovers(du) {
	let left = { volumes: [], secrets: [] };
	for (let eu in du.eus) {
		for (let vol in eu_volumes(eu)) {
			if (vol.volume)
				push(left.volumes, vol.volume);
		}
		push(left.secrets, SECRETS_DIR + '/' + eu.name);
	}
	return left;
}

function update_du(input, instance, complete, instances, command_key, root) {
	let du = du_by_instance(instances[0]);
	if (!du) {
		complete(instance, USP_ERR_OBJECT_DOES_NOT_EXIST, 'no such DeploymentUnit', {});
		return;
	}

	let op = { operation: 'Update', pkg: du.pkg, du, uuid: du.uuid, version: du.version,
		   input: input ?? {}, instance, complete, start: time() };
	let url = (input?.URL != null && input.URL != '') ? apk_url_parse(input.URL) : { pkg: du.pkg };
	let retain = ubbf.to_bool(input?.RetainData);

	if (!url || url.pkg != du.pkg) {
		du_op_fail(op, FAULT_INVALID_ARGUMENTS, 'URL must be apk://' + du.pkg + '[=<version>]');
		return;
	}
	if (pending[du.pkg]) {
		du_op_fail(op, FAULT_INVALID_DU_STATE, sprintf('%s is %s', du.pkg, pending[du.pkg]));
		return;
	}

	let req = request_build(op.input, root);
	if (req.error) {
		du_op_fail(op, FAULT_INVALID_ARGUMENTS, req.error);
		return;
	}

	let left = retain ? null : du_leftovers(du);
	let live = filter(du.eus, eu_live);
	let steps = [ url.version ? [ 'apk', 'add', url.spec ] : [ 'apk', 'upgrade', du.pkg ] ];

	if (left) {
		for (let eu in live)
			push(steps, [ 'uxc', 'kill', eu.name ]);
	}

	pending[du.pkg] = 'Updating';
	request_check(url.pkg, req, (fault) => {
		if (fault) {
			du_op_fail(op, FAULT_INVALID_ARGUMENTS, fault);
			return;
		}

		steps_run(steps, (results, failed) => {
			if (failed) {
				du_op_fail(op, FAULT_REQUEST_DENIED, result_message(failed));
				return;
			}

			let purge = left ? leftovers_remove(left) : null;
			if (purge) {
				du_op_fail(op, FAULT_REQUEST_DENIED, purge);
				return;
			}

			let restart = [];
			for (let eu in (left ? live : []))
				push(restart, [ 'uxc', 'create', eu.name ], [ 'uxc', 'start', eu.name ]);

			steps_run(restart, (results, failed) => {
				if (failed)
					du_op_fail(op, FAULT_REQUEST_DENIED, result_message(failed));
				else
					du_op_settings(op, false);
			});
		});
	});
}

function lifecycle_done(results, failed) {
	if (failed)
		utils.logging.log_err('softwaremodules: %s: %s', join(' ', failed.command), result_message(failed));
}

function eu_set_requested_state(input, command_key, instances) {
	let eu = eu_by_instance(instances[0]);
	let state = input?.RequestedState;

	if (!eu || (state != 'Active' && state != 'Idle'))
		return null;
	if (state == 'Active' && containers_disabled(view_get()))
		return null;

	if (state == 'Active')
		steps_run([ [ 'uxc', 'create', eu.name ], [ 'uxc', 'start', eu.name ] ], lifecycle_done);
	else
		steps_run([ [ 'uxc', 'kill', eu.name ] ], lifecycle_done);

	return {};
}

function eu_restart(input, command_key, instances) {
	let eu = eu_by_instance(instances[0]);
	if (!eu || containers_disabled(view_get()))
		return null;

	steps_run([ [ 'uxc', 'restart', eu.name ] ], lifecycle_done);
	return {};
}

function appdata_remove(input, command_key, instances) {
	let row = (instances[0] == 1) ? ubbf.get_by_instance(appdata_rows(view_get()), instances[1]) : null;
	if (!row || row.kind == 'tmpfs' || eu_live(row.eu))
		return null;

	if (row.from == 'settings')
		return uxc_apply([ 'uxc', 'set', row.eu.name, '--unset', 'data-volume=' + row.name ]) == 0 ? {} : null;

	let reply = uvol_call('remove', { name: row.volume });
	return reply?.code ? null : {};
}

function execenv_unsupported(input, instance, complete) {
	complete(instance, USP_ERR_COMMAND_FAILURE, 'not supported by the uxc execution environment', {});
}

function execenv_restart(input, instance, complete, instances, command_key) {
	let view = view_get();
	let steps = map(filter(view.eus, eu_live), (eu) => [ 'uxc', 'kill', eu.name ]);

	if (instances[0] != 1 || containers_disabled(view)) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'the execution environment is disabled', {});
		return;
	}

	push(steps, [ 'uxc', 'boot' ]);
	steps_run(steps, (results, failed) => {
		if (failed) {
			complete(instance, USP_ERR_COMMAND_FAILURE, result_message(failed), {});
			return;
		}

		ee_restart = { count: ee_restart.count + 1, reason: input?.Reason ?? '', time: time() };
		usp_datamodel_event(EE_REF + '.Restarted!', {
			RestartTime: utils.helpers.datetime_format(ee_restart.time),
			RestartReason: ee_restart.reason
		});
		complete(instance, 0, null, {});
	});
}

function execenv_reset(input, instance, complete, instances, command_key) {
	let view = view_get();
	let steps = [];

	if (instances[0] != 1) {
		complete(instance, USP_ERR_OBJECT_DOES_NOT_EXIST, 'no such ExecEnv', {});
		return;
	}

	for (let du in view.dus) {
		if (!pending[du.pkg])
			push(steps, [ 'apk', 'del', du.pkg ]);
	}
	push(steps, [ 'uxc', 'reconcile' ]);

	steps_run(steps, (results, failed) => {
		if (failed) {
			complete(instance, USP_ERR_COMMAND_FAILURE, result_message(failed), {});
			return;
		}

		let fault = null;
		for (let result in results)
			fault ??= leftovers_remove(leftovers_parse(result.data));

		complete(instance, fault ? USP_ERR_COMMAND_FAILURE : 0, fault, {});
	});
}

function unsupported_sync() {
	return null;
}

model[SM] = { schema: schemas.SoftwareModules, get: softwaremodules_get };
model[SM + '.ExecEnvClass'] = {};
model[SM + '.ExecEnvClass.{i}'] = { schema: schemas.ExecEnvClass, get: execenvclass_get };
model[SM + '.ExecEnvClass.{i}.Capability'] = {};
model[SM + '.ExecEnvClass.{i}.Capability.{i}'] = { schema: schemas.ExecEnvClass_Capability };
model[SM + '.ExecEnv'] = {};
model[SM + '.ExecEnv.{i}'] = { schema: schemas.ExecEnv, get: execenv_get, set: execenv_set };
model[SM + '.ExecEnv.{i}.ApplicationData'] = {};
model[SM + '.ExecEnv.{i}.ApplicationData.{i}'] = { schema: schemas.ExecEnv_ApplicationData };
model[SM + '.DeploymentUnit'] = {};
model[SM + '.DeploymentUnit.{i}'] = { schema: schemas.DeploymentUnit, get: du_get };
model[SM + '.ExecutionUnit'] = {};
model[SM + '.ExecutionUnit.{i}'] = { schema: schemas.ExecutionUnit, get: eu_get, set: eu_set };
model[SM + '.ExecutionUnit.{i}.HostObject'] = {};
model[SM + '.ExecutionUnit.{i}.HostObject.{i}'] = { schema: schemas.ExecutionUnit_HostObject };
model[SM + '.ExecutionUnit.{i}.EnvVariable'] = {};
model[SM + '.ExecutionUnit.{i}.EnvVariable.{i}'] = { schema: schemas.ExecutionUnit_EnvVariable };
model[SM + '.ExecutionUnit.{i}.AutoRestart'] = { schema: schemas.ExecutionUnit_AutoRestart, set: autorestart_set };
model[SM + '.ExecutionUnit.{i}.NetworkConfig'] = { schema: schemas.ExecutionUnit_NetworkConfig };

operations[SM + '.InstallDU()'] = { type: 'async', handler: install_du };
operations[SM + '.DeploymentUnit.{i}.Update()'] = { type: 'async', handler: update_du };
operations[SM + '.DeploymentUnit.{i}.Uninstall()'] = { type: 'async', handler: uninstall_du };
operations[SM + '.ExecutionUnit.{i}.SetRequestedState()'] = { type: 'sync', handler: eu_set_requested_state };
operations[SM + '.ExecutionUnit.{i}.Restart()'] = { type: 'sync', handler: eu_restart };
operations[SM + '.ExecEnvClass.{i}.AddExecEnv()'] = { type: 'sync', handler: unsupported_sync };
operations[SM + '.ExecEnv.{i}.SetRunLevel()'] = { type: 'sync', handler: unsupported_sync };
operations[SM + '.ExecEnv.{i}.ModifyConstraints()'] = { type: 'async', handler: execenv_unsupported };
operations[SM + '.ExecEnv.{i}.ModifyAvailableRoles()'] = { type: 'async', handler: execenv_unsupported };
operations[SM + '.ExecEnv.{i}.ModifyAvailableAccessInterfaces()'] = { type: 'async', handler: execenv_unsupported };
operations[SM + '.ExecEnv.{i}.Restart()'] = { type: 'async', handler: execenv_restart };
operations[SM + '.ExecEnv.{i}.Reset()'] = { type: 'async', handler: execenv_reset };
operations[SM + '.ExecEnv.{i}.Remove()'] = { type: 'async', handler: execenv_unsupported };
operations[SM + '.ExecEnv.{i}.ApplicationData.{i}.Remove()'] = { type: 'sync', handler: appdata_remove };
