/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * TR-181 Stats objects from udevstats replies, and the netdevs behind an
 * IP.Interface. utils/ifstats.uc makes the ubus calls.
 */

#include "ubbf.h"
#include "bindings.h"

#include <inttypes.h>

enum { DIR_RX, DIR_TX, DIRS };
enum { CNT_BYTES, CNT_PACKETS, CNT_UNICAST, CNT_MULTICAST, CNT_BROADCAST, CNTS };

static const char *const counter_keys[CNTS] = { "bytes", "packets", "unicast", "multicast", "broadcast" };

/* A sum that stays an integer until a double joins it, as ucode `+=`. */
struct total {
	bool is_double;
	int64_t i;
	double d;
};

static void
total_add(struct total *t, uc_value_t *val)
{
	if (!val)
		return;

	if (ucv_type(val) == UC_DOUBLE) {
		t->d = (t->is_double ? t->d : (double)t->i) + ucv_double_get(val);
		t->is_double = true;
	} else if (t->is_double) {
		t->d += ucv_to_double(val);
	} else {
		t->i += ucv_to_integer(val);
	}
}

static uc_value_t *
total_string(const struct total *t)
{
	char buf[24];

	snprintf(buf, sizeof(buf), "%" PRId64, t->is_double ? (int64_t)t->d : t->i);

	return ucv_string_new(buf);
}

static void
reply_accumulate(struct total totals[DIRS][CNTS], uc_value_t *reply)
{
	static const char *const dirs[DIRS] = { "rx", "tx" };
	uc_value_t *dir;

	if (!ucv_is_truish(reply))
		return;

	for (int d = 0; d < DIRS; d++) {
		dir = ucv_object_get(reply, dirs[d], NULL);
		for (int c = 0; c < CNTS; c++)
			total_add(&totals[d][c], ucv_object_get(dir, counter_keys[c], NULL));
	}
}

/**
 * ucode: `ifstats_build(replies, full)`, the Stats object of the sum of
 * udevstats `get` replies. Every Stats object declares the basic counters;
 * the interface tables add the packet types. Errors and discards are not
 * in udevstats and stay at '0'.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: array of replies, null
 *               for a failed call; true for the packet types)
 * @return       Stats object of decimal strings
 */
uc_value_t *
uc_ubbf_ifstats_build(uc_vm_t *vm, size_t nargs)
{
	static const struct {
		const char *name;
		int dir;
		int cnt;
	} basic[] = {
		{ "BytesSent", DIR_TX, CNT_BYTES }, { "BytesReceived", DIR_RX, CNT_BYTES },
		{ "PacketsSent", DIR_TX, CNT_PACKETS }, { "PacketsReceived", DIR_RX, CNT_PACKETS },
	}, types[] = {
		{ "UnicastPacketsSent", DIR_TX, CNT_UNICAST }, { "UnicastPacketsReceived", DIR_RX, CNT_UNICAST },
		{ "MulticastPacketsSent", DIR_TX, CNT_MULTICAST }, { "MulticastPacketsReceived", DIR_RX, CNT_MULTICAST },
		{ "BroadcastPacketsSent", DIR_TX, CNT_BROADCAST }, { "BroadcastPacketsReceived", DIR_RX, CNT_BROADCAST },
	};
	static const char *const zeros[] = {
		"ErrorsSent", "ErrorsReceived", "DiscardPacketsSent", "DiscardPacketsReceived",
	};
	uc_value_t *replies = uc_fn_arg(0), *stats = ucv_object_new(vm);
	struct total totals[DIRS][CNTS] = { 0 };

	for (size_t i = 0; i < ucv_array_length(replies); i++)
		reply_accumulate(totals, ucv_array_get(replies, i));

	for (size_t i = 0; i < ARRAY_SIZE(basic); i++)
		ucv_object_add(stats, basic[i].name, total_string(&totals[basic[i].dir][basic[i].cnt]));

	for (size_t i = 0; i < ARRAY_SIZE(zeros); i++)
		ucv_object_add(stats, zeros[i], ucv_string_new("0"));

	if (!ucv_is_truish(uc_fn_arg(1)))
		return stats;

	for (size_t i = 0; i < ARRAY_SIZE(types); i++)
		ucv_object_add(stats, types[i].name, total_string(&totals[types[i].dir][types[i].cnt]));

	ucv_object_add(stats, "UnknownProtoPacketsReceived", ucv_string_new("0"));

	return stats;
}

