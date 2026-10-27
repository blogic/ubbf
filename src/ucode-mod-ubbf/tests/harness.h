/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#ifndef UBBF_TEST_HARNESS_H
#define UBBF_TEST_HARNESS_H

/* cmocka.h needs these before it. */
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <setjmp.h>
#include <cmocka.h>

#include <ucode/vm.h>
#include <ucode/lib.h>

#include "bindings.h"

/**
 * cmocka group setup: a ucode VM with the standard library and ubbf.so
 * initialised as an import does (module object `ubbf`, the ubbf.dm type,
 * the USP_ERR_* globals), in *state.
 */
int vm_setup(void **state);

/**
 * cmocka group teardown: frees the VM of vm_setup().
 */
int vm_teardown(void **state);

/**
 * Calls a C function of the ucode API (a uc_ubbf_* binding) through the
 * VM, as a script call does, so uc_fn_arg() sees the arguments.
 *
 * @param vm     VM of vm_setup()
 * @param fn     the binding
 * @param nargs  number of arguments that follow, each one owned by the call
 * @return       the result, owned by the caller (NULL is a null result);
 *               an exception fails the test
 */
uc_value_t *vm_call(uc_vm_t *vm, uc_cfn_ptr_t fn, size_t nargs, ...);

/**
 * Calls a method of an object or resource with `this`, as a script call
 * `obj.name(...)` does, so uc_fn_thisval() sees the object.
 *
 * @param vm     VM of vm_setup()
 * @param obj    the object, borrowed
 * @param name   the method name
 * @param nargs  number of arguments that follow, each one owned by the call
 * @return       as vm_call()
 */
uc_value_t *vm_method(uc_vm_t *vm, uc_value_t *obj, const char *name, size_t nargs, ...);

/**
 * Runs ucode source in the VM, with `ubbf` and the standard library in
 * scope, for a case that needs a value only a script makes (an exception
 * object, a closure).
 *
 * @param vm    VM of vm_setup()
 * @param code  ucode source (raw mode, not a template)
 * @return      the value of a `return` at top level, owned by the caller;
 *              a compile error or an exception fails the test
 */
uc_value_t *vm_eval(uc_vm_t *vm, const char *code);

/**
 * Returns the module object of ubbf.so that vm_setup() made, borrowed.
 */
uc_value_t *vm_module(uc_vm_t *vm);

/**
 * Builds a value from JSON text, for test data.
 *
 * @param vm    VM of vm_setup()
 * @param text  JSON text
 * @return      the value, owned by the caller; the test fails on bad JSON
 */
uc_value_t *vm_json(uc_vm_t *vm, const char *text);

/**
 * Serialises a value to compact JSON, for comparisons.
 *
 * @param vm   VM of vm_setup()
 * @param val  the value
 * @return     the JSON text, freed by the caller
 */
char *vm_to_json(uc_vm_t *vm, uc_value_t *val);

/**
 * Asserts that a value serialises to the expected JSON text.
 */
#define assert_json_equal(vm, val, expected) do {			\
	char *_json = vm_to_json((vm), (val));				\
	assert_string_equal(_json, (expected));				\
	free(_json);							\
} while (0)

#endif
