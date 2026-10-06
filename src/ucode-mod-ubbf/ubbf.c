/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include <ucode/module.h>
#include "ubbf.h"

#define DM_STRING       0x00000001
#define DM_DATETIME     0x00000002
#define DM_BOOL         0x00000004
#define DM_INT          0x00000008
#define DM_UINT         0x00000010
#define DM_ULONG        0x00000020
#define DM_BASE64       0x00000040
#define DM_HEXBIN       0x00000080
#define DM_DECIMAL      0x00000100
#define DM_LONG         0x00000200
#define DM_WRITABLE     0x80000000

/**
 * Formats a Unix timestamp as a USP-style ISO 8601 datetime string.
 *
 * Returns the literal `0001-01-01T00:00:00Z` (USP's "unknown time") when
 * the timestamp cannot be expressed in UTC.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: integer seconds since epoch)
 * @return       ISO 8601 datetime string, or null on bad input
 */
static uc_value_t *
uc_usp_unix_to_datetime(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *arg = uc_fn_arg(0);
	struct tm tm;
	char buf[32];
	time_t t;

	if (ucv_type(arg) != UC_INTEGER)
		return NULL;

	t = (time_t)ucv_int64_get(arg);
	if (!gmtime_r(&t, &tm))
		return ucv_string_new("0001-01-01T00:00:00Z");

	strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", &tm);

	return ucv_string_new(buf);
}

/**
 * Parses a USP-style ISO 8601 datetime string into a Unix timestamp.
 *
 * Accepts up to second precision; trailing fractional or timezone
 * suffix is ignored. Returns 0 when parsing fails.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: datetime string)
 * @return       integer seconds since epoch, or null on bad input
 */
static uc_value_t *
uc_usp_datetime_to_unix(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *arg = uc_fn_arg(0);
	const char *str;
	struct tm tm = { 0 };

	if (ucv_type(arg) != UC_STRING)
		return NULL;

	str = ucv_string_get(arg);
	if (!strptime(str, "%Y-%m-%dT%H:%M:%S", &tm))
		return ucv_int64_new(0);

	return ucv_int64_new((int64_t)timegm(&tm));
}

struct constval {
	const char *name;
	unsigned int value;
};

/**
 * Adds named integer constants to a ucode scope object.
 *
 * @param scope destination scope object
 * @param vals  array of name/value pairs
 * @param n     number of entries in `vals`
 */
static void
scope_add_constants(uc_value_t *scope, const struct constval *vals, size_t n)
{
	for (size_t i = 0; i < n; i++)
		ucv_object_add(scope, vals[i].name, ucv_uint64_new(vals[i].value));
}

/**
 * Injects USP/TR-181 constants and helper functions into the VM scope.
 *
 * Defines the `dm_type` object (data-model parameter type bits), the
 * top-level `USP_ERR_*` and `PERMIT_*` constant groups, and the global
 * helper functions `usp_unix_to_datetime` and `usp_datetime_to_unix`.
 * Called once from `uc_module_init`.
 *
 * @param vm  ucode VM context
 */
