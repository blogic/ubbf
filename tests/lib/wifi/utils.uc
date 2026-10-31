// Stand-in for wifi.utils of wifi-scripts, which the host lacks: a test names
// the phy of a radio in its configuration.
export function find_phy(config) { return config?.test_phy; };
