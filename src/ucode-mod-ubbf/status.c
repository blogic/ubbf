/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * The TR-181 Status of an interface from its Enable, its LowerLayers and
 * the kernel operstate of its netdev.
 */

#include "ubbf.h"
#include "bindings.h"

enum lower_state {
	LOWER_UNKNOWN,
	LOWER_UP,
	LOWER_DOWN,
};

static const char *const status_up[] = { "Up", "Enabled" };
static const char *const status_down[] = {
	"Down", "Disabled", "LowerLayerDown", "NotPresent", "Error", "Dormant",
};

static bool
string_in(const char *s, const char *const *list, size_t cnt)
{
	for (size_t i = 0; i < cnt; i++)
		if (!strcmp(s, list[i]))
			return true;

	return false;
}

/**
 * The netdev of a lower layer. A WiFi.SSID row does not hold its kernel
 * ifname, so ssid_fn resolves the instance; any other row names its
 * netdev in Name. The result is a new reference, or NULL.
 */
static uc_value_t *
lower_netdev(uc_vm_t *vm, uc_value_t *obj, const char *ref, uc_value_t *ssid_fn)
{
	int64_t inst = tr181_ref_instance(ref, "Device.WiFi.SSID");
	uc_value_t *n, *rv;

	if (inst < 0)
		return ucv_get(ucv_object_get(obj, "Name", NULL));

	n = ucv_int64_new(inst);
	rv = callback_invoke(vm, ssid_fn, 1, n);
	ucv_put(n);

	return rv;
}

/**
 * Whether a lower layer is up: its own Status where that is definite,
 * else the operstate of its netdev. An exception of ssid_fn stays raised.
 */
static enum lower_state
lower_is_up(uc_vm_t *vm, uc_value_t *obj, const char *ref, uc_value_t *ssid_fn)
{
	uc_value_t *st = ucv_object_get(obj, "Status", NULL);
	enum lower_state state = LOWER_UNKNOWN;
	uc_value_t *ifname;
	char *op;

	if (ucv_type(st) == UC_STRING) {
		if (string_in(ucv_string_get(st), status_up, ARRAY_SIZE(status_up)))
			return LOWER_UP;
		if (string_in(ucv_string_get(st), status_down, ARRAY_SIZE(status_down)))
			return LOWER_DOWN;
	}

	ifname = lower_netdev(vm, obj, ref, ssid_fn);
	if (ucv_type(ifname) != UC_STRING || !*ucv_string_get(ifname)) {
		ucv_put(ifname);
		return LOWER_UNKNOWN;
	}

	op = netdev_read(ucv_string_get(ifname), "operstate", "unknown");
	if (!strcmp(op, "up"))
		state = LOWER_UP;
	else if (!strcmp(op, "down") || !strcmp(op, "lowerlayerdown") || !strcmp(op, "notpresent"))
		state = LOWER_DOWN;

	free(op);
	ucv_put(ifname);

	return state;
}

/**
 * Derives a Status of the 7-value ifOperStatus enum, for
 * Device.Ethernet.Interface, Link and VLANTermination and
 * Device.Bridging.Bridge.{i}.Port. With LowerLayers, the interface is Up
 * when a lower layer is up, Unknown when one cannot be judged, else
 * LowerLayerDown; references that do not resolve do not count.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2-5: Enable, netdev name, optional
 *               LowerLayers, the root config to resolve them, and the
 *               function that gives the netdev of a WiFi.SSID instance)
 * @return       Up, Down, Unknown, Dormant, NotPresent, LowerLayerDown or
 *               Error
 */
uc_value_t *
uc_ubbf_ifop_status_derive(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *ifname = uc_fn_arg(1);
	uc_value_t *layers = uc_fn_arg(2);
	uc_value_t *root = uc_fn_arg(3);
	uc_value_t *refs, *ref, *obj, *rv = NULL;
	bool resolved = false, unknown = false;
	enum lower_state state;
	char *op;

	if (!value_to_bool(uc_fn_arg(0)))
		return ucv_string_new("Down");

	if (ucv_type(layers) == UC_STRING && *ucv_string_get(layers) && ucv_is_truish(root)) {
		refs = csv_list_new(vm, ucv_string_get(layers), "-1");

		for (size_t i = 0; !rv && i < ucv_array_length(refs); i++) {
			ref = ucv_array_get(refs, i);
			obj = navigate_by_path(vm, root, ucv_string_get(ref));
			if (!ucv_is_truish(obj))
				continue;

			resolved = true;
			state = lower_is_up(vm, obj, ucv_string_get(ref), uc_fn_arg(4));
			if (vm->exception.type != EXCEPTION_NONE) {
				ucv_put(refs);
				return NULL;
			}

			if (state == LOWER_UP)
				rv = ucv_string_new("Up");
			else if (state == LOWER_UNKNOWN)
				unknown = true;
		}

		ucv_put(refs);

		if (rv)
			return rv;
		if (resolved)
			return ucv_string_new(unknown ? "Unknown" : "LowerLayerDown");
	}

	if (ucv_type(ifname) != UC_STRING || !*ucv_string_get(ifname))
		return ucv_string_new("Down");

	op = netdev_read(ucv_string_get(ifname), "operstate", "unknown");
	rv = ucv_string_new(operstate_map(op));
	free(op);

	return rv;
}

/**
 * Derives a Status of the 3-value enum of Device.Bridging.Bridge.{i}.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: Enable, bridge netdev)
 * @return       Disabled, Enabled or Error
 */
uc_value_t *
uc_ubbf_bridge_status_derive(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *ifname = uc_fn_arg(1);
	const char *status;
	char *op;

	if (!value_to_bool(uc_fn_arg(0)))
		return ucv_string_new("Disabled");

	if (ucv_type(ifname) != UC_STRING || !*ucv_string_get(ifname))
		return ucv_string_new("Error");

	op = netdev_read(ucv_string_get(ifname), "operstate", "unknown");
	status = !strcmp(op, "up") ? "Enabled" : !strcmp(op, "down") ? "Disabled" : "Error";
	free(op);

	return ucv_string_new(status);
}
