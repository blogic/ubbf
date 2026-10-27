// Host stand-in for ubus: records events and calls in global.ubus_log,
// answers bbf-device apply with success and upnpd mappings from
// global.upnpd_mappings. A call takes the object, method and data either as
// arguments or as one object.
export function call(object, method, args) {
	if (type(object) == 'object') {
		method = object.method;
		args = object.data;
		object = object.object;
	}

	push(global.ubus_log ??= [], [ 'call', object, method, args ]);

	if (object == 'bbf-device' && method == 'apply')
		return { success: true, logs: [] };
	if (object == 'upnpd' && method == 'mappings')
		return { mappings: global.upnpd_mappings ?? [] };
	if (object == 'upnpd' && method == 'delete_mapping')
		return {};
	return null;
};
export function event(name, data) {
	push(global.ubus_log ??= [], [ 'event', name, data ]);
	return true;
};
export function connect() { return null; };
export function subscriber() { return null; };
export function listener() { return null; };
export function publish() { return null; };
export function error() { return null; };
