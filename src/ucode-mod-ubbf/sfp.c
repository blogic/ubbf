/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * SFP type and allow list of Device.SFPs (TR-181 2.21), shared by the get
 * handler of modules/usfpd and the device/sfp-allow plugin of ubbf-device,
 * so that SFPCage.{i}.IsAllowed and the blocking agree.
 */

#include "ubbf.h"
#include "bindings.h"

/* ubbf has no XPON and no MoCA stack, so only Ethernet SFPs are usable. */
static const char *const supported_types[] = { "Optical Ethernet", "Electrical Ethernet" };

/**
 * Adds `SUPPORTED_SFP_TYPES` to the module object.
 *
 * @param vm     ucode VM context
 * @param scope  the module object
 */
void
sfp_constants_add(uc_vm_t *vm, uc_value_t *scope)
{
	uc_value_t *types = ucv_array_new(vm);

	for (size_t i = 0; i < ARRAY_SIZE(supported_types); i++)
		ucv_array_push(types, ucv_string_new(supported_types[i]));

	ucv_object_add(scope, "SUPPORTED_SFP_TYPES", types);
}

/* The text of a string variable, or ''. It takes the address of the
 * variable: the text of a short string lives inside the value itself. */
static const char *
string_or_empty(uc_value_t **val)
{
	return ucv_type(*val) == UC_STRING ? ucv_string_get(*val) : "";
}

/*
 * Matches a vendor part number against a pattern in which `*` stands for
 * any run of characters; '' and '*' match every part number. `value` is
 * changed: the text that the last part matched is cut off.
 */
static bool
pn_matches(const char *pattern, char *value)
{
	const char *star = strchr(pattern, '*'), *last, *p, *next;
	size_t first_len, last_len, vlen = strlen(value);
	char *pos, *part, *found;

	if (!*pattern || !strcmp(pattern, "*"))
		return true;
	if (!star)
		return !strcmp(pattern, value);

	first_len = star - pattern;
	last = strrchr(pattern, '*') + 1;
	last_len = strlen(last);

	if (vlen < first_len + last_len || strncmp(value, pattern, first_len) ||
	    strcmp(value + vlen - last_len, last))
		return false;

	/* the middle parts must lie between the first and the last part */
	value[vlen - last_len] = '\0';
	pos = value + first_len;

	for (p = star + 1; p < last; p = next + 1) {
		next = strchr(p, '*');
		part = strndup(p, next - p);
		found = strstr(pos, part);
		free(part);

		if (!found)
			return false;

		pos = found + (next - p);
	}

	return true;
}

static bool
string_eq_lower(const char *a, const char *b)
{
	return !strcasecmp(a, b);
}

/* Whether every vendor criterion that a row sets matches the SFP. */
static bool
vendor_matches(uc_value_t *row, uc_value_t *ident)
{
	uc_value_t *name = ucv_object_get(row, "VendorName", NULL);
	uc_value_t *oui = ucv_object_get(row, "VendorOUI", NULL);
	uc_value_t *pn = ucv_object_get(row, "VendorPN", NULL);
	uc_value_t *iname = ucv_object_get(ident, "VendorName", NULL);
	uc_value_t *ioui = ucv_object_get(ident, "VendorOUI", NULL);
	uc_value_t *ipn = ucv_object_get(ident, "VendorPN", NULL);
	char *value;
	bool ok;

	if (*string_or_empty(&name) && strcmp(string_or_empty(&name), string_or_empty(&iname)))
		return false;

	if (*string_or_empty(&oui) && !string_eq_lower(string_or_empty(&oui), string_or_empty(&ioui)))
		return false;

	value = xstrdup(string_or_empty(&ipn));
	ok = pn_matches(string_or_empty(&pn), value);
	free(value);

	return ok;
}

/**
 * ucode: `sfp_type_resolve(sfps, ident, eeprom_type)`, the type of an SFP:
 * the type of the first enabled SFPProperties.SFP.{i} row that matches its
 * vendor fields, else the type usfpd reads from the EEPROM.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (3 expected: Device.SFPs of the
 *               configuration, VendorName, VendorOUI and VendorPN of the
 *               SFP, SFPType from usfpd)
 * @return       SFP type
 */
uc_value_t *
uc_ubbf_sfp_type_resolve(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *rows = ucv_object_get(ucv_object_get(uc_fn_arg(0), "SFPProperties", NULL), "SFP", NULL);
	uc_value_t *row, *enable, *type, *result = uc_fn_arg(2);
	struct numkeys keys;

	numkeys_sorted(rows, &keys);

	for (size_t i = 0; i < keys.count; i++) {
		row = ucv_object_get(rows, keys.list[i].name, NULL);
		enable = ucv_object_get(row, "Enable", NULL);
		type = ucv_object_get(row, "SFPType", NULL);

		if ((enable && !value_to_bool(enable)) || !ucv_is_truish(type))
			continue;

		if (vendor_matches(row, uc_fn_arg(1))) {
			result = type;
			break;
		}
	}

	free(keys.list);

	return ucv_get(result);
}

/**
 * ucode: `sfp_allowed(sfps, ident, type)`, whether the allow list admits
 * an SFP: AllowAllSFPs true, or an enabled AllowedSFP.{i} row whose set
 * criteria all match.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (3 expected: Device.SFPs of the
 *               configuration, vendor fields of the SFP, the type from
 *               sfp_type_resolve())
 * @return       boolean
 */
uc_value_t *
uc_ubbf_sfp_allowed(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *allowed = ucv_object_get(uc_fn_arg(0), "AllowedSFPs", NULL);
	uc_value_t *all = ucv_object_get(allowed, "AllowAllSFPs", NULL);
	uc_value_t *rows = ucv_object_get(allowed, "AllowedSFP", NULL), *row, *type;
	struct numkeys keys;
	bool ok = false;

	if (!all || value_to_bool(all))
		return ucv_boolean_new(true);

	numkeys_sorted(rows, &keys);

	for (size_t i = 0; !ok && i < keys.count; i++) {
		row = ucv_object_get(rows, keys.list[i].name, NULL);
		if (!value_to_bool(ucv_object_get(row, "Enable", NULL)))
			continue;

		type = ucv_object_get(row, "SFPType", NULL);
		if (*string_or_empty(&type) && !loose_equal(type, uc_fn_arg(2)))
			continue;

		ok = vendor_matches(row, uc_fn_arg(1));
	}

	free(keys.list);

	return ucv_boolean_new(ok);
}
