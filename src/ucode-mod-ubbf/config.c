/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"
#include "bindings.h"

#include <sha2.h>

#define CONFIG_PATH		"/etc/ubbf/config.json"
#define CONFIG_APPLY		"/usr/libexec/ubbf/apply"
#define CONFIG_RESTORE_REG	"ubbf.config.restore"

/**
 * Validates the path of a configuration file passed in by a ubus caller.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: candidate path)
 * @return       a short reason when the path is unacceptable, null when
 *               it is fine
 */
uc_value_t *
uc_ubbf_config_path_check(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *arg = uc_fn_arg(0);
	const char *path, *part, *end;
	size_t len;

	if (ucv_type(arg) != UC_STRING || *ucv_string_get(arg) != '/')
		return ucv_string_new("file path must be absolute");

	for (path = ucv_string_get(arg); *path; path = end) {
		part = path + 1;
		end = strchrnul(part, '/');
		len = end - part;

		if ((len == 1 && part[0] == '.') ||
		    (len == 2 && part[0] == '.' && part[1] == '.'))
			return ucv_string_new("file path must not contain . or ..");
	}

	return NULL;
}

/**
 * Validates a configuration file with a dry run of ubbf-apply.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 optional: path, default
 *               /etc/ubbf/config.json)
 * @return       `{ success, output }`
 */
uc_value_t *
uc_ubbf_config_validate(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *arg = uc_fn_arg(0);
	uc_value_t *rv = ucv_object_new(vm);
	char *argv[] = { CONFIG_APPLY, "--dry-run", CONFIG_PATH, NULL };
	char *output;
	int status;

	if (ucv_type(arg) == UC_STRING)
		argv[2] = ucv_string_get(arg);

	output = spawn_output(argv, &status);
	if (!output) {
		ucv_object_add(rv, "success", ucv_boolean_new(false));
		ucv_object_add(rv, "output", ucv_string_new("Failed to execute ubbf-apply"));
		return rv;
	}

	ucv_object_add(rv, "success", ucv_boolean_new(status == 0));
	ucv_object_add(rv, "output", ucv_string_new(output));
	free(output);

	return rv;
}

/**
 * Registers the function that replaces the live config with a file.
 *
 * The data model keeps the live config in memory, so a whole-file restore
 * has to go through it. It imports every TR-181 handler, so a handler
 * cannot import it back without a cycle; it registers its restore here
 * instead.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: function called with the
 *               file path and the `done` callback)
 * @return       null
 */
uc_value_t *
uc_ubbf_config_restore_hook_set(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *fn = uc_fn_arg(0);

	uc_vm_registry_set(vm, CONFIG_RESTORE_REG,
			   ucv_is_callable(fn) ? ucv_get(fn) : NULL);

	return NULL;
}

/**
 * Replaces the live config with a config file through the data model.
 *
 * The file is read at once. While a USP transaction is open the restore
 * waits for it to end, and `done` gets the result.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: path, done callback)
 * @return       null when the restore is queued, else
 *               `{ success, error?, rolled_back? }`
 */
uc_value_t *
uc_ubbf_config_restore(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *hook = uc_vm_registry_get(vm, CONFIG_RESTORE_REG);
	uc_value_t *rv;

	if (!hook) {
		rv = ucv_object_new(vm);
		ucv_object_add(rv, "success", ucv_boolean_new(false));
		ucv_object_add(rv, "error", ucv_string_new("No data model to restore into"));
		return rv;
	}

	return callback_invoke(vm, hook, 2, uc_fn_arg(0), uc_fn_arg(1));
}

/**
 * Takes the `_instances` section out of a configuration and seeds the
 * instance map with its pins.
 *
 * @param vm      ucode VM context
 * @param config  configuration tree, changed in place
 * @return        new reference to the pins, or NULL when the tree has none
 */
uc_value_t *
config_pins_take(uc_vm_t *vm, uc_value_t *config)
{
	uc_value_t *pins = ucv_get(ucv_object_get(config, "_instances", NULL));

	if (!pins)
		return NULL;

	ucv_object_delete(config, "_instances");
	instance_pins_seed(vm, pins);

	return pins;
}

/**
 * ucode: `config_pins_take(config)`, see config_pins_take().
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: configuration tree)
 * @return       the pins, or null when the tree had none
 */
uc_value_t *
uc_ubbf_config_pins_take(uc_vm_t *vm, size_t nargs)
{
	return config_pins_take(vm, uc_fn_arg(0));
}

/**
 * Serialises a configuration as config.json holds it: tab-indented JSON
 * with a newline, and the `_instances` section that pins the instance
 * numbers of the runtime rows it stores or names (instance_pins_new()).
 *
 * @param vm      ucode VM context
 * @param config  configuration tree
 * @param pins    pins to write, or NULL to compute them from the map
 * @return        the content, freed by the caller
 */
char *
config_content(uc_vm_t *vm, uc_value_t *config, uc_value_t *pins)
{
	uc_value_t *own = pins ? ucv_get(pins) : instance_pins_new(vm, config);
	uc_value_t *doc = ucv_get(config);
	char *json, *content;

	if (ucv_object_length(own)) {
		ucv_put(doc);
		doc = ucv_object_new(vm);
		ucv_object_foreach(config, key, val)
			ucv_object_add(doc, key, ucv_get(val));
		ucv_object_add(doc, "_instances", ucv_get(own));
	}

	json = ucv_to_jsonstring_formatted(vm, doc, '\t', 1);
	xasprintf(&content, "%s\n", json ? json : "null");
	free(json);
	ucv_put(doc);
	ucv_put(own);

	return content;
}

/**
 * The SHA-256 of a string as lowercase hex, as ucode's digest.sha256().
 *
 * @param s  the string
 * @return   new string value
 */
uc_value_t *
sha256_new(const char *s)
{
	char hex[SHA256_DIGEST_STRING_LENGTH];

	return ucv_string_new(SHA256Data((const uint8_t *)s, strlen(s), hex));
}
