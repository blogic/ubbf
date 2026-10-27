// Stand-in for the ubus module: answers network.interface.<name> status
// from global.netifd, an interface name to status map, and odhcpd's
// dhcp ipv6leases from global.ipv6leases.
export function call(object, method) {
	if (object == 'dhcp' && method == 'ipv6leases')
		return global.ipv6leases;
	let m = match(object, /^network\.interface\.(.+)$/);
	return (m && method == 'status') ? global.netifd?.[m[1]] : null;
};
