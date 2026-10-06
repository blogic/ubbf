// Stand-in for the ubus module: answers the usfpd methods from
// global.usfpd_cages, a cage name to { optical, netdev } map, and the
// ModemManager dump from global.mm_modems.
return {
	call: (object, method, args) => {
		let cages = global.usfpd_cages ?? {};

		if (object == 'modemmanager' && method == 'dump')
			return { modem: global.mm_modems ?? [] };
		if (method == 'cages')
			return { cages: keys(cages) };
		if (method == 'cage_status')
			return { SFPPresent: !!cages[args.name], Optical: !!cages[args.name]?.optical };
		if (method == 'optical_status')
			return { Name: cages[args.name]?.netdev, Status: 'Up' };
		return null;
	}
};
