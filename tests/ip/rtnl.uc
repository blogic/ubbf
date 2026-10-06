// Stand-in for the rtnl module: no addresses and no routes.
export function request() {
	return [];
};

const consts = { RTM_GETADDR: 22, RTM_GETROUTE: 26, NLM_F_DUMP: 0x300, AF_INET6: 10, RT_SCOPE_LINK: 253 };
export { consts as "const" };
