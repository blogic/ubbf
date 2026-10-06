// Stand-in for the ubus module: answers network.interface.<name> status
// from global.netifd, an interface name to status map.
export function call(object, method) {
	let m = match(object, /^network\.interface\.(.+)$/);
	return (m && method == 'status') ? global.netifd?.[m[1]] : null;
};