static void
scope_inject_globals(uc_vm_t *vm)
{
	uc_value_t *scope = uc_vm_scope_get(vm);
	uc_value_t *dm_types = ucv_object_new(vm);

	static const struct constval type_vals[] = {
		{ "STRING",    DM_STRING },
		{ "DATETIME",  DM_DATETIME },
		{ "BOOL",      DM_BOOL },
		{ "INT",       DM_INT },
		{ "UINT",      DM_UINT },
		{ "ULONG",     DM_ULONG },
		{ "BASE64",    DM_BASE64 },
		{ "HEXBIN",    DM_HEXBIN },
		{ "DECIMAL",   DM_DECIMAL },
		{ "LONG",      DM_LONG },
		{ "WRITABLE",  DM_WRITABLE },
	};

	static const struct constval usp_err_vals[] = {
		{ "USP_ERR_GENERAL_FAILURE",           7000 },
		{ "USP_ERR_MESSAGE_NOT_UNDERSTOOD",    7001 },
		{ "USP_ERR_REQUEST_DENIED",            7002 },
		{ "USP_ERR_INTERNAL_ERROR",            7003 },
		{ "USP_ERR_INVALID_ARGUMENTS",         7004 },
		{ "USP_ERR_RESOURCES_EXCEEDED",        7005 },
		{ "USP_ERR_PERMISSION_DENIED",         7006 },
		{ "USP_ERR_INVALID_CONFIGURATION",     7007 },
		{ "USP_ERR_INVALID_PATH_SYNTAX",       7008 },
		{ "USP_ERR_PARAM_ACTION_FAILED",       7009 },
		{ "USP_ERR_UNSUPPORTED_PARAM",         7010 },
		{ "USP_ERR_INVALID_TYPE",              7011 },
		{ "USP_ERR_INVALID_VALUE",             7012 },
		{ "USP_ERR_PARAM_READ_ONLY",           7013 },
		{ "USP_ERR_VALUE_CONFLICT",            7014 },
		{ "USP_ERR_CRUD_FAILURE",              7015 },
		{ "USP_ERR_OBJECT_DOES_NOT_EXIST",     7016 },
		{ "USP_ERR_CREATION_FAILURE",          7017 },
		{ "USP_ERR_NOT_A_TABLE",               7018 },
		{ "USP_ERR_OBJECT_NOT_CREATABLE",      7019 },
		{ "USP_ERR_SET_FAILURE",               7020 },
		{ "USP_ERR_REQUIRED_PARAM_FAILED",     7021 },
		{ "USP_ERR_COMMAND_FAILURE",           7022 },
		{ "USP_ERR_COMMAND_CANCELLED",         7023 },
		{ "USP_ERR_OBJECT_NOT_DELETABLE",      7024 },
		{ "USP_ERR_UNIQUE_KEY_CONFLICT",       7025 },
		{ "USP_ERR_INVALID_PATH",              7026 },
		{ "USP_ERR_INVALID_COMMAND_ARGS",      7027 },
	};

	static const struct constval permit_vals[] = {
		{ "PERMIT_GET",                0x8000 },
		{ "PERMIT_SET",                0x4000 },
		{ "PERMIT_ADD",                0x0400 },
		{ "PERMIT_DEL",                0x0040 },
		{ "PERMIT_OPER",               0x0002 },
		{ "PERMIT_SUBS_VAL_CHANGE",    0x1000 },
		{ "PERMIT_SUBS_OBJ_ADD",       0x0100 },
		{ "PERMIT_SUBS_OBJ_DEL",       0x0010 },
		{ "PERMIT_SUBS_EVT_OPER_COMP", 0x0001 },
		{ "PERMIT_GET_INST",           0x0080 },
		{ "PERMIT_OBJ_INFO",           0x0800 },
		{ "PERMIT_CMD_INFO",           0x0008 },
		{ "PERMIT_NONE",               0x0000 },
		{ "PERMIT_ALL",                0xFFFF },
	};

	static const uc_function_list_t global_fns[] = {
		{ "usp_unix_to_datetime", uc_usp_unix_to_datetime },
		{ "usp_datetime_to_unix", uc_usp_datetime_to_unix },
	};

	scope_add_constants(dm_types, type_vals,
			    sizeof(type_vals) / sizeof(type_vals[0]));
	ucv_object_add(scope, "dm_type", dm_types);

	scope_add_constants(scope, usp_err_vals,
			    sizeof(usp_err_vals) / sizeof(usp_err_vals[0]));
	scope_add_constants(scope, permit_vals,
			    sizeof(permit_vals) / sizeof(permit_vals[0]));

	uc_function_list_register(scope, global_fns);
}

