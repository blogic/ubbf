/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "harness.h"

#include <stdlib.h>
#include <string.h>

#include <json-c/json.h>

#include <ucode/compiler.h>
#include <ucode/source.h>
#include <ucode/program.h>

/* The entry point of ubbf.so, which the static library carries along. */
void uc_module_init(uc_vm_t *vm, uc_value_t *scope);

int
vm_setup(void **state)
{
	uc_vm_t *vm = calloc(1, sizeof(*vm));
	uc_value_t *module;

	if (!vm)
		return -1;

	uc_vm_init(vm, NULL);
	uc_stdlib_load(uc_vm_scope_get(vm));

	module = ucv_object_new(vm);
	uc_module_init(vm, module);
	ucv_object_add(uc_vm_scope_get(vm), "ubbf", module);

	*state = vm;

	return 0;
}

int
vm_teardown(void **state)
{
	uc_vm_t *vm = *state;

	uc_vm_free(vm);
	free(vm);

	return 0;
}

static uc_value_t *
call_pushed(uc_vm_t *vm, bool mcall, size_t nargs, va_list ap)
{
	for (size_t i = 0; i < nargs; i++)
		uc_vm_stack_push(vm, va_arg(ap, uc_value_t *));

	if (uc_vm_call(vm, mcall, nargs) != EXCEPTION_NONE)
		fail_msg("exception: %s", vm->exception.message ? vm->exception.message : "?");

	return uc_vm_stack_pop(vm);
}

uc_value_t *
vm_call(uc_vm_t *vm, uc_cfn_ptr_t fn, size_t nargs, ...)
{
	uc_value_t *res;
	va_list ap;

	uc_vm_stack_push(vm, ucv_cfunction_new("test", fn));

	va_start(ap, nargs);
	res = call_pushed(vm, false, nargs, ap);
	va_end(ap);

	return res;
}

uc_value_t *
vm_method(uc_vm_t *vm, uc_value_t *obj, const char *name, size_t nargs, ...)
{
	uc_value_t *fn = ucv_property_get(obj, name), *res;
	va_list ap;

	if (!ucv_is_callable(fn))
		fail_msg("no method %s", name);

	uc_vm_stack_push(vm, ucv_get(obj));
	uc_vm_stack_push(vm, ucv_get(fn));

	va_start(ap, nargs);
	res = call_pushed(vm, true, nargs, ap);
	va_end(ap);

	return res;
}

uc_value_t *
vm_eval(uc_vm_t *vm, const char *code)
{
	uc_parse_config_t config = uc_default_parse_config;
	uc_source_t *source;
	uc_program_t *program;
	uc_value_t *res = NULL;
	char *err = NULL, *buf = xstrdup(code);

	config.raw_mode = true;

	/* The source keeps the buffer and frees it. */
	source = uc_source_new_buffer("test", buf, strlen(buf));
	program = uc_compile(&config, source, &err);
	if (!program)
		fail_msg("compile: %s", err ? err : "?");

	if (uc_vm_execute(vm, program, &res) != STATUS_OK)
		fail_msg("exception: %s", vm->exception.message ? vm->exception.message : "?");

	uc_program_put(program);
	uc_source_put(source);

	return res;
}

uc_value_t *
vm_module(uc_vm_t *vm)
{
	return ucv_object_get(uc_vm_scope_get(vm), "ubbf", NULL);
}

uc_value_t *
vm_json(uc_vm_t *vm, const char *text)
{
	json_object *jso = json_tokener_parse(text);
	uc_value_t *val;

	assert_non_null(jso);
	val = ucv_from_json(vm, jso);
	json_object_put(jso);

	return val;
}

char *
vm_to_json(uc_vm_t *vm, uc_value_t *val)
{
	return ucv_to_jsonstring(vm, val);
}
