/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"
#include "bindings.h"

#include <dirent.h>
#include <limits.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <net/if.h>

/* ---- sysfs reading ----------------------------------------------------- */

/**
 * Reads a text file and returns its trimmed contents.
 *
 * Leading tabs/spaces and trailing whitespace/newlines are stripped.
 * Reads are capped at 8 KiB (sysfs_read_file's static buffer); content
 * beyond that is silently discarded.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1-2 expected: path, optional default)
 * @return       trimmed string contents, the default value on failure, or null
 */
uc_value_t *
uc_ubbf_readfile_trim(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *path_val = uc_fn_arg(0);
	uc_value_t *def_val = uc_fn_arg(1);
	char *content;

	if (ucv_type(path_val) != UC_STRING)
		return def_val ? ucv_get(def_val) : NULL;

	content = sysfs_read_file(ucv_string_get(path_val));
	if (!content)
		return def_val ? ucv_get(def_val) : NULL;

	uc_value_t *r = ucv_string_new(content);
	free(content);

	return r;
}

/**
 * Reads a text file and parses its trimmed content as a base-10 integer.
 *
 * Returns the supplied default on read failure or unparsable content.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1-2 expected: path, optional default int)
 * @return       parsed integer or default value
 */
uc_value_t *
uc_ubbf_readfile_int(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *path_val = uc_fn_arg(0);
	uc_value_t *def_val = uc_fn_arg(1);
	int64_t def_int;
	char *content;
	char *endp;
	long long val;

	def_int = (ucv_type(def_val) == UC_INTEGER) ? ucv_int64_get(def_val) : 0;

	if (ucv_type(path_val) != UC_STRING)
		return ucv_int64_new(def_int);

	content = sysfs_read_file(ucv_string_get(path_val));
	if (!content)
		return ucv_int64_new(def_int);

	val = strtoll(content, &endp, 10);
	if (!*content || *endp != '\0')
		val = def_int;
	free(content);

	return ucv_int64_new(val);
}

/**
 * Reads `/proc/uptime` and returns the integer seconds component.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       uptime in seconds, or 0 on read failure
 */
uc_value_t *
uc_ubbf_uptime_read(uc_vm_t *vm, size_t nargs)
{
	char *content = sysfs_read_file("/proc/uptime");
	long long val;
	char *endp;

	if (!content)
		return ucv_int64_new(0);

	val = strtoll(content, &endp, 10);
	free(content);

	return ucv_int64_new(val >= 0 ? val : 0);
}

/* ---- ethernet helpers -------------------------------------------------- */

/**
 * Maps a Linux operstate string to its TR-181 Status equivalent.
 *
 * Unknown or NULL input maps to `Error`.
 *
 * @param state  Linux operstate string (e.g. `up`, `down`, `dormant`)
 * @return       static TR-181 Status string
 */
const char *
operstate_map(const char *state)
{
	if (!state) return "Error";
	if (strcmp(state, "up") == 0) return "Up";
	if (strcmp(state, "down") == 0) return "Down";
	if (strcmp(state, "unknown") == 0) return "Unknown";
	if (strcmp(state, "dormant") == 0) return "Dormant";
	if (strcmp(state, "notpresent") == 0) return "NotPresent";
	if (strcmp(state, "lowerlayerdown") == 0) return "LowerLayerDown";
	return "Error";
}

/**
 * Reads a `/sys/class/net/<ifname>/<file>` attribute, with fallback default.
 *
 * @param ifname interface name
 * @param file   attribute name relative to the netdev directory
 * @param def    string returned (heap-duplicated) on read failure
 * @return       newly allocated trimmed string; caller must `free()` it
 */
char *
netdev_read(const char *ifname, const char *file, const char *def)
{
	char path[256];
	char *content;

	snprintf(path, sizeof(path), "/sys/class/net/%s/%s", ifname, file);
	content = sysfs_read_file(path);

	return content ? content : xstrdup(def ? def : "");
}

/**
 * Returns TR-181 Link properties for a network interface from sysfs.
 *
 * Output object contains `Status`, `MACAddress` (uppercase) and `MTU`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: ifname)
 * @return       Link properties object, possibly empty on bad input
 */
