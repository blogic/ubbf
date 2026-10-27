/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * The management protocol of the image. Firmware images ship exactly one
 * of obuspa (USP) or cwmpd (CWMP), so the presence of the cwmpd binary is
 * a faithful signal; ubbf-device needs the answer without building the
 * data model.
 */

#include "ubbf.h"
#include "bindings.h"

#define CWMPD_PATH	"/usr/sbin/cwmpd"

/**
 * Reports whether the image runs CWMP. The answer is read once per
 * process: the binary does not come or go while ubbf runs.
 *
 * @return  true for a CWMP image, false for a USP image
 */
bool
ubbf_cwmp_mode(void)
{
	static int mode = -1;
	struct stat st;

	if (mode < 0)
		mode = (stat(CWMPD_PATH, &st) == 0);

	return mode;
}

/**
 * ucode: `active_protocol()`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       "cwmp" or "usp"
 */
uc_value_t *
uc_ubbf_active_protocol(uc_vm_t *vm, size_t nargs)
{
	return ucv_string_new(ubbf_cwmp_mode() ? "cwmp" : "usp");
}

/**
 * ucode: `cwmp_mode()`. See ubbf_cwmp_mode().
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       true for a CWMP image
 */
uc_value_t *
uc_ubbf_cwmp_mode(uc_vm_t *vm, size_t nargs)
{
	return ucv_boolean_new(ubbf_cwmp_mode());
}

#define USP_ERR_GENERAL_FAILURE		7000
#define USP_ERR_COMMAND_FAILURE		7022

/**
 * Calls a function, as `this.name(...)` when `this` is given, and drops
 * the result. The call owns the arguments. A function that is missing
 * raises a type exception, as the same call in ucode does.
 */
static bool
function_call(uc_vm_t *vm, uc_value_t *this, const char *name,
	      uc_value_t *fn, size_t nargs, uc_value_t **args)
{
	bool ok = ucv_is_callable(fn);

	if (ok)
		ucv_put(callback_call(vm, this, fn, nargs, args));
	else
		uc_vm_raise_exception(vm, EXCEPTION_TYPE, "%s is not a function", name);

	for (size_t i = 0; i < nargs; i++)
		ucv_put(args[i]);

	return ok && vm->exception.type == EXCEPTION_NONE;
}

/**
 * Signals the end of a USP transfer operation: sends the
 * Device.LocalAgent.TransferComplete! event through the
 * `usp_datamodel_event()` of the agent and completes the operation through
 * `ctx.complete()`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: transfer context with
 *               `command`, `command_key`, `transfer_type`, `obj_path`,
 *               `url`, `start_time`, `instance` and `complete`; fault
 *               string, or null on success)
 * @return       null
 */
uc_value_t *
uc_ubbf_transfer_complete(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *ctx = uc_fn_arg(0);
	uc_value_t *fault = uc_fn_arg(1);
	uc_value_t *start = ucv_object_get(ctx, "start_time", NULL);
	uc_value_t *key = ucv_object_get(ctx, "command_key", NULL);
	uc_value_t *now = ucv_int64_new(time(NULL));
	bool failed = ucv_is_truish(fault);
	uc_value_t *event = ucv_object_new(vm);
	uc_value_t *output = ucv_object_new(vm);
	uc_value_t *args[4];

	ucv_object_add(event, "Command", ucv_get(ucv_object_get(ctx, "command", NULL)));
	ucv_object_add(event, "CommandKey", key ? ucv_get(key) : ucv_string_new(""));
	ucv_object_add(event, "Requestor", ucv_string_new(""));
	ucv_object_add(event, "TransferType", ucv_get(ucv_object_get(ctx, "transfer_type", NULL)));
	ucv_object_add(event, "Affected", ucv_get(ucv_object_get(ctx, "obj_path", NULL)));
	ucv_object_add(event, "TransferURL", ucv_get(ucv_object_get(ctx, "url", NULL)));
	ucv_object_add(event, "StartTime", unix_to_datetime_new(start));
	ucv_object_add(event, "CompleteTime", unix_to_datetime_new(now));
	ucv_object_add(event, "FaultCode", ucv_int64_new(failed ? USP_ERR_GENERAL_FAILURE : 0));
	ucv_object_add(event, "FaultString", fault ? ucv_get(fault) : ucv_string_new(""));

	ucv_object_add(output, "MaxRetries", ucv_string_new("0"));
	ucv_object_add(output, "StartTime", unix_to_datetime_new(start));
	ucv_object_add(output, "CompleteTime", unix_to_datetime_new(now));
	ucv_put(now);

	args[0] = ucv_string_new("Device.LocalAgent.TransferComplete!");
	args[1] = event;
	if (!function_call(vm, NULL, "usp_datamodel_event",
			   ucv_object_get(uc_vm_scope_get(vm), "usp_datamodel_event", NULL),
			   2, args)) {
		ucv_put(output);
		return NULL;
	}

	args[0] = ucv_get(ucv_object_get(ctx, "instance", NULL));
	args[1] = ucv_int64_new(failed ? USP_ERR_COMMAND_FAILURE : 0);
	args[2] = failed ? ucv_get(fault) : NULL;
	args[3] = output;
	function_call(vm, ctx, "complete", ucv_property_get(ctx, "complete"), 4, args);

	return NULL;
}
