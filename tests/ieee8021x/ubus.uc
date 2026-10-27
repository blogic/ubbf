// Stand-in for the ubus module of tests/ieee8021x.uc: answers the methods
// of wpa_supplicant.<netdev> from global.EAPOL (eapol_status reply keyed by
// netdev) and records the control commands in global.CONTROL; answers the
// methods of hostapd.<netdev> from global.HOSTAPD (station flags keyed by
// netdev, then by MAC address).
return {
	call: (object, method, args) => {
		let h = match(object, /^hostapd\.(.+)$/);
		let clients = h ? global.HOSTAPD?.[h[1]] : null;
		if (clients && method == 'get_status')
			return { driver: 'wired', status: 'ENABLED', iface: h[1] };
		if (clients && method == 'get_clients')
			return { clients };
		if (h)
			return null;

		let m = match(object, /^wpa_supplicant\.(.+)$/);
		let eapol = m ? global.EAPOL?.[m[1]] : null;
		if (!eapol)
			return null;

		if (method == 'eapol_status')
			return eapol;
		if (method == 'eapol_reset') {
			eapol.success_count = 0;
			eapol.failure_count = 0;
			return null;
		}
		if (method != 'control')
			return null;

		push(global.CONTROL ??= [], args.command);
		if (args.command == 'GET_CAPABILITY eap')
			return { result: 'MD5 TLS PEAP MSCHAPV2' };
		return { result: 'OK\n' };
	}
};