uc_value_t *
uc_ubbf_link_properties_get(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *ifname_val = uc_fn_arg(0);
	const char *ifname;
	uc_value_t *obj;
	char *operstate, *mac, *mtu;

	if (ucv_type(ifname_val) != UC_STRING)
		return ucv_object_new(vm);

	ifname = ucv_string_get(ifname_val);
	operstate = netdev_read(ifname, "operstate", "unknown");
	mac = netdev_read(ifname, "address", "00:00:00:00:00:00");
	mtu = netdev_read(ifname, "mtu", "0");

	str_to_upper(mac);

	obj = ucv_object_new(vm);
	ucv_object_add(obj, "Status", ucv_string_new(operstate_map(operstate)));
	ucv_object_add(obj, "MACAddress", ucv_string_new(mac));
	ucv_object_add(obj, "MTU", ucv_string_new(mtu));

	free(operstate);
	free(mac);
	free(mtu);

	return obj;
}

/**
 * Returns TR-181 Ethernet.Interface properties for a netdev from sysfs.
 *
 * Populates Enable, Status, LowerLayers, MaxBitRate, MACAddress (uppercase),
 * CurrentBitRate, CurrentDuplexMode, EEECapability and EEEEnable. Speed
 * values of `-1` or `65535` are normalised to `0`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: ifname)
 * @return       Ethernet properties object, possibly empty on bad input
 */
uc_value_t *
uc_ubbf_ethernet_properties_get(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *ifname_val = uc_fn_arg(0);
	const char *ifname;
	uc_value_t *obj;
	char *operstate, *mac, *speed, *duplex;
	const char *bit_rate, *duplex_mode;

	if (ucv_type(ifname_val) != UC_STRING)
		return ucv_object_new(vm);

	ifname = ucv_string_get(ifname_val);
	operstate = netdev_read(ifname, "operstate", "unknown");
	mac = netdev_read(ifname, "address", "00:00:00:00:00:00");
	speed = netdev_read(ifname, "speed", "-1");
	duplex = netdev_read(ifname, "duplex", "unknown");

	str_to_upper(mac);

	bit_rate = speed;
	if (strcmp(speed, "-1") == 0 || strcmp(speed, "65535") == 0)
		bit_rate = "0";

	duplex_mode = "Auto";
	if (strcmp(duplex, "full") == 0)
		duplex_mode = "Full";
	else if (strcmp(duplex, "half") == 0)
		duplex_mode = "Half";

	obj = ucv_object_new(vm);
	ucv_object_add(obj, "Enable", ucv_string_new("true"));
	ucv_object_add(obj, "Status", ucv_string_new(operstate_map(operstate)));
	ucv_object_add(obj, "LowerLayers", ucv_string_new(""));
	ucv_object_add(obj, "MaxBitRate", ucv_string_new("-1"));
	ucv_object_add(obj, "MACAddress", ucv_string_new(mac));
	ucv_object_add(obj, "CurrentBitRate", ucv_string_new(bit_rate));
	ucv_object_add(obj, "CurrentDuplexMode", ucv_string_new(duplex_mode));
	ucv_object_add(obj, "EEECapability", ucv_string_new("true"));
	ucv_object_add(obj, "EEEEnable", ucv_string_new("false"));

	free(operstate);
	free(mac);
	free(speed);
	free(duplex);

	return obj;
}

/* ---- host discovery ---------------------------------------------------- */

/**
 * Parses `/proc/net/arp` into an array of host entries.
 *
 * Skips the header line, the all-zero MAC and entries without the
 * `ATF_COM` flag. Each emitted object holds `ip`, `mac` (uppercase),
 * `device` and `active` (always true).
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       array of host objects, possibly empty
 */
uc_value_t *
uc_ubbf_arp_parse(uc_vm_t *vm, size_t nargs)
{
	/* stream line by line; sysfs_read_file() caps at 8 KiB, which
	 * silently drops hosts on larger LANs */
	char line[512];
	uc_value_t *arr;
	FILE *fp;
	bool header = true;

	arr = ucv_array_new(vm);

	fp = fopen("/proc/net/arp", "r");
	if (!fp)
		return arr;

	while (fgets(line, sizeof(line), fp)) {
		char ip[64] = "", hw[8] = "", flags_str[8] = "", mac[20] = "", mask[8] = "", dev[64] = "";
		uc_value_t *entry;
		unsigned long flags;

		if (header) {
			header = false;
			continue;
		}

		if (sscanf(line, "%63s %7s %7s %19s %7s %63s", ip, hw, flags_str, mac, mask, dev) < 6)
			continue;

		flags = strtoul(flags_str, NULL, 16);
		if (strcmp(mac, "00:00:00:00:00:00") == 0 || !(flags & 0x02))
			continue;

		str_to_upper(mac);

		entry = ucv_object_new(vm);
		ucv_object_add(entry, "ip", ucv_string_new(ip));
		ucv_object_add(entry, "mac", ucv_string_new(mac));
		ucv_object_add(entry, "device", ucv_string_new(dev));
		ucv_object_add(entry, "active", ucv_boolean_new(true));
		ucv_array_push(arr, entry);
	}

	fclose(fp);
	return arr;
}

