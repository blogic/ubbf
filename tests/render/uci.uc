// Stand-in for the uci module: an empty configuration.
export function cursor() {
	return {
		load: () => null,
		get: () => null,
		get_all: () => null,
		foreach: () => null
	};
};
