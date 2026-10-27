/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * Learned rows of Device.DNS.Client.Server and Device.DNS.Relay.Forwarding.
 * The resolv file paths stay in utils/dns.uc.
 */

#include "ubbf.h"
#include "bindings.h"

/**
 * ucode: `dns_learned_row(row)`, whether a server or forwarding row
 * belongs to a learned server. A controller adds Static rows; the first
 * write into a learned row stores the Type of its source.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: the row or null)
 * @return       boolean
 */
uc_value_t *
uc_ubbf_dns_learned_row(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *type = ucv_object_get(uc_fn_arg(0), "Type", NULL);
	uc_value_t *row_static = ucv_string_new("Static");
	bool learned = type && !loose_equal(type, row_static);

	ucv_put(row_static);

	return ucv_boolean_new(learned);
}