static bool
netdev_is_bridge(const char *dev)
{
	char path[PATH_MAX];

	snprintf(path, sizeof(path), "/sys/class/net/%s/bridge", dev);

	return access(path, F_OK) == 0;
}

/**
 * Tells whether a network device is a bridge, or sits on one, such as the
 * VLAN device br-lanv0 on the bridge br-lan.
 *
 * @param dev  device name
 * @return     true when the bridge FDB covers the device
 */
static bool
netdev_on_bridge(const char *dev)
{
	char path[PATH_MAX];
	struct dirent *e;
	bool found = false;
	DIR *d;

	if (netdev_is_bridge(dev))
		return true;

	snprintf(path, sizeof(path), "/sys/class/net/%s", dev);
	d = opendir(path);
	if (!d)
		return false;

	while (!found && (e = readdir(d)) != NULL)
		if (!strncmp(e->d_name, "lower_", 6))
			found = netdev_is_bridge(e->d_name + 6);

	closedir(d);

	return found;
}

/**
 * Tells whether a merged host is on the LAN now: the bridge FDB knows its
 * MAC, or the ARP table has it on a device that is not on a bridge, where
 * no FDB exists to ask.
 *
 * @param fdb   FDB object, MAC to port
 * @param mac   uppercase MAC
 * @param host  merged host object
 * @return      true when the host is present
 */
static bool
host_present(uc_value_t *fdb, const char *mac, uc_value_t *host)
{
	uc_value_t *device = ucv_object_get(host, "device", NULL);
	const char *dev = ucv_string_get(device);

	if (ucv_type(fdb) == UC_OBJECT && ucv_object_get(fdb, mac, NULL))
		return true;

	if (!dev || !*dev || strchr(dev, '/'))
		return false;

	return !netdev_on_bridge(dev);
}

/**
 * Merges ARP, DHCP lease, IPv6 neighbour and FDB data into Hosts entries.
 *
 * Builds an intermediate per-MAC dictionary from ARP, DHCP and IPv6
 * sources, then keeps only the hosts that host_present() finds on the
 * LAN, so that stale entries do not appear in TR-181 Hosts.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (4 expected: arp array, leases obj,
 *               ipv6 neigh obj, fdb obj)
 * @return       array of host objects suitable for the Hosts table
 */
