// Stand-in for the native uwsc module, which upty/session.uc imports; the
// host build of uwsc links another libucode than the host ucode. No
// WebSocket connects.
export function connect() { return null; };
