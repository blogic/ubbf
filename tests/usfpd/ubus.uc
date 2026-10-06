// Stand-in for the ubus module: answers the usfpd methods from global.USFPD,
// { cages: [ names ], status: { name: cage_status }, optical: { name:
// optical_status }, transceiver: { name: transceiver } }.
return {
	call: (object, method, args) => {
		let u = global.USFPD ?? {};

		if (object != 'usfpd')
			return null;
		if (method == 'cages')
			return { cages: u.cages ?? [] };
		if (method == 'cage_status')
			return u.status?.[args.name];
		if (method == 'optical_status')
			return u.optical?.[args.name];
		if (method == 'transceiver')
			return u.transceiver?.[args.name];
		return null;
	}
};
