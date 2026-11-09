// Host stand-in for ubus: records events and calls in global.ubus_log,
// answers bbf-device apply with success, upnpd mappings from
// global.upnpd_mappings, and any other call with the value of
// global.ubus_replies[object][method].
// A call takes the object, method and data either as arguments or as one
// object.
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

	return global.ubus_replies?.[object]?.[method];
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

// A handler loads ubus with require(), which compiles a .uc file as a
// script; on a device import and require share the one ubus.so.
modules.ubus ??= { call, event, connect, subscriber, listener, publish, error };