static const uc_function_list_t module_fns[] = {
	{ "create",                      uc_ubbf_create },
	{ "path_to_parts",               uc_ubbf_path_to_parts },
	{ "navigate",                    uc_ubbf_navigate },
	{ "match_pattern",               uc_ubbf_match_pattern },
	{ "pattern_matches_path",        uc_ubbf_pattern_matches_path },
	{ "pattern_has_more_instances",  uc_ubbf_pattern_has_more_instances },
	{ "deep_clone",                  uc_ubbf_deep_clone },
	{ "navigate_or_create",          uc_ubbf_navigate_or_create },
	{ "set_nested_value",            uc_ubbf_set_nested_value },
	{ "to_bool",                     uc_ubbf_to_bool },
	{ "to_int",                      uc_ubbf_to_int },
	{ "csv_to_list",                 uc_ubbf_csv_to_list },
	{ "ip_to_int",                   uc_ubbf_ip_to_int },
	{ "int_to_ip",                   uc_ubbf_int_to_ip },
	{ "cidr_to_netmask",             uc_ubbf_cidr_to_netmask },
	{ "netmask_to_cidr",             uc_ubbf_netmask_to_cidr },
	{ "ipv6_expand",                 uc_ubbf_ipv6_expand },
	{ "ipv6_prefix_match",           uc_ubbf_ipv6_prefix_match },
	{ "is_instance_key",             uc_ubbf_is_instance_key },
	{ "count_instances",             uc_ubbf_count_instances },
	{ "find_next_instance",          uc_ubbf_find_next_instance },
	{ "instance_num_extract",        uc_ubbf_instance_num_extract },
	{ "last_instance_idx",           uc_ubbf_last_instance_idx },
	{ "find_nested_instances",       uc_ubbf_find_nested_instances },
	{ "collect_instances_for_pattern", uc_ubbf_collect_instances_for_pattern },
	{ "get_parent_config",           uc_ubbf_get_parent_config },
	{ "entries_count_update",        uc_ubbf_entries_count_update },
	{ "get",                         uc_ubbf_get },
	{ "instances",                   uc_ubbf_instances },
	{ "enabled",                     uc_ubbf_enabled },
	{ "interface_to_name",           uc_ubbf_interface_to_name },
	{ "lower_layer_resolve",         uc_ubbf_lower_layer_resolve },
	{ "navigate_data",               uc_ubbf_navigate },
	{ "match_path_pattern",          uc_ubbf_match_pattern },
	{ "instance_count",              uc_ubbf_count_instances },
	{ "ctx_config",                  uc_ubbf_ctx_config },
	{ "ctx_parent",                  uc_ubbf_ctx_parent },
	{ "alias_from_mac",              uc_ubbf_alias_from_mac },
	{ "alias_from_name",             uc_ubbf_alias_from_name },
	{ "enumerate_instances",         uc_ubbf_enumerate_instances },
	{ "get_by_instance",             uc_ubbf_get_by_instance },
	{ "shell_escape",                uc_ubbf_shell_escape },
	{ "format_param_value",          uc_ubbf_format_param_value },
	{ "iso8601_format",              uc_ubbf_iso8601_format },
	{ "iso8601_format_usec",         uc_ubbf_iso8601_format_usec },
	{ "readfile_trim",               uc_ubbf_readfile_trim },
	{ "readfile_int",                uc_ubbf_readfile_int },
	{ "readfile_hex",                uc_ubbf_readfile_hex },
	{ "uptime_read",                 uc_ubbf_uptime_read },
	{ "operstate_to_status",         uc_ubbf_operstate_to_status },
	{ "link_properties_get",         uc_ubbf_link_properties_get },
	{ "ethernet_properties_get",     uc_ubbf_ethernet_properties_get },
	{ "arp_parse",                   uc_ubbf_arp_parse },
	{ "bridge_fdb_parse",            uc_ubbf_bridge_fdb_parse },
	{ "ipv6_neigh_parse",            uc_ubbf_ipv6_neigh_parse },
	{ "hosts_merge",                 uc_ubbf_hosts_merge },
	{ "layer3_interface_find",       uc_ubbf_layer3_interface_find },
	{ "host_primary_ip",             uc_ubbf_host_primary_ip },
	{ "name_sanitise",               uc_ubbf_name_sanitise },
	{ "uci_value_sanitise",          uc_ubbf_uci_value_sanitise },
	{ "mac_is_valid",                uc_ubbf_mac_is_valid },
	{ "transfer_url_validate",       uc_ubbf_transfer_url_validate },
	{ "mac_normalise",               uc_ubbf_mac_normalise },
	{ "mac_from_duid",               uc_ubbf_mac_from_duid },
	{ "tr181_ref_parse",             uc_ubbf_tr181_ref_parse },
	{ "to_int_positive",             uc_ubbf_to_int_positive },
	{ "port_range_format",           uc_ubbf_port_range_format },
	{ "protocol_to_uci",             uc_ubbf_protocol_to_uci },
	{ "freq_to_channel",             uc_ubbf_freq_to_channel },
	{ "antenna_count",               uc_ubbf_antenna_count },
	{ "ipv6_lifetime_status",        uc_ubbf_ipv6_lifetime_status },
	{ "htmode_to_standard",          uc_ubbf_htmode_to_standard },
	{ "htmode_to_bandwidth",         uc_ubbf_htmode_to_bandwidth },
	{ "tmpfile_name",                uc_ubbf_tmpfile_name },
	{ "write_file_atomic",           uc_ubbf_write_file_atomic },
	{ "counter_bump",                uc_ubbf_counter_bump },
	{ "rate_limit_check",            uc_ubbf_rate_limit_check },
	{ "wol_send",                    uc_ubbf_wol_send },
	{ "arch_get",                    uc_ubbf_arch_get },
	{ "apk_installed",               uc_ubbf_apk_installed },
	{ "statvfs_info",                uc_ubbf_statvfs_info },
	{ "du_kib",                      uc_ubbf_du_kib },
	{ "mac_to_base64",               uc_ubbf_mac_to_base64 },
	{ "int_to_hexbin",               uc_ubbf_int_to_hexbin },
	{ "dscp_map_to_hex",             uc_ubbf_dscp_map_to_hex },
	{ "bss_index_by_bssid",          uc_ubbf_bss_index_by_bssid },
	{ "ipv4_addr_to_object",         uc_ubbf_ipv4_addr_to_object },
	{ "ipv6_addr_to_object",         uc_ubbf_ipv6_addr_to_object },
	{ "ipv6_prefix_to_object",       uc_ubbf_ipv6_prefix_to_object },
	{ "txpower_pct_to_dbm",          uc_ubbf_txpower_pct_to_dbm },
	{ "wifi_operating_standard",     uc_ubbf_wifi_operating_standard },
	{ "led_read_info",               uc_ubbf_led_read_info },
	{ "cpu_stats",                   uc_ubbf_cpu_stats },
	{ "process_count",               uc_ubbf_process_count },
	{ "process_info",                uc_ubbf_process_info },
	{ "leases_parse",                uc_ubbf_leases_parse },
	{ "curl_w_metrics_parse",        uc_ubbf_curl_w_metrics_parse },
	{ "diag_result_expand",          uc_ubbf_diag_result_expand },
	{ "ping_output_parse",           uc_ubbf_ping_output_parse },
	{ "traceroute_output_parse",     uc_ubbf_traceroute_output_parse },
	{ "usb_enumerate",               uc_ubbf_usb_enumerate },
	{ "usb_device_info",             uc_ubbf_usb_device_info },
	{ "usb_interface_info",          uc_ubbf_usb_interface_info },
	{ "usb_net_interfaces",          uc_ubbf_usb_net_interfaces },
};

/**
 * Module entry point invoked by the ucode loader.
 *
 * Registers the `ubbf.dm` resource type, exports the `module_fns` table
 * onto the module scope, and injects the USP/TR-181 constants and
 * top-level helpers into the VM scope.
 *
 * @param vm     ucode VM context
 * @param scope  module scope object that receives the exports
 */
void uc_module_init(uc_vm_t *vm, uc_value_t *scope)
{
	dm_register_type(vm);
	uc_function_list_register(scope, module_fns);
	scope_inject_globals(vm);
}
