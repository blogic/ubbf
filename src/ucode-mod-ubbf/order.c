/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * The TR-181 data type Order: an entry created without a value goes last,
 * a value that an existing entry holds moves that entry and all lower ones
 * down by one, and a deletion compacts the values.
 */

#include "ubbf.h"
#include "bindings.h"
#include <inttypes.h>

/* The TR-181 2.21 tables whose Order parameter has the data type Order. */
static const char *const order_tables[] = {
	"Device.Bridging.Filter",
	"Device.DHCPv4.Client.{i}.ReqOption",
	"Device.DHCPv4.Relay.Forwarding",
	"Device.DHCPv4.Server.Pool",
	"Device.DHCPv6.Server.Pool",
	"Device.Firewall.Chain.{i}.Rule",
	"Device.Firewall.Level",
	"Device.GRE.Filter",
	"Device.IPsec.Filter",
	"Device.L2TPv3.Filter",
	"Device.MQTT.BrokerSecurity.ACL",
	"Device.QoS.Classification",
	"Device.UserInterface.HTTPAccess",
	"Device.VXLAN.Filter",
};

struct order_row {
	const char *key;
	int64_t n;
	int64_t order;
};

static int64_t
order_of(uc_value_t *row)
{
	uc_value_t *val = ucv_object_get(row, "Order", NULL);
	const char *s;
	char *end;
	int64_t n;

	if (ucv_type(val) == UC_INTEGER) {
		n = ucv_int64_get(val);
		return n >= 1 ? n : 0;
	}

	if (ucv_type(val) != UC_STRING)
		return 0;

	s = ucv_string_get(val);
	if (!*s)
		return 0;

	n = strtoll(s, &end, 10);
	return (*end == '\0' && n >= 1) ? n : 0;
}

static int
by_order(const void *a, const void *b)
{
	const struct order_row *ra = a, *rb = b;

	if (ra->order != rb->order)
		return ra->order < rb->order ? -1 : 1;

	return (ra->n > rb->n) - (ra->n < rb->n);
}

static int
by_instance(const void *a, const void *b)
{
	const struct order_row *ra = a, *rb = b;

	return (ra->n > rb->n) - (ra->n < rb->n);
}

/**
 * The instance rows of a table in instance order, with their Order values
 * (0 for none). The keys point into `rows`.
 */
static struct order_row *
order_rows(uc_value_t *rows, size_t *cnt)
{
	struct order_row *list = xalloc(sizeof(*list) * (ucv_object_length(rows) + 1));
	size_t n = 0;

	ucv_object_foreach(rows, key, row) {
		if (!key_is_instance(key))
			continue;

		list[n].key = key;
		list[n].n = strtoll(key, NULL, 10);
		list[n].order = order_of(row);
		n++;
	}

	qsort(list, n, sizeof(*list), by_instance);
	*cnt = n;

	return list;
}

/**
 * Calls fn for the rows object of each Order table in a config tree.
 */
static void
order_tables_foreach(uc_vm_t *vm, uc_value_t *data,
		     void (*fn)(uc_vm_t *, const char *, uc_value_t *, void *),
		     void *ctx)
{
	for (size_t i = 0; i < ARRAY_SIZE(order_tables); i++) {
		char *pattern = xstrdup(order_tables[i]);
		char *name = strrchr(pattern, '.');
		uc_value_t *parts, *parents, *rows;
		char *path;

		*name++ = '\0';

		parts = path_parts_new(vm, pattern);
		parents = ucv_array_new(vm);
		instances_collect(parents, parts, data, 0, "", vm);

		for (size_t j = 0; j < ucv_array_length(parents); j++) {
			uc_value_t *parent = ucv_array_get(parents, j);

			xasprintf(&path, "%s.%s", ucv_string_get(parent), name);
			rows = navigate_by_path(vm, data, path);
			if (ucv_type(rows) == UC_OBJECT)
				fn(vm, path, rows, ctx);
			free(path);
		}

		ucv_put(parents);
		ucv_put(parts);
		free(pattern);
	}
}

static void
order_snapshot_table(uc_vm_t *vm, const char *path, uc_value_t *rows, void *ctx)
{
	uc_value_t *table = ucv_object_new(vm);
	struct order_row *list;
	size_t cnt;

	list = order_rows(rows, &cnt);
	for (size_t i = 0; i < cnt; i++)
		ucv_object_add(table, list[i].key,
			       list[i].order ? ucv_int64_new(list[i].order) : NULL);
	free(list);

	ucv_object_add(ctx, path, table);
}

/**
 * The Order values of a config tree, to compare a later tree against.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: config tree)
 * @return       table path to `{ instance: Order }`, null for a row
 *               without a value
 */
uc_value_t *
uc_ubbf_order_snapshot(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *snap = ucv_object_new(vm);

	order_tables_foreach(vm, uc_fn_arg(0), order_snapshot_table, snap);

	return snap;
}

/**
 * Order values for a table whose earlier values are unknown: duplicates
 * move down in instance order, and rows without a value go last. The
 * result replaces the order of each row.
 */
