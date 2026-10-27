function render_config() {
// A directory of its own: the jail of ubbf-logd mounts it, and the file in
// it is replaced on each change.
const LOGD_DIR = '/var/run/ubbf-logd';
const LOGD_CONF = LOGD_DIR + '/config.json';

// TR-181 facility name -> syslog facility number
const FACILITY_MAP = {
	Kern: 0,
	User: 1,
	Mail: 2,
	Daemon: 3,
	Auth: 4,
	Syslog: 5,
	LPR: 6,
	News: 7,
	UUCP: 8,
	Cron: 9,
	AuthPriv: 10,
	FTP: 11,
	NTP: 12,
	Audit: 13,
	Console: 14,
	Cron2: 15,
	Local0: 16,
	Local1: 17,
	Local2: 18,
	Local3: 19,
	Local4: 20,
	Local5: 21,
	Local6: 22,
	Local7: 23
};

// TR-181 severity name -> syslog severity number (emerg=0..debug=7)
const SEVERITY_MAP = {
	Emergency: 0,
	Alert: 1,
	Critical: 2,
	Error: 3,
	Warning: 4,
	Notice: 5,
	Info: 6,
	Debug: 7
};

const SEVERITIES_ALL = 0xff;

// syslog-ng took user.notice for a frame without a valid <PRI>.
const DEFAULT_FACILITY = 1;
const DEFAULT_SEVERITY = 5;

let certificates = {};
include('../security/certificates.uc', { certificates });

let syslog = {};
include('./shared.uc', { syslog });

function instances_by_id(path) {
	let out = {};
	for (let inst in ubbf_instances(config, path) ?? []) {
		let id = +(inst?.['.instance'] ?? 0);
		if (id > 0)
			out[id] = inst;
	}
	return out;
}

function facility_mask(csv) {
	let mask = 0;
	for (let name in syslog.split_list(csv)) {
		if (name == 'All')
			return 0;
		if (name in FACILITY_MAP)
			mask |= 1 << FACILITY_MAP[name];
	}
	return mask;
}

function severity_mask(inst, severity, compare) {
	if (!severity || severity == 'All')
		return SEVERITIES_ALL;
	if (severity == 'None')
		return 0;
	if (!(severity in SEVERITY_MAP)) {
		warn('syslog: Filter.%d unknown Severity %s, treating as All', inst, severity);
		return SEVERITIES_ALL;
	}

	let level = SEVERITY_MAP[severity];
	if (compare == 'Equal')
		return 1 << level;
	return (1 << (level + 1)) - 1;
}

function tls_paths(net, ctx_label) {
	let out = {};

	let cert_ref = net.Certificate ?? '';
	if (cert_ref != '') {
		out.cert = certificates.certificate_path_resolve(cert_ref);
		if (!out.cert)
			warn('syslog: %s Certificate ref %s does not resolve', ctx_label, cert_ref);
	}

	let ca_ref = net.CABundle ?? '';
	if (ca_ref != '') {
		out.ca_dir = certificates.cabundle_path_resolve(ca_ref);
		if (!out.ca_dir)
			warn('syslog: %s CABundle ref %s does not resolve, omitting it', ctx_label, ca_ref);
	}

	return out;
}

function source_network_render(inst, src) {
	let net = src?.Network;
	if (!net || !ubbf_to_bool(net.Enable))
		return null;

	let proto = lc(net.Protocol ?? 'UDP');
	let tls = (proto == 'tls') ? tls_paths(net, sprintf('Source.%d.Network', inst)) : {};
	if (proto == 'tls' && !tls.cert) {
		warn('syslog: Source.%d.Network Protocol=TLS requires a Certificate; listener disabled', inst);
		return null;
	}

	let facility = FACILITY_MAP[src.FacilityLevel ?? 'All'] ?? DEFAULT_FACILITY;
	let severity = SEVERITY_MAP[src.Severity ?? 'All'] ?? DEFAULT_SEVERITY;

	return {
		proto,
		port: ubbf_to_int(net.Port ?? '1099'),
		default_pri: facility * 8 + severity,
		...tls,
		peer_verify: ubbf_to_bool(net.PeerVerify)
	};
}

function source_unix_render(inst, src) {
	let uds = src?.UnixDomainSocket;
	if (!dm_visible('2.21', null))
		return null;
	if (!uds || !ubbf_to_bool(uds.Enable))
		return null;

	let path = syslog.socket_path(uds.Path);
	if (!path) {
		warn('syslog: Source.%d.UnixDomainSocket.Path %s is not one name in %s; socket disabled',
		     inst, uds.Path ?? '', syslog.SOCKET_DIR);
		return null;
	}

	let facility = FACILITY_MAP[src.FacilityLevel ?? 'All'] ?? DEFAULT_FACILITY;
	let severity = SEVERITY_MAP[src.Severity ?? 'All'] ?? DEFAULT_SEVERITY;

	return { path, default_pri: facility * 8 + severity };
}

function source_render(inst, src) {
	return {
		kernel: ubbf_to_bool(src.KernelMessages),
		system: ubbf_to_bool(src.SystemMessages),
		network: source_network_render(inst, src),
		unix: source_unix_render(inst, src)
	};
}

function filter_render(inst, f) {
	return {
		facilities: facility_mask(f.FacilityLevel ?? 'All'),
		severities: severity_mask(inst, f.Severity, f.SeverityCompare ?? 'EqualOrHigher'),
		pattern: f.PatternMatch ?? '',
		action: lc(f.SeverityCompareAction ?? 'Log')
	};
}

function action_remote_render(inst, action) {
	let lr = action?.LogRemote;
	if (!lr || !ubbf_to_bool(lr.Enable) || (lr.Address ?? '') == '')
		return null;

	let proto = lc(lr.Protocol || 'UDP');
	let tls = (proto == 'tls') ? tls_paths(lr, sprintf('Action.%d.LogRemote', inst)) : {};

	return {
		proto,
		address: lr.Address,
		port: ubbf_to_int(lr.Port ?? '514'),
		...tls,
		peer_verify: ubbf_to_bool(lr.PeerVerify)
	};
}

function action_file_render(inst, action) {
	let lf = action?.LogFile;
	if (!lf || !ubbf_to_bool(lf.Enable))
		return null;

	let path = syslog.logfile_path(lf.FilePath);
	if (!path)
		warn('syslog: Action.%d.LogFile.FilePath %s is not a file URI below %s, file disabled',
		     inst, lf.FilePath ?? '', syslog.LOG_DIR);

	return path;
}

function refs_known(inst, csv, table, known) {
	let out = [];
	for (let ref in syslog.split_list(csv)) {
		let id = syslog.ref_instance(table, ref);
		if (id && known[id])
			push(out, id);
		else
			warn('syslog: Action.%d reference %s is not a %s row, ignored', inst, ref, table);
	}
	return out;
}

function has_stop_filter(ids, filters) {
	for (let id in ids)
		if ((filters[id].SeverityCompareAction ?? 'Log') == 'Stop')
			return true;
	return false;
}

// An action without a destination still matters when it has a Stop
// filter: it ends the message for the actions after it.
function action_render(inst, action, sources, filters, templates) {
	let file = action_file_render(inst, action);
	let remote = action_remote_render(inst, action);
	let filter_ids = refs_known(inst, action.FilterRef ?? '', 'Filter', filters);
	if (!file && !remote && !has_stop_filter(filter_ids, filters))
		return null;

	let rendered_sources = refs_known(inst, action.SourceRef ?? '', 'Source', sources);
	if (!length(rendered_sources))
		return null;

	let template = syslog.ref_instance('Template', action.TemplateRef ?? '');

	return {
		id: inst,
		sources: rendered_sources,
		filters: filter_ids,
		template: (template && templates[template]) ? template : null,
		structured: ubbf_to_bool(action.StructuredData),
		file,
		remote
	};
}

function logd_conf_render() {
	let sources = instances_by_id('Device.Syslog.Source');
	let filters = instances_by_id('Device.Syslog.Filter');
	let templates = instances_by_id('Device.Syslog.Template');
	let actions = instances_by_id('Device.Syslog.Action');
	let conf = { sources: {}, filters: {}, templates: {}, actions: [] };

	for (let id, src in sources)
		conf.sources[id] = source_render(+id, src);

	for (let id, f in filters)
		conf.filters[id] = filter_render(+id, f);

	for (let id, t in templates)
		conf.templates[id] = {
			expression: t.Expression ?? '',
			escape: ubbf_to_bool(t.EscapeMessage)
		};

	// Actions run in instance order: a Stop filter ends a message for the
	// actions after its own.
	for (let id in sort(keys(actions), (a, b) => +a - +b)) {
		let rendered = action_render(+id, actions[id], sources, filters, templates);
		if (rendered)
			push(conf.actions, rendered);
	}

	return conf;
}

let cfg = ubbf_get(config, 'Device.Syslog');
let conf = (cfg && ubbf_to_bool(cfg.Enable)) ? logd_conf_render() : null;
let run_logd = length(filter(conf?.actions ?? [], (a) => a.file || a.remote)) > 0;

services.set_enabled('ubbf-logd', run_logd);

if (!run_logd)
	return;

let content = sprintf('%.J\n', conf);
if (dry_run || content == (fs.readfile(LOGD_CONF) ?? ''))
	return;

// The rename keeps a daemon that starts meanwhile from reading half a file.
let tmp = LOGD_CONF + '.tmp';
fs.mkdir(LOGD_DIR, 0755);
if (fs.writefile(tmp, content) == null || !fs.rename(tmp, LOGD_CONF)) {
	error('syslog: cannot write %s', LOGD_CONF);
	return;
}

// A daemon that is not running yet reads the file when it starts.
let reply = ubus.call({ object: 'ubbf-logd', method: 'reload' });
if (reply?.error)
	warn('syslog: ubbf-logd reload: %s', reply.error);
for (let id, result in reply?.actions ?? {})
	if (result != 'ok')
		warn('syslog: ubbf-logd Action.%s: %s', id, result);
}
uci_comment(output, '# generated by syslog/render.uc (no UCI output; /var/run/ubbf-logd.json written directly)');
render_config();