static void
member_add(uc_vm_t *vm, uc_value_t *members, uc_value_t *root, uc_value_t *ref)
{
	uc_value_t *dev = lower_layer_name_get(vm, root, ucv_string_get(ref));

	if (!ucv_is_truish(dev))
		return;

	for (size_t i = 0; i < ucv_array_length(members); i++)
		if (loose_equal(ucv_array_get(members, i), dev) &&
		    ucv_type(ucv_array_get(members, i)) == ucv_type(dev))
			return;

	ucv_array_push(members, ucv_get(dev));
}

/* The bridge number of a `Device.Bridging.Bridge.{n}.Port.{m}` reference,
 * or NULL for any other reference. */
static char *
bridge_port_ref(const char *ref)
{
	static const char prefix[] = "Device.Bridging.Bridge.";
	const char *n = ref + strlen(prefix), *p;
	size_t n_len = strspn(n, "0123456789");

	if (strncmp(ref, prefix, strlen(prefix)) || !n_len || strncmp(n + n_len, ".Port.", 6))
		return NULL;

	p = n + n_len + 6;
	p += strspn(p, "0123456789");
	if (p == n + n_len + 6 || (*p && strcmp(p, ".")))
		return NULL;

	return strndup(n, n_len);
}

static void
bridge_members_add(uc_vm_t *vm, uc_value_t *members, uc_value_t *root, const char *bridge)
{
	uc_value_t *ports, *refs;
	char *path;

	xasprintf(&path, "Device.Bridging.Bridge.%s.Port", bridge);
	ports = navigate_by_path(vm, root, path);
	free(path);

	ucv_object_foreach(ports, key, port) {
		if (!key_is_instance(key) || ucv_type(port) != UC_OBJECT ||
		    !value_to_bool(ucv_object_get(port, "Enable", NULL)) ||
		    value_to_bool(ucv_object_get(port, "ManagementPort", NULL)))
			continue;

		refs = ucv_object_get(port, "LowerLayers", NULL);
		refs = csv_list_new(vm, (ucv_type(refs) == UC_STRING) ? ucv_string_get(refs) : "", "-1");

		for (size_t i = 0; i < ucv_array_length(refs); i++)
			member_add(vm, members, root, ucv_array_get(refs, i));

		ucv_put(refs);
	}
}

/**
 * ucode: `ip_interface_members(root, iface)`, the netdevs behind the
 * LowerLayers of an IP.Interface. An entry that names a bridge port
 * expands into the enabled ports of the bridge that are no management
 * port; every other entry gives its own netdev.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: root, IP.Interface row)
 * @return       array of netdev names without repeats
 */
uc_value_t *
uc_ubbf_ip_interface_members(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *root = uc_fn_arg(0), *layers = ucv_object_get(uc_fn_arg(1), "LowerLayers", NULL);
	uc_value_t *members = ucv_array_new(vm), *refs, *ref;
	char *bridge;

	if (!ucv_is_truish(root) || ucv_type(layers) != UC_STRING || !ucv_is_truish(layers))
		return members;

	refs = csv_list_new(vm, ucv_string_get(layers), "-1");

	for (size_t i = 0; i < ucv_array_length(refs); i++) {
		ref = ucv_array_get(refs, i);
		bridge = bridge_port_ref(ucv_string_get(ref));

		if (bridge)
			bridge_members_add(vm, members, root, bridge);
		else
			member_add(vm, members, root, ref);

		free(bridge);
	}

	ucv_put(refs);

	return members;
}