static void
order_loaded(struct order_row *list, size_t cnt)
{
	int64_t last = 0;
	size_t set = 0;

	for (size_t i = 0; i < cnt; i++) {
		if (!list[i].order)
			continue;

		struct order_row tmp = list[set];
		list[set++] = list[i];
		list[i] = tmp;
	}

	qsort(list, set, sizeof(*list), by_order);
	qsort(list + set, cnt - set, sizeof(*list), by_instance);

	for (size_t i = 0; i < set; i++)
		list[i].order = last = (list[i].order > last + 1) ? list[i].order : last + 1;

	for (size_t i = set; i < cnt; i++)
		list[i].order = ++last;
}

static bool
before_get(uc_value_t *before, const char *key, int64_t *order)
{
	bool found;
	uc_value_t *val = ucv_object_get(before, key, &found);

	*order = (ucv_type(val) == UC_INTEGER) ? ucv_int64_get(val) : 0;

	return found;
}

static bool
rows_deleted(uc_value_t *before, uc_value_t *rows)
{
	bool found;

	ucv_object_foreach(before, key, val) {
		(void)val;
		ucv_object_get(rows, key, &found);
		if (!found)
			return true;
	}

	return false;
}

/**
 * Order values for a table after a change against its earlier values: a
 * row keeps the value it had before, a written value takes its place and
 * moves the entries from that value on down by one, and a deletion
 * compacts the values. The rows with a value end up in list[0..n), n is
 * returned; the caller places the rows without a value after them.
 */
static size_t
order_changed(struct order_row *list, size_t cnt, uc_value_t *before,
	      uc_value_t *rows)
{
	size_t nbase = 0, nwritten = 0;
	struct order_row *written;
	int64_t prev;
	bool taken;

	written = xalloc(sizeof(*written) * (cnt + 1));

	for (size_t i = 0; i < cnt; i++) {
		if (!list[i].order)
			continue;

		if (before_get(before, list[i].key, &prev) && prev == list[i].order)
			list[nbase++] = list[i];
		else
			written[nwritten++] = list[i];
	}

	qsort(written, nwritten, sizeof(*written), by_order);

	for (size_t w = 0; w < nwritten; w++) {
		taken = false;
		for (size_t i = 0; i < nbase; i++)
			if (list[i].order == written[w].order)
				taken = true;

		for (size_t i = 0; taken && i < nbase; i++)
			if (list[i].order >= written[w].order)
				list[i].order++;

		list[nbase++] = written[w];
	}

	free(written);

	if (rows_deleted(before, rows)) {
		qsort(list, nbase, sizeof(*list), by_order);
		for (size_t i = 0; i < nbase; i++)
			list[i].order = i + 1;
	}

	return nbase;
}

struct order_compute {
	uc_value_t *before;
	bool changed;
};

static bool
order_value_equal(uc_value_t *val, int64_t order)
{
	char buf[24];

	if (ucv_type(val) == UC_INTEGER)
		return ucv_int64_get(val) == order;

	if (ucv_type(val) != UC_STRING)
		return false;

	snprintf(buf, sizeof(buf), "%" PRId64, order);

	return !strcmp(ucv_string_get(val), buf);
}

static void
order_compute_table(uc_vm_t *vm, const char *path, uc_value_t *rows, void *data)
{
	struct order_compute *ctx = data;
	uc_value_t *before = ucv_object_get(ctx->before, path, NULL);
	struct order_row *list, *unset;
	size_t cnt, nset, nunset = 0;
	int64_t last = 0;
	char buf[24];

	list = order_rows(rows, &cnt);

	if (ucv_type(before) != UC_OBJECT) {
		order_loaded(list, cnt);
	} else {
		unset = xalloc(sizeof(*unset) * (cnt + 1));
		for (size_t i = 0; i < cnt; i++)
			if (!list[i].order)
				unset[nunset++] = list[i];

		nset = order_changed(list, cnt, before, rows);

		for (size_t i = 0; i < nset; i++)
			if (list[i].order > last)
				last = list[i].order;

		for (size_t i = 0; i < nunset; i++) {
			list[nset + i] = unset[i];
			list[nset + i].order = ++last;
		}

		free(unset);
	}

	for (size_t i = 0; i < cnt; i++) {
		uc_value_t *row = ucv_object_get(rows, list[i].key, NULL);

		if (ucv_type(row) != UC_OBJECT ||
		    order_value_equal(ucv_object_get(row, "Order", NULL), list[i].order))
			continue;

		snprintf(buf, sizeof(buf), "%" PRId64, list[i].order);
		ucv_object_add(row, "Order", ucv_string_new(buf));
		ctx->changed = true;
	}

	free(list);
}

/**
 * Applies the data type Order to every Order table of a config tree.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: config tree, changed in
 *               place; order_snapshot() of the tree before the change, or
 *               null when it is not known)
 * @return       true when a value changed
 */
uc_value_t *
uc_ubbf_orders_compute(uc_vm_t *vm, size_t nargs)
{
	struct order_compute ctx = { .before = uc_fn_arg(1) };

	order_tables_foreach(vm, uc_fn_arg(0), order_compute_table, &ctx);

	return ucv_boolean_new(ctx.changed);
}
