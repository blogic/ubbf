// Stand-in for the uci module: answers get() from global.uci, a
// config to section to option map.
export function cursor() {
	return {
		get: (config, section, option) => global.uci?.[config]?.[section]?.[option]
	};
};