uc_value_t *
uc_ubbf_hosts_merge(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *arp = uc_fn_arg(0);
	uc_value_t *leases = uc_fn_arg(1);
	uc_value_t *ipv6 = uc_fn_arg(2);
	uc_value_t *fdb = uc_fn_arg(3);
	uc_value_t *hosts_by_mac, *result;

	hosts_by_mac = ucv_object_new(vm);

	if (ucv_type(arp) == UC_ARRAY) {
		for (size_t i = 0; i < ucv_array_length(arp); i++) {
			uc_value_t *entry = ucv_array_get(arp, i);
			uc_value_t *mac_val = ucv_object_get(entry, "mac", NULL);
			uc_value_t *ip_val = ucv_object_get(entry, "ip", NULL);
			const char *mac, *ip;
			uc_value_t *host;

			if (!mac_val || !ip_val) continue;
			mac = ucv_string_get(mac_val);
			ip = ucv_string_get(ip_val);

			host = ucv_object_get(hosts_by_mac, mac, NULL);
			if (!host) {
				uc_value_t *v6 = (ucv_type(ipv6) == UC_OBJECT)
					? ucv_object_get(ipv6, mac, NULL) : NULL;
				uc_value_t *lease = (ucv_type(leases) == UC_OBJECT)
					? ucv_object_get(leases, mac, NULL) : NULL;
				uc_value_t *hostname = lease
					? ucv_object_get(lease, "hostname", NULL) : NULL;

				host = ucv_object_new(vm);
				ucv_object_add(host, "mac", ucv_string_new(mac));
				ucv_object_add(host, "ipv4_addresses", ucv_array_new(vm));
				ucv_object_add(host, "ipv6_addresses",
					       v6 ? ucv_get(v6) : ucv_array_new(vm));
				ucv_object_add(host, "hostname",
					       hostname ? ucv_get(hostname) : ucv_string_new(""));
				ucv_object_add(host, "device",
					       ucv_get(ucv_object_get(entry, "device", NULL)));
				ucv_object_add(host, "active", ucv_boolean_new(true));
				ucv_object_add(host, "address_source",
					       ucv_string_new(lease ? "DHCP" : "Static"));
				ucv_object_add(hosts_by_mac, mac, host);
			}

			uc_value_t *addrs = ucv_object_get(host, "ipv4_addresses", NULL);
			bool dup = false;
			for (size_t j = 0; j < ucv_array_length(addrs); j++) {
				uc_value_t *av = ucv_array_get(addrs, j);
				if (ucv_type(av) == UC_STRING && strcmp(ucv_string_get(av), ip) == 0) {
					dup = true;
					break;
				}
			}
			if (!dup)
				ucv_array_push(addrs, ucv_string_new(ip));
		}
	}

	if (ucv_type(leases) == UC_OBJECT) {
		ucv_object_foreach(leases, mac, lease) {
			if (ucv_object_get(hosts_by_mac, mac, NULL))
				continue;

			uc_value_t *v6 = (ucv_type(ipv6) == UC_OBJECT)
				? ucv_object_get(ipv6, mac, NULL) : NULL;
			uc_value_t *ip_val = ucv_object_get(lease, "ip", NULL);
			uc_value_t *hostname = ucv_object_get(lease, "hostname", NULL);

			uc_value_t *host = ucv_object_new(vm);
			ucv_object_add(host, "mac", ucv_string_new(mac));

			uc_value_t *addrs = ucv_array_new(vm);
			if (ip_val) ucv_array_push(addrs, ucv_get(ip_val));
			ucv_object_add(host, "ipv4_addresses", addrs);
			ucv_object_add(host, "ipv6_addresses",
				       v6 ? ucv_get(v6) : ucv_array_new(vm));
			ucv_object_add(host, "hostname",
				       hostname ? ucv_get(hostname) : ucv_string_new(""));
			ucv_object_add(host, "device", ucv_string_new(""));
			ucv_object_add(host, "active", ucv_boolean_new(false));
			ucv_object_add(host, "address_source", ucv_string_new("DHCP"));
			ucv_object_add(hosts_by_mac, mac, host);
		}
	}

	/* A host with IPv6 only (SLAAC or DHCPv6, no IPv4) is in neither the
	 * ARP table nor the DHCPv4 leases. */
	if (ucv_type(ipv6) == UC_OBJECT) {
		ucv_object_foreach(ipv6, mac, v6) {
			if (ucv_object_get(hosts_by_mac, mac, NULL))
				continue;

			uc_value_t *host = ucv_object_new(vm);
			ucv_object_add(host, "mac", ucv_string_new(mac));
			ucv_object_add(host, "ipv4_addresses", ucv_array_new(vm));
			ucv_object_add(host, "ipv6_addresses", ucv_get(v6));
			ucv_object_add(host, "hostname", ucv_string_new(""));
			ucv_object_add(host, "device", ucv_string_new(""));
			ucv_object_add(host, "active", ucv_boolean_new(false));
			ucv_object_add(host, "address_source", ucv_string_new("None"));
			ucv_object_add(hosts_by_mac, mac, host);
		}
	}

	result = ucv_array_new(vm);

	ucv_object_foreach(hosts_by_mac, mac, host) {
		if (!host_present(fdb, mac, host))
			continue;

		ucv_object_add(host, "active", ucv_boolean_new(true));
		ucv_array_push(result, ucv_get(host));
	}

	ucv_put(hosts_by_mac);
	return result;
}

