return {
	call: (object, method, args) => {
		if (object != 'upty')
			return null;
		push(global.UPTY_CALLS, { method, args });
		return global.UPTY_REPLY[method];
	},
	error: () => 'Not found'
};
