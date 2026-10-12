/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include <ucode/module.h>
#include "ubbf.h"
#include "bindings.h"

const struct constval dm_type_vals[] = {
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

const size_t dm_type_vals_count = sizeof(dm_type_vals) / sizeof(dm_type_vals[0]);

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

	scope_add_constants(dm_types, dm_type_vals, dm_type_vals_count);
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
	{ "pattern_matches_path",        uc_ubbf_pattern_matches_path },
	{ "navigate_or_create",          uc_ubbf_navigate_or_create },
	{ "to_bool",                     uc_ubbf_to_bool },
	{ "to_int",                      uc_ubbf_to_int },
	{ "csv_to_list",                 uc_ubbf_csv_to_list },
	{ "ip_to_int",                   uc_ubbf_ip_to_int },
	{ "int_to_ip",                   uc_ubbf_int_to_ip },
	{ "cidr_to_netmask",             uc_ubbf_cidr_to_netmask },
	{ "netmask_to_cidr",             uc_ubbf_netmask_to_cidr },
	{ "is_instance_key",             uc_ubbf_is_instance_key },
	{ "find_next_instance",          uc_ubbf_find_next_instance },
	{ "collect_instances_for_pattern", uc_ubbf_collect_instances_for_pattern },
	{ "entries_count_update",        uc_ubbf_entries_count_update },
	{ "get",                         uc_ubbf_get },
	{ "instances",                   uc_ubbf_instances },
	{ "enabled",                     uc_ubbf_enabled },
	{ "interface_to_name",           uc_ubbf_interface_to_name },
	{ "lower_layer_resolve",         uc_ubbf_lower_layer_resolve },
	{ "ethernet_interface_path",     uc_ubbf_ethernet_interface_path },
	{ "upstream_interface_ref",      uc_ubbf_upstream_interface_ref },
	{ "lower_layers_wifi",           uc_ubbf_lower_layers_wifi },
	{ "port_snooped",                uc_ubbf_port_snooped },
	{ "tree_leaves",                 uc_ubbf_tree_leaves },
	{ "navigate_data",               uc_ubbf_navigate },
	{ "instance_count",              uc_ubbf_count_instances },
	{ "ctx_config",                  uc_ubbf_ctx_config },
	{ "alias_from_mac",              uc_ubbf_alias_from_mac },
	{ "alias_from_name",             uc_ubbf_alias_from_name },
	{ "enumerate_instances",         uc_ubbf_enumerate_instances },
	{ "get_by_instance",             uc_ubbf_get_by_instance },
	{ "shell_escape",                uc_ubbf_shell_escape },
	{ "iso8601_format",              uc_ubbf_iso8601_format },
	{ "datetime_format",             uc_ubbf_datetime_format },
	{ "iso8601_format_usec",         uc_ubbf_iso8601_format_usec },
	{ "iso8601_local_format",        uc_ubbf_iso8601_local_format },
	{ "readfile_trim",               uc_ubbf_readfile_trim },
	{ "readfile_int",                uc_ubbf_readfile_int },
	{ "uptime_read",                 uc_ubbf_uptime_read },
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
	{ "text_clamp",                  uc_ubbf_text_clamp },
	{ "cmd_build",                   uc_ubbf_cmd_build },
	{ "mac_is_valid",                uc_ubbf_mac_is_valid },
	{ "transfer_url_validate",       uc_ubbf_transfer_url_validate },
	{ "mac_normalise",               uc_ubbf_mac_normalise },
	{ "mac_from_duid",               uc_ubbf_mac_from_duid },
	{ "tr181_ref_parse",             uc_ubbf_tr181_ref_parse },
	{ "port_range_format",           uc_ubbf_port_range_format },
	{ "protocol_to_uci",             uc_ubbf_protocol_to_uci },
	{ "chain_rules_ordered",         uc_ubbf_chain_rules_ordered },
	{ "firewall_set_resolve",        uc_ubbf_firewall_set_resolve },
	{ "chain_rule_set_matches",      uc_ubbf_chain_rule_set_matches },
	{ "chain_rule_unsupported",      uc_ubbf_chain_rule_unsupported },
	{ "firewall_rules_expired",      uc_ubbf_firewall_rules_expired },
	{ "firewall_expiry_next",        uc_ubbf_firewall_expiry_next },
	{ "firewall_reconcile",          uc_ubbf_firewall_reconcile },
	{ "start_time_valid",            uc_ubbf_start_time_valid },
	{ "intervals_union",             uc_ubbf_intervals_union },
	{ "intervals_complement",        uc_ubbf_intervals_complement },
	{ "schedule_intervals",          uc_ubbf_schedule_intervals },
	{ "intervals_to_windows",        uc_ubbf_intervals_to_windows },
	{ "week_seconds",                uc_ubbf_week_seconds },
	{ "intervals_active",            uc_ubbf_intervals_active },
	{ "schedule_state",              uc_ubbf_schedule_state },
	{ "refs_intervals",              uc_ubbf_refs_intervals },
	{ "schedule_windows",            uc_ubbf_schedule_windows },
	{ "schedule_refs_check",         uc_ubbf_schedule_refs_check },
	{ "schedule_refs_prune",         uc_ubbf_schedule_refs_prune },
	{ "router_table_id",             uc_ubbf_router_table_id },
	{ "forwarding_policy_set",       uc_ubbf_forwarding_policy_set },
	{ "source_prefix",               uc_ubbf_source_prefix },
	{ "route_dest",                  uc_ubbf_route_dest },
	{ "prefix_intersect",            uc_ubbf_prefix_intersect },
	{ "source_tables",               uc_ubbf_source_tables },
	{ "source_table_contents",       uc_ubbf_source_table_contents },
	{ "source_rules",                uc_ubbf_source_rules },
	{ "main_source_rules",           uc_ubbf_main_source_rules },
	{ "policy_resolve",              uc_ubbf_policy_resolve },
	{ "prefix6_parse",               uc_ubbf_prefix6_parse },
	{ "prefix6_contains",            uc_ubbf_prefix6_contains },
	{ "nptv6_setting_check",         uc_ubbf_nptv6_setting_check },
	{ "sfp_type_resolve",            uc_ubbf_sfp_type_resolve },
	{ "sfp_allowed",                 uc_ubbf_sfp_allowed },
	{ "key_acceptable",              uc_ubbf_key_acceptable },
	{ "dns_learned_row",             uc_ubbf_dns_learned_row },
	{ "hosts_leases_by_mac",         uc_ubbf_hosts_leases_by_mac },
	{ "hosts_ap_ssids",              uc_ubbf_hosts_ap_ssids },
	{ "ipv6_maps_merge",             uc_ubbf_ipv6_maps_merge },
	{ "netifd_interfaces_build",     uc_ubbf_netifd_interfaces_build },
	{ "ap_by_ssid_instance",         uc_ubbf_ap_by_ssid_instance },
	{ "pool_client_paths",           uc_ubbf_pool_client_paths },
	{ "hosts_state_load",            uc_ubbf_hosts_state_load },
	{ "host_active_track",           uc_ubbf_host_active_track },
	{ "hosts_downstream_build",      uc_ubbf_hosts_downstream_build },
	{ "hosts_inactive_drop",         uc_ubbf_hosts_inactive_drop },
	{ "hosts_state_flush",           uc_ubbf_hosts_state_flush },
	{ "host_path_by_ip_find",        uc_ubbf_host_path_by_ip_find },
	{ "ifstats_build",               uc_ubbf_ifstats_build },
	{ "ipv6_leases_by_mac",          uc_ubbf_ipv6_leases_by_mac },
	{ "ipv6_pool_clients_build",     uc_ubbf_ipv6_pool_clients_build },
	{ "pool_leases_by_key",          uc_ubbf_pool_leases_by_key },
	{ "static_address_states",       uc_ubbf_static_address_states },
	{ "dhcp_option_value",           uc_ubbf_dhcp_option_value },
	{ "hex_to_printable",            uc_ubbf_hex_to_printable },
	{ "prefix_length_nibble_check",  uc_ubbf_prefix_length_nibble_check },
	{ "ra_prefixes_hook_read",       uc_ubbf_ra_prefixes_hook_read },
	{ "ipv6_prefix_rows_build",      uc_ubbf_ipv6_prefix_rows_build },
	{ "ip_interface_members",        uc_ubbf_ip_interface_members },
	{ "freq_to_channel",             uc_ubbf_freq_to_channel },
	{ "antenna_count",               uc_ubbf_antenna_count },
	{ "tmpfile_name",                uc_ubbf_tmpfile_name },
	{ "write_file_atomic",           uc_ubbf_write_file_atomic },
	{ "arch_get",                    uc_ubbf_arch_get },
	{ "apk_version",                 uc_ubbf_apk_version },
	{ "statvfs_info",                uc_ubbf_statvfs_info },
	{ "ipv4_addr_to_object",         uc_ubbf_ipv4_addr_to_object },
	{ "ipv6_addr_to_object",         uc_ubbf_ipv6_addr_to_object },
	{ "ipv6_prefix_to_object",       uc_ubbf_ipv6_prefix_to_object },
	{ "txpower_pct_to_dbm",          uc_ubbf_txpower_pct_to_dbm },
	{ "wifi_operating_standard",     uc_ubbf_wifi_operating_standard },
	{ "standards_to_highest",        uc_ubbf_standards_to_highest },
	{ "standards_bandwidth_to_htmode", uc_ubbf_standards_bandwidth_to_htmode },
	{ "clamp_htmode",                uc_ubbf_clamp_htmode },
	{ "channel_width_to_bandwidth",  uc_ubbf_channel_width_to_bandwidth },
	{ "band_to_uci",                 uc_ubbf_band_to_uci },
	{ "band_to_index",               uc_ubbf_band_to_index },
	{ "radio_address_derive",        uc_ubbf_radio_address_derive },
	{ "dscp_parse",                  uc_ubbf_dscp_parse },
	{ "qos_map_set_render",          uc_ubbf_qos_map_set_render },
	{ "phy_max_standard",            uc_ubbf_phy_max_standard },
	{ "phy_supported_bandwidths",    uc_ubbf_phy_supported_bandwidths },
	{ "phy_max_bandwidth",           uc_ubbf_phy_max_bandwidth },
	{ "phy_max_ssids",               uc_ubbf_phy_max_ssids },
	{ "phy_max_bitrate",             uc_ubbf_phy_max_bitrate },
	{ "phy_max_txpower",             uc_ubbf_phy_max_txpower },
	{ "phy_supported_bands",         uc_ubbf_phy_supported_bands },
	{ "phy_supported_standards",     uc_ubbf_phy_supported_standards },
	{ "phy_possible_channels",       uc_ubbf_phy_possible_channels },
	{ "channel_valid_for_bandwidth", uc_ubbf_channel_valid_for_bandwidth },
	{ "wpa_psk",                     uc_ubbf_wpa_psk },
	{ "ht_caps_encode",              uc_ubbf_ht_caps_encode },
	{ "vht_caps_encode",             uc_ubbf_vht_caps_encode },
	{ "sta_he_caps_build",           uc_ubbf_sta_he_caps_build },
	{ "sta_he_caps_from_nl80211",    uc_ubbf_sta_he_caps_from_nl80211 },
	{ "sta_he_caps_from_flags",      uc_ubbf_sta_he_caps_from_flags },
	{ "sta_he_caps_from_frame_body", uc_ubbf_sta_he_caps_from_frame_body },
	{ "chipset_vendor_get",          uc_ubbf_chipset_vendor_get },
	{ "radio_survey_build",          uc_ubbf_radio_survey_build },
	{ "radio_capability_build",      uc_ubbf_radio_capability_build },
	{ "local_sta_data_build",        uc_ubbf_local_sta_data_build },
	{ "topology_devices_build",      uc_ubbf_topology_devices_build },
	{ "device_api_data_build",       uc_ubbf_device_api_data_build },
	{ "cpu_stats",                   uc_ubbf_cpu_stats },
	{ "process_count",               uc_ubbf_process_count },
	{ "process_info",                uc_ubbf_process_info },
	{ "module_spawn",                uc_ubbf_module_spawn },
	{ "module_kill",                 uc_ubbf_module_kill },
	{ "leases_parse",                uc_ubbf_leases_parse },
	{ "curl_w_metrics_parse",        uc_ubbf_curl_w_metrics_parse },
	{ "curl_insecure_allowed",       uc_ubbf_curl_insecure_allowed },
	{ "curl_exit_to_status",         uc_ubbf_curl_exit_to_status },
	{ "curl_download",               uc_ubbf_curl_download },
	{ "curl_send",                   uc_ubbf_curl_send },
	{ "curl_upload",                 uc_ubbf_curl_upload },
	{ "ping_output_parse",           uc_ubbf_ping_output_parse },
	{ "traceroute_output_parse",     uc_ubbf_traceroute_output_parse },
	{ "schema_get",                  uc_ubbf_schema_get },
	{ "schema_defaults",             uc_ubbf_schema_defaults },
	{ "schema_param_info",           uc_ubbf_schema_param_info },
	{ "schema_extract",              uc_ubbf_schema_extract },
	{ "schema_entry_addable",        uc_ubbf_schema_entry_addable },
	{ "schema_protocol_set",         uc_ubbf_schema_protocol_set },
	{ "schema_version_set",          uc_ubbf_schema_version_set },
	{ "schema_tables",               uc_ubbf_schema_tables },
	{ "schema_tables_load",          uc_ubbf_schema_tables_load },
	{ "log_init",                    uc_ubbf_log_init },
	{ "log_debug",                   uc_ubbf_log_debug },
	{ "log_info",                    uc_ubbf_log_info },
	{ "log_warn",                    uc_ubbf_log_warn },
	{ "log_err",                     uc_ubbf_log_err },
	{ "log_exception",               uc_ubbf_log_exception },
	{ "active_protocol",             uc_ubbf_active_protocol },
	{ "cwmp_mode",                   uc_ubbf_cwmp_mode },
	{ "transfer_complete",           uc_ubbf_transfer_complete },
	{ "write_gate_create",           uc_ubbf_write_gate_create },
	{ "cache_call",                  uc_ubbf_cache_call },
	{ "cache_invalidate",            uc_ubbf_cache_invalidate },
	{ "link_local_addresses_get",    uc_ubbf_link_local_addresses_get },
	{ "ra_prefixes_get",             uc_ubbf_ra_prefixes_get },
	{ "ethtool_properties_get",      uc_ubbf_ethtool_properties_get },
	{ "ethtool_stats_get",           uc_ubbf_ethtool_stats_get },
	{ "uci_change_update",           uc_ubbf_uci_change_update },
	{ "uci_last_changed",            uc_ubbf_uci_last_changed },
	{ "deviceinfo_get",              uc_ubbf_deviceinfo_get },
	{ "acl_role_load",               uc_ubbf_acl_role_load },
	{ "acl_can_diagnose",            uc_ubbf_acl_can_diagnose },
	{ "acl_can_write",               uc_ubbf_acl_can_write },
	{ "acl_can_add",                 uc_ubbf_acl_can_add },
	{ "acl_filter_tree",             uc_ubbf_acl_filter_tree },
	{ "ifop_status_derive",          uc_ubbf_ifop_status_derive },
	{ "bridge_status_derive",        uc_ubbf_bridge_status_derive },
	{ "order_snapshot",              uc_ubbf_order_snapshot },
	{ "orders_compute",              uc_ubbf_orders_compute },
	{ "config_path_check",           uc_ubbf_config_path_check },
	{ "config_validate",             uc_ubbf_config_validate },
	{ "config_restore_hook_set",     uc_ubbf_config_restore_hook_set },
	{ "config_restore",              uc_ubbf_config_restore },
	{ "config_pins_take",            uc_ubbf_config_pins_take },
	{ "instance_map_own",            uc_ubbf_instance_map_own },
	{ "instance_numbers",            uc_ubbf_instance_numbers },
	{ "instance_numbers_known",      uc_ubbf_instance_numbers_known },
	{ "instance_number",             uc_ubbf_instance_number },
	{ "instance_prune",              uc_ubbf_instance_prune },
	{ "instance_key",                uc_ubbf_instance_key },
	{ "instance_lookup",             uc_ubbf_instance_lookup },
	{ "instance_rows",               uc_ubbf_instance_rows },
	{ "instance_items",              uc_ubbf_instance_items },
	{ "instance_floor",              uc_ubbf_instance_floor },
	{ "instance_ids",                uc_ubbf_instance_ids },
	{ "instance_id_rows",            uc_ubbf_instance_id_rows },
	{ "instance_stack",              uc_ubbf_instance_stack },
	{ "instance_retire",             uc_ubbf_instance_retire },
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
	write_gate_register_type(vm);
	uc_function_list_register(scope, module_fns);
	scope_add_constants(scope, routing_vals, routing_vals_count);
	scope_add_constants(scope, curl_vals, curl_vals_count);
	sfp_constants_add(vm, scope);
	scope_inject_globals(vm);
}
