/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * Calls from C into the VM, and state that a VM keeps for the module.
 */

#include "ubbf.h"

#include <stdarg.h>

/**
 * Calls a function of the VM, as `this.fn(...args)` when `this` is given.
 * An exception stays raised for the caller: it propagates when the
 * binding returns, or exception_log_clear() takes it.
 *
 * @param vm     ucode VM context
 * @param this   receiver, or NULL for a plain call
 * @param fn     the function; anything else gives NULL and raises nothing
 * @param nargs  number of arguments
 * @param args   the arguments, borrowed
 * @return       new reference to the result, or NULL on an exception
 */
uc_value_t *
callback_call(uc_vm_t *vm, uc_value_t *this, uc_value_t *fn, size_t nargs,
	      uc_value_t **args)
{
	if (!ucv_is_callable(fn))
		return NULL;

	if (this)
		uc_vm_stack_push(vm, ucv_get(this));
	uc_vm_stack_push(vm, ucv_get(fn));
	for (size_t i = 0; i < nargs; i++)
		uc_vm_stack_push(vm, ucv_get(args[i]));

	if (uc_vm_call(vm, this != NULL, nargs) != EXCEPTION_NONE)
		return NULL;

	return uc_vm_stack_pop(vm);
}

/**
 * callback_call() without `this`, the arguments given in the call.
 *
 * @param vm     ucode VM context
 * @param fn     the function
 * @param nargs  number of the arguments that follow, borrowed
 * @return       new reference to the result, or NULL on an exception
 */
uc_value_t *
callback_invoke(uc_vm_t *vm, uc_value_t *fn, size_t nargs, ...)
{
	uc_value_t *args[8];
	va_list ap;

	if (nargs > ARRAY_SIZE(args))
		return NULL;

	va_start(ap, nargs);
	for (size_t i = 0; i < nargs; i++)
		args[i] = va_arg(ap, uc_value_t *);
	va_end(ap);

	return callback_call(vm, NULL, fn, nargs, args);
}

/**
 * A value that the module keeps per VM in the registry, made on first
 * use. The registry is a GC root, so the value and what it holds live as
 * long as the VM.
 *
 * @param vm    ucode VM context
 * @param key   registry key, "ubbf.<name>"
 * @param type  UC_OBJECT or UC_ARRAY, the type of a new value
 * @return      the value, borrowed
 */
uc_value_t *
registry_get(uc_vm_t *vm, const char *key, uc_type_t type)
{
	uc_value_t *val = uc_vm_registry_get(vm, key);

	if (val)
		return val;

	val = (type == UC_ARRAY) ? ucv_array_new(vm) : ucv_object_new(vm);
	uc_vm_registry_set(vm, key, val);

	return val;
}
