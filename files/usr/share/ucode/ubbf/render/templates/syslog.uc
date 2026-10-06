function render_config() {
const SYSLOG_NG_CONF = '/etc/syslog-ng.conf';
const BRIDGE_IP = '127.0.0.1';
const BRIDGE_PORT = 5514;

// TR-181 facility name -> syslog-ng facility token
const FACILITY_MAP = {
	Kern: 'kern',
	User: 'user',
	Mail: 'mail',
	Daemon: 'daemon',
	Auth: 'auth',
	Syslog: 'syslog',
	LPR: 'lpr',
	News: 'news',
	UUCP: 'uucp',
	Cron: 'cron',
	AuthPriv: 'authpriv',
	FTP: 'ftp',
	NTP: 'ntp',
	Audit: 'audit',
	Console: 'console',
	Cron2: 'solaris-cron',
	Local0: 'local0',
	Local1: 'local1',
	Local2: 'local2',
	Local3: 'local3',
	Local4: 'local4',
	Local5: 'local5',
	Local6: 'local6',
	Local7: 'local7'
};

// TR-181 severity -> syslog-ng level token (ordered emerg=0..debug=7)
const SEVERITY_ORDER = [ 'emerg', 'alert', 'crit', 'err', 'warning', 'notice', 'info', 'debug' ];
const SEVERITY_MAP = {
	Emergency: 'emerg',
	Alert: 'alert',
	Critical: 'crit',
	Error: 'err',
	Warning: 'warning',
	Notice: 'notice',
	Info: 'info',
	Debug: 'debug'
};

/**
 * Trims surrounding whitespace and `[`/`]` brackets from a TR-181 list
 * literal so callers see a bare comma-separated payload.
 *
 * @param {string} value - Raw TR-181 list value
 * @returns {string} Trimmed payload
 */
function trim_list(value) {
	if (type(value) != 'string')
		return '';
	let v = trim(value);
	if (length(v) >= 2 && substr(v, 0, 1) == '[' && substr(v, length(v) - 1) == ']')
		v = trim(substr(v, 1, length(v) - 2));
	return v;
}

/**
 * Splits a TR-181 list value into trimmed non-empty tokens.
 *
 * @param {string} value - TR-181 list value (optionally bracketed)
 * @returns {array} Tokens with surrounding whitespace removed
 */
function split_list(value) {
	let v = trim_list(value);
	if (v == '')
		return [];
	let out = [];
	for (let part in split(v, ',')) {
		let t = trim(part);
		if (t != '')
			push(out, t);
	}
	return out;
}

/**
 * Extracts the trailing instance number from a TR-181 row reference.
 *
 * Accepts variants like `Device.Syslog.Source.3`, `.Syslog.Source.3`,
 * `Source.3.` and returns the integer instance.
 *
 * @param {string} ref - TR-181 path reference
 * @returns {number|null} Instance number, or null if no trailing digits
 */
function ref_instance(ref) {
	if (type(ref) != 'string')
		return null;
	let m = match(ref, /\.([0-9]+)\.?$/);
	if (!m)
		return null;
	return +m[1];
}

/**
 * Maps a TR-181 facility list to a syslog-ng `facility(...)` argument list.
 *
 * Empty result means "no facility constraint" (caller should omit the
 * facility() filter clause).
 *
 * @param {string} csv - TR-181 list of facility names (e.g. "[Kern,Mail]")
 * @returns {array} syslog-ng facility tokens
 */
function facility_tokens(csv) {
	let tokens = [];
	for (let name in split_list(csv)) {
		if (name == 'All')
			return [];
		let t = FACILITY_MAP[name];
		if (t)
			push(tokens, t);
	}
	return tokens;
}

/**
 * Builds a syslog-ng `level(...)` argument list from TR-181 severity rules.
 *
 * Severity=All -> empty (no constraint). Severity=None -> sentinel ['__none__']
 * which the caller turns into a filter that drops everything.
 *
 * @param {string} severity - TR-181 severity name
 * @param {string} compare - 'Equal' or 'EqualOrHigher'
 * @returns {array|null} Token list, or null when severity is unrecognised
 */
function level_tokens(severity, compare) {
	if (severity == 'All' || !severity)
		return [];
	if (severity == 'None')
		return [ '__none__' ];

	let tok = SEVERITY_MAP[severity];
	if (!tok)
		return null;

	if (compare == 'Equal')
		return [ tok ];

	let idx = -1;
	for (let i = 0; i < length(SEVERITY_ORDER); i++)
		if (SEVERITY_ORDER[i] == tok) {
			idx = i;
			break;
		}
	if (idx < 0)
		return [ tok ];

	let out = [];
	for (let i = 0; i <= idx; i++)
		push(out, SEVERITY_ORDER[i]);
	return out;
}

/**
 * Escapes a string for safe inclusion inside a syslog-ng double-quoted
 * literal. Backslashes and double quotes are backslash-escaped.
 *
 * @param {string} s - Input string
 * @returns {string} Escaped string (without surrounding quotes)
 */
function quote_escape(s) {
	if (type(s) != 'string')
		return '';
	let out = '';
	for (let i = 0; i < length(s); i++) {
		let c = substr(s, i, 1);
		if (c == '\\' || c == '"')
			out += '\\';
		out += c;
	}
	return out;
}

/**
 * Strips a `file://` URI prefix from a TR-181 file path. Pass-through for
 * already-bare paths.
 *
 * @param {string} value - TR-181 file URI or bare path
 * @returns {string} Bare filesystem path
 */
function strip_file_uri(value) {
	if (type(value) != 'string')
		return '';
	if (substr(value, 0, 7) == 'file://')
		return substr(value, 7);
	return value;
}

/**
 * Maps TR-181 protocol enum to syslog-ng transport keyword.
 *
 * @param {string} proto - "TCP" | "UDP" | "TLS"
 * @returns {string} "tcp" | "udp" | "tls"
 */
function transport_for(proto) {
	if (proto == 'TCP') return 'tcp';
	if (proto == 'TLS') return 'tls';
	return 'udp';
}

/**
 * Renders the global options block.
 *
 * @returns {string} `options { ... };` block
 */
function render_options() {
	return 'options {\n' +
		'\tchain_hostnames(no);\n' +
		'\tcreate_dirs(yes);\n' +
		'\tkeep_hostname(yes);\n' +
		'\tlog_fifo_size(256);\n' +
		'\tlog_msg_size(2048);\n' +
		'\tflush_lines(0);\n' +
		'\tuse_fqdn(no);\n' +
		'};\n';
}

/**
 * Renders the loopback bridge source that ingests logd output.
 *
 * @returns {string} `source s_logd_bridge { ... };` block
 */
function render_bridge_source() {
	return sprintf('source s_logd_bridge {\n' +
		'\tnetwork(transport(tcp) ip(%s) port(%d));\n' +
		'};\n', BRIDGE_IP, BRIDGE_PORT);
}

/**
 * Builds the syslog-ng `tls(...)` clause for a server-side network() source.
 *
 * Server side requires both `cert-file()` and `key-file()`. By convention,
 * a single PEM at the resolved path that contains both blocks is used for
 * both. Returns null and warns when the Certificate ref does not resolve,
 * letting the caller skip emitting the listener entirely.
 *
 * @param {object} net - Source.{i}.Network object
 * @param {string} ctx_label - Diagnostic label for warn() output
 * @returns {string|null} `\n\t\ttls(...)` clause, or null when unusable
 */
function tls_server_clause(net, ctx_label) {
	let cert_ref = net.Certificate ?? '';
	if (cert_ref == '') {
		warn('syslog: %s Protocol=TLS requires Certificate; listener disabled', ctx_label);
		return null;
	}
	let cert_path = certificate_path_resolve(cert_ref);
	if (!cert_path) {
		warn('syslog: %s Certificate ref %s does not resolve; listener disabled', ctx_label, cert_ref);
		return null;
	}

	let parts = [
		sprintf('cert-file("%s")', quote_escape(cert_path)),
		sprintf('key-file("%s")', quote_escape(cert_path))
	];

	let ca_ref = net.CABundle ?? '';
	if (ca_ref != '') {
		let ca_dir = cabundle_path_resolve(ca_ref);
		if (ca_dir)
			push(parts, sprintf('ca-dir("%s")', quote_escape(ca_dir)));
		else
			warn('syslog: %s CABundle ref %s does not resolve, omitting ca-dir', ctx_label, ca_ref);
	}

	let peer_verify = ubbf_to_bool(net.PeerVerify) ? 'required-trusted' : 'optional-untrusted';
	push(parts, sprintf('peer-verify(%s)', peer_verify));

	return '\n\t\ttls(' + join(' ', parts) + ')';
}

/**
 * Renders a per-Source.{i}.Network listener.
 *
 * Defaults from the parent Source apply only to messages without a valid
 * RFC 3164 header; they map onto `default-facility()` / `default-priority()`.
 * TLS server side resolves Certificate (cert+key in one PEM) and CABundle
 * (peer-cert validation directory) through the Security data model.
 *
 * @param {number} inst - Source instance number
 * @param {object} src - Source.{i} object (with Network sub-object)
 * @returns {string} Source block, or empty string when network is disabled
 *                   or the TLS cert reference does not resolve
 */
function render_network_source(inst, src) {
	let net = src?.Network;
	if (!net || !ubbf_to_bool(net.Enable))
		return '';

	let proto = net.Protocol ?? 'UDP';
	let tls_clause = '';
	if (proto == 'TLS') {
		tls_clause = tls_server_clause(net, sprintf('Source.%d.Network', inst));
		if (tls_clause === null)
			return '';
	}

	let lines = [];
	push(lines, sprintf('\ttransport(%s)', transport_for(proto)));
	push(lines, sprintf('\tport(%d)', ubbf_to_int(net.Port ?? '1099')));

	let dfl_fac = FACILITY_MAP[src?.FacilityLevel ?? 'All'];
	if (dfl_fac)
		push(lines, sprintf('\tdefault-facility(%s)', dfl_fac));

	let dfl_sev = SEVERITY_MAP[src?.Severity ?? 'All'];
	if (dfl_sev)
		push(lines, sprintf('\tdefault-priority(%s)', dfl_sev));

	if (tls_clause != '')
		push(lines, '\t' + tls_clause);

	return sprintf('source s_source_%d_net {\n\tnetwork(\n%s\n\t);\n};\n', inst, join('\n', lines));
}

/**
 * Returns the syslog-ng filter expression encoding a Source's
 * KernelMessages / SystemMessages toggles, or null when the source
 * contributes nothing (both toggles off).
 *
 * Returns an empty string when no filter is needed (both toggles on).
 *
 * @param {object} src - Source.{i} object
 * @returns {string|null} Filter expression, '' for no-op, null for drop-all
 */
function source_local_expr(src) {
	let kern = ubbf_to_bool(src.KernelMessages);
	let sys = ubbf_to_bool(src.SystemMessages);

	if (kern && sys)
		return '';
	if (kern && !sys)
		return 'facility(kern)';
	if (!kern && sys)
		return 'not facility(kern)';
	return null;
}

/**
 * Builds the positive (un-inverted) syslog-ng filter expression body
 * for a Filter.{i}. Used both for the named filter emission and for
 * Stop-action discard log blocks.
 *
 * @param {number} inst - Filter instance number (for diagnostics)
 * @param {object} f - Filter.{i} object
 * @returns {string} Body expression (without `filter f_X { ... };` wrapping)
 */
function filter_body(inst, f) {
	let parts = [];

	let facs = facility_tokens(f.FacilityLevel ?? 'All');
	if (length(facs) > 0)
		push(parts, sprintf('facility(%s)', join(',', facs)));

	let lvls = level_tokens(f.Severity ?? 'All', f.SeverityCompare ?? 'EqualOrHigher');
	if (lvls === null) {
		warn('syslog: Filter.%d unknown Severity %s, treating as All', inst, f.Severity);
	} else if (length(lvls) > 0) {
		if (lvls[0] == '__none__')
			push(parts, 'level(none)');
		else
			push(parts, sprintf('level(%s)', join(',', lvls)));
	}

	let pat = f.PatternMatch ?? '';
	if (pat != '')
		push(parts, sprintf('match("%s" type(pcre))', quote_escape(pat)));

	return length(parts) > 0 ? join(' and ', parts) : 'level(emerg..debug)';
}

/**
 * Renders a Filter.{i} as a named syslog-ng filter.
 *
 * Block inverts the body (`not (...)`). Stop emits the body as-is; its
 * short-circuit semantics are realised in `render_log_path` by emitting
 * a separate `flags(final)` discard log block.
 *
 * @param {number} inst - Filter instance number
 * @param {object} f - Filter.{i} object
 * @returns {string} `filter f_<i> { ... };` block
 */
function render_filter(inst, f) {
	let body = filter_body(inst, f);
	if ((f.SeverityCompareAction ?? 'Log') == 'Block')
		body = sprintf('not (%s)', body);
	return sprintf('filter f_%d { %s; };\n', inst, body);
}

/**
 * Renders a Template.{i}.
 *
 * @param {number} inst - Template instance number
 * @param {object} t - Template.{i} object
 * @returns {string} `template t_<i> { ... };` block
 */
function render_template(inst, t) {
	let expr = quote_escape(t.Expression ?? '');
	let escape = ubbf_to_bool(t.EscapeMessage) ? 'yes' : 'no';
	return sprintf('template t_%d {\n\ttemplate("%s");\n\ttemplate_escape(%s);\n};\n', inst, expr, escape);
}

/**
 * Renders an Action.{i}.LogFile destination.
 *
 * @param {number} inst - Action instance number
 * @param {object} action - Action.{i} object
 * @returns {string} `destination d_<i>_file { ... };` block, or empty
 */
function render_destination_file(inst, action) {
	let lf = action?.LogFile;
	if (!lf || !ubbf_to_bool(lf.Enable))
		return '';
	let path = strip_file_uri(lf.FilePath ?? '');
	if (path == '')
		return '';

	let tref_inst = ref_instance(action.TemplateRef ?? '');
	let tmpl = tref_inst ? sprintf(' template(t_%d)', tref_inst) : '';

	return sprintf('destination d_%d_file {\n\tfile("%s"%s);\n};\n',
		inst, quote_escape(path), tmpl);
}

/**
 * Builds the syslog-ng `tls(...)` clause for a client (LogRemote) socket.
 *
 * `peer-verify` follows TR-181 PeerVerify: true -> required-trusted,
 * false -> optional-untrusted (still negotiates TLS, doesn't fail on
 * untrusted server cert). CABundle resolves to a directory used as
 * `ca-dir(...)`. Certificate resolves to a PEM that contains both a
 * cert and a private key (used for mutual auth as `cert-file()` plus
 * `key-file()`). When CABundle is absent and PeerVerify=true we still
 * emit ca-dir from the system bundle if one exists, otherwise warn.
 *
 * @param {object} cfg - LogRemote object (carries CABundle, Certificate, PeerVerify)
 * @param {string} ctx_label - Diagnostic label for warn() output
 * @returns {string} `\n\t\ttls(...)` clause to splice into a network() call
 */
function tls_client_clause(cfg, ctx_label) {
	let parts = [];

	let peer_verify = ubbf_to_bool(cfg.PeerVerify) ? 'required-trusted' : 'optional-untrusted';
	push(parts, sprintf('peer-verify(%s)', peer_verify));

	let ca_ref = cfg.CABundle ?? '';
	if (ca_ref != '') {
		let ca_dir = cabundle_path_resolve(ca_ref);
		if (ca_dir)
			push(parts, sprintf('ca-dir("%s")', quote_escape(ca_dir)));
		else
			warn('syslog: %s CABundle ref %s does not resolve, omitting ca-dir', ctx_label, ca_ref);
	}

	let cert_ref = cfg.Certificate ?? '';
	if (cert_ref != '') {
		let cert_path = certificate_path_resolve(cert_ref);
		if (cert_path) {
			push(parts, sprintf('cert-file("%s")', quote_escape(cert_path)));
			push(parts, sprintf('key-file("%s")', quote_escape(cert_path)));
		} else {
			warn('syslog: %s Certificate ref %s does not resolve, omitting cert/key', ctx_label, cert_ref);
		}
	}

	return '\n\t\ttls(' + join(' ', parts) + ')';
}

/**
 * Renders an Action.{i}.LogRemote destination.
 *
 * Honors Protocol (UDP/TCP/TLS), Address, Port, TemplateRef, and full TLS
 * (CABundle / Certificate / PeerVerify resolution).
 *
 * @param {number} inst - Action instance number
 * @param {object} action - Action.{i} object
 * @returns {string} `destination d_<i>_remote { ... };` block, or empty
 */
function render_destination_remote(inst, action) {
	let lr = action?.LogRemote;
	if (!lr || !ubbf_to_bool(lr.Enable))
		return '';
	let addr = lr.Address ?? '';
	if (addr == '')
		return '';

	let proto = lr.Protocol ?? 'UDP';
	let port = ubbf_to_int(lr.Port ?? '514');
	let tref_inst = ref_instance(action.TemplateRef ?? '');
	let tmpl = tref_inst ? sprintf('\n\t\ttemplate(t_%d)', tref_inst) : '';
	let structured = ubbf_to_bool(action.StructuredData) ? '\n\t\tflags(syslog-protocol)' : '';
	let tls_clause = (proto == 'TLS') ? tls_client_clause(lr, sprintf('Action.%d.LogRemote', inst)) : '';

	return sprintf('destination d_%d_remote {\n' +
		'\tnetwork("%s"\n' +
		'\t\tport(%d)\n' +
		'\t\ttransport(%s)%s%s%s\n' +
		'\t);\n' +
		'};\n',
		inst, quote_escape(addr), port, transport_for(proto), tls_clause, tmpl, structured);
}

/**
 * Resolves SourceRef on an Action and emits the right `source(...)` lines
 * plus an inline source-side filter expression when
 * KernelMessages/SystemMessages toggles must restrict the bridge stream.
 *
 * Multiple referenced Sources combine with OR: if any one of them admits a
 * given message, the action sees it.
 *
 * @param {object} action - Action.{i} object
 * @param {object} sources - Map of all Source.{i} objects keyed by instance
 * @returns {object} { source_lines: [...], source_filter: '<expr>'|null }
 */
function resolve_action_sources(action, sources) {
	let want_bridge = false;
	let bridge_unrestricted = false;
	let bridge_clauses = [];
	let net_sources = [];

	for (let ref in split_list(action.SourceRef ?? '')) {
		let inst = ref_instance(ref);
		if (!inst)
			continue;
		let src = sources[sprintf('%d', inst)];
		if (!src)
			continue;

		let expr = source_local_expr(src);
		if (expr !== null) {
			want_bridge = true;
			if (expr == '')
				bridge_unrestricted = true;
			else
				push(bridge_clauses, expr);
		}
		if (src.Network && ubbf_to_bool(src.Network.Enable))
			push(net_sources, sprintf('s_source_%d_net', inst));
	}

	let lines = [];
	if (want_bridge)
		push(lines, '\tsource(s_logd_bridge);');
	for (let s in net_sources)
		push(lines, sprintf('\tsource(%s);', s));

	let combined = null;
	if (want_bridge && !bridge_unrestricted && length(bridge_clauses) > 0) {
		if (length(bridge_clauses) == 1)
			combined = bridge_clauses[0];
		else
			combined = '(' + join(' or ', bridge_clauses) + ')';
	}

	return { source_lines: lines, source_filter: combined, uses_bridge: want_bridge };
}

/**
 * Builds the per-Action source/source-filter prefix lines used by both
 * the regular log path and any Stop discard blocks. Returns null when
 * the Action has no usable sources at all.
 *
 * @param {object} action - Action.{i} object
 * @param {object} sources - Map of Source.{i} objects keyed by instance
 * @returns {object|null} { source_lines: [...], source_filter: '<expr>'|null }
 */
function action_prefix(action, sources) {
	let resolved = resolve_action_sources(action, sources);
	if (length(resolved.source_lines) == 0)
		return null;
	return resolved;
}

/**
 * Renders the Action.{i} log path tying sources, filters, and destinations.
 *
 * For each FilterRef in order, if the referenced Filter has
 * SeverityCompareAction=Stop, an extra discard log block with
 * `flags(final)` is emitted *before* the regular log path. The Stop
 * filter is then omitted from the regular path's filter chain since the
 * discard block already short-circuited any matching messages.
 *
 * @param {number} inst - Action instance number
 * @param {object} action - Action.{i} object
 * @param {object} sources - Map of all Source.{i} objects
 * @param {object} filters - Map of all Filter.{i} objects keyed by instance
 * @returns {object|null} { text: `log { ... };` blocks, has_destination,
 *                          uses_bridge }, or null when nothing is rendered
 */
function render_log_path(inst, action, sources, filters) {
	let prefix = action_prefix(action, sources);
	if (!prefix)
		return null;

	let stop_blocks = [];
	let regular_filters = [];

	for (let ref in split_list(action.FilterRef ?? '')) {
		let fi = ref_instance(ref);
		if (!fi)
			continue;
		let f = filters[sprintf('%d', fi)];
		let act = f?.SeverityCompareAction ?? 'Log';
		if (act == 'Stop') {
			let lines = [];
			for (let s in prefix.source_lines)
				push(lines, s);
			if (prefix.source_filter)
				push(lines, sprintf('\tfilter { %s; };', prefix.source_filter));
			push(lines, sprintf('\tfilter(f_%d);', fi));
			push(lines, '\tflags(final);');
			push(stop_blocks, 'log {\n' + join('\n', lines) + '\n};\n');
		} else {
			push(regular_filters, fi);
		}
	}

	let lines = [];
	for (let s in prefix.source_lines)
		push(lines, s);

	if (prefix.source_filter)
		push(lines, sprintf('\tfilter { %s; };', prefix.source_filter));

	for (let fi in regular_filters)
		push(lines, sprintf('\tfilter(f_%d);', fi));

	let have_dest = false;
	if (action.LogFile && ubbf_to_bool(action.LogFile.Enable) && (action.LogFile.FilePath ?? '') != '') {
		push(lines, sprintf('\tdestination(d_%d_file);', inst));
		have_dest = true;
	}
	if (action.LogRemote && ubbf_to_bool(action.LogRemote.Enable) && (action.LogRemote.Address ?? '') != '') {
		push(lines, sprintf('\tdestination(d_%d_remote);', inst));
		have_dest = true;
	}

	if (!have_dest && length(stop_blocks) == 0)
		return null;

	let main_block = have_dest ? 'log {\n' + join('\n', lines) + '\n};\n' : '';
	return {
		text: join('', stop_blocks) + main_block,
		has_destination: have_dest,
		uses_bridge: prefix.uses_bridge
	};
}

/**
 * Renders the complete syslog-ng configuration and reports which daemons it
 * needs: syslog-ng only when some log path delivers to a destination, and
 * the logd bridge only when such a path reads the local message stream.
 *
 * @returns {object} { content, has_destination, uses_bridge }
 */
function syslog_ng_conf_render() {
	let has_destination = false;
	let uses_bridge = false;
	let parts = [
		'# generated by syslog.uc - do not edit',
		'@version: current',
		'',
		render_options(),
		render_bridge_source()
	];

	// ubbf_instances() returns an ARRAY of objects each carrying their
	// TR-181 instance number under '.instance' (see routing.uc for the
	// convention). Re-key into instance-number-indexed dicts so the
	// per-Action SourceRef / FilterRef lookups in render_log_path can
	// resolve refs by their TR-181 instance.
	let sources_arr = ubbf_instances(config, 'Device.Syslog.Source') ?? [];
	let sources = {};
	for (let src in sources_arr) {
		if (!src) continue;
		let inst = src['.instance'];
		if (!inst) continue;
		sources[sprintf('%d', +inst)] = src;
		let block = render_network_source(+inst, src);
		if (block != '')
			push(parts, block);
	}

	let filters_arr = ubbf_instances(config, 'Device.Syslog.Filter') ?? [];
	let filters = {};
	for (let f in filters_arr) {
		if (!f) continue;
		let inst = f['.instance'];
		if (!inst) continue;
		filters[sprintf('%d', +inst)] = f;
		push(parts, render_filter(+inst, f));
	}

	let templates_arr = ubbf_instances(config, 'Device.Syslog.Template') ?? [];
	for (let t in templates_arr) {
		if (!t) continue;
		let inst = t['.instance'];
		if (!inst) continue;
		push(parts, render_template(+inst, t));
	}

	let actions_arr = ubbf_instances(config, 'Device.Syslog.Action') ?? [];
	for (let action in actions_arr) {
		if (!action) continue;
		let inst = action['.instance'];
		if (!inst) continue;
		let f = render_destination_file(+inst, action);
		if (f != '') push(parts, f);
		let r = render_destination_remote(+inst, action);
		if (r != '') push(parts, r);
	}

	for (let action in actions_arr) {
		if (!action) continue;
		let inst = action['.instance'];
		if (!inst) continue;
		let lp = render_log_path(+inst, action, sources, filters);
		if (!lp)
			continue;
		push(parts, lp.text);
		if (!lp.has_destination)
			continue;
		has_destination = true;
		if (lp.uses_bridge)
			uses_bridge = true;
	}

	return {
		content: join('\n', parts) + '\n',
		has_destination,
		uses_bridge
	};
}

let cfg = ubbf_get(config, 'Device.Syslog');
let rendered = (cfg && ubbf_to_bool(cfg.Enable)) ? syslog_ng_conf_render() : null;
let run_syslog_ng = !!rendered?.has_destination;
let run_bridge = run_syslog_ng && rendered.uses_bridge;

services.set_enabled('syslog-ng', run_syslog_ng);
services.set_enabled('ubbf-syslog-bridge', run_bridge);

if (!run_syslog_ng)
	return;

let old_content = fs.readfile(SYSLOG_NG_CONF) ?? '';
if (rendered.content != old_content) {
	fs.writefile(SYSLOG_NG_CONF, rendered.content);
	// Reload the running syslog-ng if any; the apply pipeline only
	// runs `start`, so without this an in-place config edit is silently
	// ignored until the next reboot. The reload errors silently when
	// syslog-ng is not yet up; first-boot start picks up the file fresh.
	system('/usr/sbin/syslog-ng-ctl reload >/dev/null 2>&1');
	// The bridge reads the hostname at start time only; restart it so
	// hostname changes propagate to the RFC 3164 frames it emits.
	if (run_bridge)
		system('/etc/init.d/ubbf-syslog-bridge restart >/dev/null 2>&1');
}
}
uci_comment(output, '# generated by syslog.uc (no UCI output; /etc/syslog-ng.conf written directly)');
render_config();
