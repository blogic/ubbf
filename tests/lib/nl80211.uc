// Stand-in for the nl80211 module, which the host lacks: no kernel answers.
const C = { NL80211_CMD_GET_STATION: 17, NLM_F_DUMP: 0x300 };

export function request() { return null; };
export function error() { return null; };
export function listener() { return null; };
export { C as 'const' };
