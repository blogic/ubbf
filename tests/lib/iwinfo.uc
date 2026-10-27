// Stand-in for the iwinfo module, which the host lacks: no wiphy and no
// interface until a test fills phys or ifaces.
export const phys = [];
export const ifaces = {};
export function update() {};
export function assoclist() { return {}; };
