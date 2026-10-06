'use strict';

// Schema for Device.NAT.
export const NAT = {
	path: "Device.NAT.",
	schema: {
		"InterfaceSettingNumberOfEntries": dm_type.UINT,
		"PortMappingNumberOfEntries": dm_type.UINT,
		// "MaxNumberOfPortMappings": dm_type.UINT,        // Not in nat.md
		// "PortTriggerNumberOfEntries": dm_type.UINT,    // Not in nat.md
		// "MaxNumberOfPortTriggers": dm_type.UINT        // Not in nat.md
		"X_UBBF_MaxSessions": dm_type.UINT | dm_type.WRITABLE,
		"X_UBBF_ActiveSessions": dm_type.UINT
	},
	defaults: {
		"InterfaceSettingNumberOfEntries": "0",
		"PortMappingNumberOfEntries": "0",
		"X_UBBF_MaxSessions": "0",
		"X_UBBF_ActiveSessions": "0"
	},
	constraints: {
		// 0 keeps the kernel's nf_conntrack_max; MVP-2109 asks for at
		// least 3000 sessions.
		"X_UBBF_MaxSessions": { ranges: [ [ 0, 0 ], [ 3000, 4194304 ] ] }
	}
};

// Schema for Device.NAT.InterfaceSetting.{i}.
export const InterfaceSetting = {
	path: "Device.NAT.InterfaceSetting.{i}.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"Status": dm_type.STRING,
		"Alias": dm_type.STRING | dm_type.WRITABLE,
		"Interface": dm_type.STRING | dm_type.WRITABLE
		// "SourceNetwork": dm_type.STRING | dm_type.WRITABLE,       // Not in nat.md
		// "TCPTranslationTimeout": dm_type.INT | dm_type.WRITABLE,  // Not in nat.md
		// "UDPTranslationTimeout": dm_type.INT | dm_type.WRITABLE   // Not in nat.md
	},
	defaults: {
		"Enable": "false",
		"Status": "Disabled",
		"Alias": "",
		"Interface": ""
	}
};

// Schema for Device.NAT.PortMapping.{i}.
export const PortMapping = {
	path: "Device.NAT.PortMapping.{i}.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"Status": dm_type.STRING,
		"Alias": dm_type.STRING | dm_type.WRITABLE,
		"Interface": dm_type.STRING | dm_type.WRITABLE,
		"AllInterfaces": dm_type.BOOL | dm_type.WRITABLE,
		"LeaseDuration": dm_type.UINT | dm_type.WRITABLE,
		"RemoteHost": dm_type.STRING | dm_type.WRITABLE,
		"ExternalPort": dm_type.UINT | dm_type.WRITABLE,
		"ExternalPortEndRange": dm_type.UINT | dm_type.WRITABLE,
		"InternalPort": dm_type.UINT | dm_type.WRITABLE,
		"Protocol": dm_type.STRING | dm_type.WRITABLE,
		"InternalClient": dm_type.STRING | dm_type.WRITABLE,
		"Description": dm_type.STRING | dm_type.WRITABLE
		// "Origin": dm_type.STRING,                      // Not in nat.md
		// "RemainingLeaseTime": dm_type.UINT,            // Not in nat.md
		// "ScheduleRef": dm_type.STRING | dm_type.WRITABLE, // Not in nat.md
		// "Log": dm_type.BOOL | dm_type.WRITABLE,        // Not in nat.md
		// "LogRef": dm_type.STRING | dm_type.WRITABLE    // Not in nat.md
	},
	defaults: {
		"Enable": "false",
		"Status": "Disabled",
		"Alias": "",
		"Interface": "",
		"AllInterfaces": "false",
		"LeaseDuration": "0",
		"RemoteHost": "",
		"ExternalPort": "0",
		"ExternalPortEndRange": "0",
		"InternalPort": "0",
		"Protocol": "",
		"InternalClient": "",
		"Description": ""
	}
};

// PortTrigger not in nat.md scope - not implemented

// Vendor sub-object for Device.NAT.X_UBBF_Hairpinning.
// Closes MVP-2113. Enable=true drives fw4 reflection=1 with
// reflection_src=external on every PortMapping and DMZ redirect, so the
// internal target sees the WAN external IP/port as the source of
// hairpinned packets (the prpl wording: "packets displaying external
// source IP address and port"). Off by default; the operator opts in
// per deployment, because reflection extends the surface that LAN
// clients can reach via the public address.
export const X_UBBF_Hairpinning = {
	path: "Device.NAT.X_UBBF_Hairpinning.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE
	},
	defaults: {
		"Enable": "false"
	}
};

// Vendor singleton for Device.NAT.X_UBBF_IPPassthrough.
// Closes prplWare MVP-2003, 2016, 2017, 2018, 2019, 2020 (Advanced DMZ /
// IP Passthrough). Move the public WAN IPv4 onto one designated LAN MAC
// via DHCP, give the RG a non-routable secondary on the WAN device,
// SNAT RG egress to the public IP, DNAT inbound management ports back
// to the secondary. Singleton: at most one ADMZ host per RG. While the
// WAN is down or no AdvancedDMZhost is set, dnsmasq is told to ignore
// the ADMZ MAC entirely so the host never receives a LAN-pool offer it
// would later have to surrender (MVP-2020).
//
//   Enable          - master toggle, default false
//   AdvancedDMZhost - target MAC (lower-case colon form, MVP-2016)
//   LeaseTime       - DHCP lease handed to the ADMZ host, seconds, MVP-2019
//   Status          - Disabled | Enabled_NoMAC | Enabled_NoWANIP | Enabled_Active
export const X_UBBF_IPPassthrough = {
	path: "Device.NAT.X_UBBF_IPPassthrough.",
	schema: {
		"Enable":          dm_type.BOOL   | dm_type.WRITABLE,
		"AdvancedDMZhost": dm_type.STRING | dm_type.WRITABLE,
		"LeaseTime":       dm_type.UINT   | dm_type.WRITABLE,
		"Status":          dm_type.STRING
	},
	defaults: {
		"Enable":          "false",
		"AdvancedDMZhost": "",
		"LeaseTime":       "3600",
		"Status":          "Disabled"
	}
};
