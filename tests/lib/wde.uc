// Stand-in for the native wde module, which modules/easymesh/objectdata.uc
// loads: a device with no DSCP map, and Radio rows with no BSS metrics.
return {
	dscp_map_to_hex: () => "",
	bss_index_by_bssid: () => ({}),
	mac_to_base64: (mac) => mac
};
