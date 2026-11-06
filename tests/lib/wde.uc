// Stand-in for the native wde module, which modules/easymesh/objectdata.uc
// loads; a device with no DSCP map is the only call that the tests reach.
return { dscp_map_to_hex: () => "" };