/**
 * Locates the TR-181 IP.Interface that matches a host's IP address.
 *
 * For each netifd interface, compares the host IP against every assigned
 * address using the matching prefix length (IPv4 or IPv6) until a match
 * is found, then returns `{ path, upstream }` for the corresponding
 * `Device.IP.Interface.{i}` entry. When no match exists, returns
 * `{ path: "", upstream: false }`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (3 expected: data model root, host IP,
 *               netifd interfaces array)
 * @return       result object describing the matching interface
 */
uc_value_t *
uc_ubbf_layer3_interface_find(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *config = uc_fn_arg(0);
	uc_value_t *ip_val = uc_fn_arg(1);
	uc_value_t *netifd_ifaces = uc_fn_arg(2);
	const char *ip_addr;
	bool is_v6;
	uc_value_t *empty;

	empty = ucv_object_new(vm);
	ucv_object_add(empty, "path", ucv_string_new(""));
	ucv_object_add(empty, "upstream", ucv_boolean_new(false));

	if (ucv_type(ip_val) != UC_STRING || ucv_type(netifd_ifaces) != UC_ARRAY)
		return empty;

	ip_addr = ucv_string_get(ip_val);
	if (!ip_addr || !*ip_addr)
		return empty;

	is_v6 = (strchr(ip_addr, ':') != NULL);

	uc_value_t *ip_interfaces = navigate_by_path(vm, config, "Device.IP.Interface");
	if (ucv_type(ip_interfaces) != UC_OBJECT)
		return empty;

	for (size_t ni = 0; ni < ucv_array_length(netifd_ifaces); ni++) {
		uc_value_t *netifd = ucv_array_get(netifd_ifaces, ni);
		uc_value_t *name_val = ucv_object_get(netifd, "name", NULL);
		uc_value_t *addr_list;

		if (!name_val) continue;

		addr_list = ucv_object_get(netifd, is_v6 ? "ipv6_addresses" : "addresses", NULL);
		if (ucv_type(addr_list) != UC_ARRAY) continue;

		for (size_t ai = 0; ai < ucv_array_length(addr_list); ai++) {
			uc_value_t *addr = ucv_array_get(addr_list, ai);
			uc_value_t *aip = ucv_object_get(addr, "ip", NULL);
			uc_value_t *amask = ucv_object_get(addr, "mask", NULL);
			bool match = false;

			if (!aip || !amask) continue;

			if (ucv_type(aip) != UC_STRING || ucv_type(amask) != UC_INTEGER)
				continue;

			match = ip_prefix_match(ip_addr, ucv_string_get(aip), (int)ucv_int64_get(amask));

			if (!match) continue;

			const char *netifd_name = ucv_string_get(name_val);

			ucv_object_foreach(ip_interfaces, inst_key, iface) {
				uc_value_t *iface_name = ucv_object_get(iface, "Name", NULL);

				if (!iface_name || ucv_type(iface_name) != UC_STRING)
					continue;
				if (strcmp(ucv_string_get(iface_name), netifd_name) != 0)
					continue;

				uc_value_t *upstream = ucv_object_get(iface, "Upstream", NULL);
				char *path;

				xasprintf(&path, "Device.IP.Interface.%s", inst_key);

				ucv_put(empty);
				uc_value_t *result = ucv_object_new(vm);
				ucv_object_add(result, "path", ucv_string_new(path));
				free(path);
				ucv_object_add(result, "upstream",
					       ucv_boolean_new(value_to_bool(upstream)));
				return result;
			}
		}
	}

	return empty;
}

/**
 * Picks a representative IP address from a Host entry.
 *
 * Prefers the first IPv4 address, falling back to the first IPv6 address.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: host object)
 * @return       string IP, or an empty string when none is available
 */
uc_value_t *
uc_ubbf_host_primary_ip(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *host = uc_fn_arg(0);
	uc_value_t *addrs;

	if (ucv_type(host) != UC_OBJECT)
		return ucv_string_new("");

	addrs = ucv_object_get(host, "ipv4_addresses", NULL);
	if (ucv_type(addrs) == UC_ARRAY && ucv_array_length(addrs) > 0)
		return ucv_get(ucv_array_get(addrs, 0));

	addrs = ucv_object_get(host, "ipv6_addresses", NULL);
	if (ucv_type(addrs) == UC_ARRAY && ucv_array_length(addrs) > 0)
		return ucv_get(ucv_array_get(addrs, 0));

	return ucv_string_new("");
}
