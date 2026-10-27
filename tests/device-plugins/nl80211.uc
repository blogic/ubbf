// Stand-in for the nl80211 module: the plugins only need it to load.
const constants = {};

export function request() { return null; };
export { constants as "const" };
