// Device.LEDs.LED.{i}.Enable false sets option disabled on the led section
// of that LED in the system config; the procd led service reloads on the
// change, removes the trigger and turns the LED off.
function render_config() {
	let rows = ubbf_get(config, 'Device.LEDs.LED') ?? {};

	// The board sections come from /etc/config/system alone: the RAM
	// overlay holds the sections of the last render.
	let sections = {};
	let cursor = uci_cursor('/etc/config', '/tmp/.uci', '');
	cursor?.foreach('system', 'led', (s) => {
		if (s.sysfs)
			sections[s.sysfs] = s['.name'];
	});

	for (let key, row in rows) {
		if (type(row) != 'object' || row.Enable == null || ubbf_to_bool(row.Enable))
			continue;

		let name = row.Name;
		if (!name || !fs.stat(`/sys/class/leds/${name}`))
			continue;

		let section = sections[name];
		if (!section) {
			section = `ubbf_led_${key}`;
			uci_named_section(output, `system.${section}`, 'led');
			uci_set_string(output, `system.${section}.sysfs`, name);
		}

		uci_set_boolean(output, `system.${section}.disabled`, true);
	}
}
render_config();
