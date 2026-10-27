/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * The write gate serialises writes against a writer that holds the config
 * across several events, such as a USP transaction that spans several
 * calls from obuspa while the event loop runs between them.
 */

#include "ubbf.h"
#include "bindings.h"

#define GATE_TYPE	"ubbf.write_gate"

enum {
	GATE_SLOT_BUSY,
	GATE_SLOT_SCHEDULE,
	GATE_SLOT_ON_ERROR,
	GATE_SLOT_QUEUE,
	GATE_SLOT_MAX
};

typedef struct {
	bool draining;
	bool scheduled;
} write_gate_t;

/**
 * Creates a gate.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (3 expected: `busy()`, true while the
 *               writer holds the config; `schedule(gate)`, which must call
 *               `gate.drain()` after the current event; `on_error(label, e)`,
 *               called when a queued write or its reply throws)
 * @return       the gate
 */
uc_value_t *
uc_ubbf_write_gate_create(uc_vm_t *vm, size_t nargs)
{
	write_gate_t *gate;
	uc_value_t *res;

	res = ucv_resource_create_ex(vm, GATE_TYPE, (void **)&gate,
				     GATE_SLOT_MAX, sizeof(*gate));

	ucv_resource_value_set(res, GATE_SLOT_BUSY, ucv_get(uc_fn_arg(0)));
	ucv_resource_value_set(res, GATE_SLOT_SCHEDULE, ucv_get(uc_fn_arg(1)));
	ucv_resource_value_set(res, GATE_SLOT_ON_ERROR, ucv_get(uc_fn_arg(2)));
	ucv_resource_value_set(res, GATE_SLOT_QUEUE, ucv_array_new(vm));

	return res;
}

/**
 * Asks `busy()`. An exception stays raised and *busy is true, so the
 * caller does not run a write.
 */
static bool
gate_busy(uc_vm_t *vm, uc_value_t *res, bool *busy)
{
	uc_value_t *rv = callback_invoke(vm, ucv_resource_value_get(res, GATE_SLOT_BUSY), 0);

	*busy = ucv_is_truish(rv);
	ucv_put(rv);

	if (vm->exception.type != EXCEPTION_NONE) {
		*busy = true;
		return false;
	}

	return true;
}

static bool
gate_release(uc_vm_t *vm, uc_value_t *res, write_gate_t *gate)
{
	uc_value_t *queue = ucv_resource_value_get(res, GATE_SLOT_QUEUE);
	bool busy;

	if (gate->scheduled)
		return true;

	if (!gate_busy(vm, res, &busy))
		return false;

	if (busy || !ucv_array_length(queue))
		return true;

	gate->scheduled = true;
	ucv_put(callback_invoke(vm, ucv_resource_value_get(res, GATE_SLOT_SCHEDULE), 1, res));

	return vm->exception.type == EXCEPTION_NONE;
}

/**
 * Runs a write now, or queues it while the gate is busy.
 *
 * A write also queues while earlier writes wait, so writes run in the
 * order they arrive. A write made by a queued write that runs is part of
 * it and runs at once.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: `job()`, which does the
 *               write and returns its result object; `done(result)`, called
 *               with the result of a queued write)
 * @return       the result, or null when the write is queued
 */
static uc_value_t *
uc_write_gate_write(uc_vm_t *vm, size_t nargs)
{
	write_gate_t *gate = uc_fn_thisval(GATE_TYPE);
	uc_value_t *res = _uc_fn_this_res(vm);
	uc_value_t *job = uc_fn_arg(0);
	uc_value_t *queue, *entry;
	bool busy;

	if (!gate)
		return NULL;

	queue = ucv_resource_value_get(res, GATE_SLOT_QUEUE);

	if (gate->draining)
		return callback_invoke(vm, job, 0);

	if (!gate_busy(vm, res, &busy))
		return NULL;

	if (!busy && !ucv_array_length(queue))
		return callback_invoke(vm, job, 0);

	entry = ucv_array_new(vm);
	ucv_array_push(entry, ucv_get(job));
	ucv_array_push(entry, ucv_get(uc_fn_arg(1)));
	ucv_array_push(queue, entry);

	gate_release(vm, res, gate);

	return NULL;
}

/**
 * Tells the gate that the writer which held it is done, so the queued
 * writes run once the current event returns.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       null
 */
static uc_value_t *
uc_write_gate_release(uc_vm_t *vm, size_t nargs)
{
	write_gate_t *gate = uc_fn_thisval(GATE_TYPE);

	if (gate)
		gate_release(vm, _uc_fn_this_res(vm), gate);

	return NULL;
}

/**
 * Passes the raised exception to `on_error(label, e)`. An exception in
 * `on_error()` stays raised.
 */
static bool
gate_error(uc_vm_t *vm, uc_value_t *res, const char *label)
{
	uc_value_t *e = uc_vm_exception_object(vm);
	uc_value_t *name = ucv_string_new(label);

	ucv_put(callback_invoke(vm, ucv_resource_value_get(res, GATE_SLOT_ON_ERROR), 2, name, e));
	ucv_put(name);
	ucv_put(e);

	return vm->exception.type == EXCEPTION_NONE;
}

static uc_value_t *
write_failed_new(uc_vm_t *vm)
{
	uc_value_t *rv = ucv_object_new(vm);

	ucv_object_add(rv, "success", ucv_boolean_new(false));
	ucv_object_add(rv, "error", ucv_string_new("Write failed"));

	return rv;
}

/**
 * Runs the queued writes in order until the queue is empty or a writer
 * holds the gate again.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       null
 */
static uc_value_t *
uc_write_gate_drain(uc_vm_t *vm, size_t nargs)
{
	write_gate_t *gate = uc_fn_thisval(GATE_TYPE);
	uc_value_t *res = _uc_fn_this_res(vm);
	uc_value_t *queue, *entry, *result;
	bool busy;

	if (!gate)
		return NULL;

	gate->scheduled = false;
	queue = ucv_resource_value_get(res, GATE_SLOT_QUEUE);

	while (ucv_array_length(queue)) {
		if (!gate_busy(vm, res, &busy) || busy)
			return NULL;

		entry = ucv_array_shift(queue);

		gate->draining = true;
		result = callback_invoke(vm, ucv_array_get(entry, 0), 0);
		gate->draining = false;

		if (vm->exception.type != EXCEPTION_NONE) {
			if (!gate_error(vm, res, "queued write")) {
				ucv_put(entry);
				return NULL;
			}

			result = write_failed_new(vm);
		}

		ucv_put(callback_invoke(vm, ucv_array_get(entry, 1), 1, result));
		ucv_put(result);

		if (vm->exception.type != EXCEPTION_NONE &&
		    !gate_error(vm, res, "queued write reply")) {
			ucv_put(entry);
			return NULL;
		}

		ucv_put(entry);
	}

	return NULL;
}

static const uc_function_list_t write_gate_methods[] = {
	{ "write",   uc_write_gate_write },
	{ "release", uc_write_gate_release },
	{ "drain",   uc_write_gate_drain },
};

/**
 * Registers the `ubbf.write_gate` resource type with the VM.
 *
 * @param vm  ucode VM context
 */
void
write_gate_register_type(uc_vm_t *vm)
{
	uc_type_declare(vm, GATE_TYPE, write_gate_methods, NULL);
}
