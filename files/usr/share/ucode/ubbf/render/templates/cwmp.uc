// cwmp config lives in persistent flash UCI (/etc/config/cwmp), written by
// the ManagementServer data-model set handler and read directly by cwmpd
// (at boot, before this overlay exists) and the uwsd CR listener (cr.uc,
// live per request). Nothing is rendered to /var/run/uci here: rewriting
// cwmpd's config would force a procd restart mid-session. This template
// only reflects the persisted enable flag into the service state so an
// apply starts/stops cwmpd (start is idempotent: the procd command is
// static, so no restart).
function render_config() {
	let c = uci_cursor();
	let enabled = (c.get('cwmp', 'cwmp', 'enabled') == '1');
	services.set_enabled('cwmp', enabled);
}
render_config();
