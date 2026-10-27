/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * The functions that ubbf.c exports to ucode, and the registration of the
 * resource types. C code calls the functions of ubbf.h instead.
 */

#ifndef UBBF_BINDINGS_H
#define UBBF_BINDINGS_H

#include <ucode/lib.h>
#include <ucode/vm.h>

/* acl.c */
uc_value_t *uc_ubbf_acl_role_load(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_acl_can_diagnose(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_acl_can_write(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_acl_can_add(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_acl_filter_tree(uc_vm_t *vm, size_t nargs);

/* atomic.c */
uc_value_t *uc_ubbf_tmpfile_name(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_write_file_atomic(uc_vm_t *vm, size_t nargs);

/* cache.c */
uc_value_t *uc_ubbf_cache_call(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_cache_invalidate(uc_vm_t *vm, size_t nargs);

/* coerce.c */
uc_value_t *uc_ubbf_to_bool(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_to_int(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_csv_to_list(uc_vm_t *vm, size_t nargs);

/* config.c */
uc_value_t *uc_ubbf_config_path_check(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_config_validate(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_config_restore_hook_set(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_config_restore(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_config_pins_take(uc_vm_t *vm, size_t nargs);

/* curl.c */
uc_value_t *uc_ubbf_curl_insecure_allowed(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_curl_exit_to_status(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_curl_download(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_curl_send(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_curl_upload(uc_vm_t *vm, size_t nargs);

/* dhcp.c */
uc_value_t *uc_ubbf_leases_parse(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ipv6_leases_by_mac(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ipv6_pool_clients_build(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_pool_leases_by_key(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_static_address_states(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_dhcp_option_value(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_hex_to_printable(uc_vm_t *vm, size_t nargs);

/* diag.c */
uc_value_t *uc_ubbf_curl_w_metrics_parse(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ping_output_parse(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_traceroute_output_parse(uc_vm_t *vm, size_t nargs);

/* dm.c */
uc_value_t *uc_ubbf_create(uc_vm_t *vm, size_t nargs);
void dm_register_type(uc_vm_t *vm);

/* ethtool.c */
uc_value_t *uc_ubbf_ethtool_properties_get(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ethtool_stats_get(uc_vm_t *vm, size_t nargs);

/* firewall.c */
uc_value_t *uc_ubbf_port_range_format(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_protocol_to_uci(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_chain_rules_ordered(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_firewall_set_resolve(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_chain_rule_set_matches(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_chain_rule_unsupported(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_firewall_rules_expired(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_firewall_expiry_next(uc_vm_t *vm, size_t nargs);

/* firewall_reconcile.c */
uc_value_t *uc_ubbf_firewall_reconcile(uc_vm_t *vm, size_t nargs);

/* gate.c */
uc_value_t *uc_ubbf_write_gate_create(uc_vm_t *vm, size_t nargs);
void write_gate_register_type(uc_vm_t *vm);

/* inet.c */
uc_value_t *uc_ubbf_ip_to_int(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_int_to_ip(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_cidr_to_netmask(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_netmask_to_cidr(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ipv4_addr_to_object(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ipv6_addr_to_object(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ipv6_prefix_to_object(uc_vm_t *vm, size_t nargs);

/* instance.c */
uc_value_t *uc_ubbf_enumerate_instances(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_get_by_instance(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_is_instance_key(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_count_instances(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_find_next_instance(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_collect_instances_for_pattern(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_entries_count_update(uc_vm_t *vm, size_t nargs);

/* log.c */
uc_value_t *uc_ubbf_log_init(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_log_debug(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_log_info(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_log_warn(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_log_err(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_log_exception(uc_vm_t *vm, size_t nargs);

/* mac.c */
uc_value_t *uc_ubbf_alias_from_mac(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_mac_is_valid(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_mac_normalise(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_mac_from_duid(uc_vm_t *vm, size_t nargs);

/* map.c */
uc_value_t *uc_ubbf_instance_map_own(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_instance_numbers(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_instance_numbers_known(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_instance_number(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_instance_prune(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_instance_key(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_instance_lookup(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_instance_rows(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_instance_items(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_instance_floor(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_instance_ids(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_instance_id_rows(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_instance_stack(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_instance_retire(uc_vm_t *vm, size_t nargs);

/* order.c */
uc_value_t *uc_ubbf_order_snapshot(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_orders_compute(uc_vm_t *vm, size_t nargs);

/* nptv6.c */
uc_value_t *uc_ubbf_prefix6_parse(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_prefix6_contains(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_nptv6_setting_check(uc_vm_t *vm, size_t nargs);

/* path.c */
uc_value_t *uc_ubbf_path_to_parts(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_navigate(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_pattern_matches_path(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ctx_config(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_tr181_ref_parse(uc_vm_t *vm, size_t nargs);

/* proc.c */
uc_value_t *uc_ubbf_cpu_stats(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_process_count(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_process_info(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_module_spawn(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_module_kill(uc_vm_t *vm, size_t nargs);

/* protocol.c */
uc_value_t *uc_ubbf_active_protocol(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_cwmp_mode(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_transfer_complete(uc_vm_t *vm, size_t nargs);

/* rtnl.c */
uc_value_t *uc_ubbf_link_local_addresses_get(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ra_prefixes_get(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_bridge_fdb_parse(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ipv6_neigh_parse(uc_vm_t *vm, size_t nargs);

/* routing.c */
uc_value_t *uc_ubbf_router_table_id(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_forwarding_policy_set(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_source_prefix(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_route_dest(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_prefix_intersect(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_source_tables(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_source_table_contents(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_source_rules(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_main_source_rules(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_policy_resolve(uc_vm_t *vm, size_t nargs);

/* schedule.c */
uc_value_t *uc_ubbf_start_time_valid(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_intervals_union(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_intervals_complement(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_schedule_intervals(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_intervals_to_windows(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_week_seconds(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_intervals_active(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_schedule_state(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_refs_intervals(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_schedule_windows(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_schedule_refs_check(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_schedule_refs_prune(uc_vm_t *vm, size_t nargs);

/* schema.c */
uc_value_t *uc_ubbf_schema_get(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_schema_defaults(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_schema_param_info(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_schema_extract(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_schema_entry_addable(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_schema_protocol_set(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_schema_version_set(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_schema_tables(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_schema_tables_load(uc_vm_t *vm, size_t nargs);

/* sfp.c */
uc_value_t *uc_ubbf_sfp_type_resolve(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_sfp_allowed(uc_vm_t *vm, size_t nargs);
void sfp_constants_add(uc_vm_t *vm, uc_value_t *scope);

/* hosts.c */
uc_value_t *uc_ubbf_hosts_leases_by_mac(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_hosts_ap_ssids(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ipv6_maps_merge(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_netifd_interfaces_build(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ap_by_ssid_instance(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_pool_client_paths(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_hosts_state_load(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_host_active_track(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_hosts_downstream_build(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_hosts_inactive_drop(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_hosts_state_flush(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_host_path_by_ip_find(uc_vm_t *vm, size_t nargs);

/* ifstats.c */
uc_value_t *uc_ubbf_ifstats_build(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ip_interface_members(uc_vm_t *vm, size_t nargs);

/* ipv6.c */
uc_value_t *uc_ubbf_prefix_length_nibble_check(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ra_prefixes_hook_read(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ipv6_prefix_rows_build(uc_vm_t *vm, size_t nargs);

/* dns.c */
uc_value_t *uc_ubbf_dns_learned_row(uc_vm_t *vm, size_t nargs);

/* ssh_keys.c */
uc_value_t *uc_ubbf_key_acceptable(uc_vm_t *vm, size_t nargs);

/* status.c */
uc_value_t *uc_ubbf_ifop_status_derive(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_bridge_status_derive(uc_vm_t *vm, size_t nargs);

/* string.c */
uc_value_t *uc_ubbf_shell_escape(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_alias_from_name(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_name_sanitise(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_uci_value_sanitise(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_text_clamp(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_cmd_build(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_transfer_url_validate(uc_vm_t *vm, size_t nargs);

/* sys.c */
uc_value_t *uc_ubbf_arch_get(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_apk_version(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_statvfs_info(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_deviceinfo_get(uc_vm_t *vm, size_t nargs);

/* sysfs.c */
uc_value_t *uc_ubbf_readfile_trim(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_readfile_int(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_uptime_read(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_link_properties_get(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ethernet_properties_get(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_arp_parse(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_hosts_merge(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_layer3_interface_find(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_host_primary_ip(uc_vm_t *vm, size_t nargs);

/* time.c */
uc_value_t *uc_ubbf_iso8601_format(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_datetime_format(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_usp_unix_to_datetime(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_usp_datetime_to_unix(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_iso8601_format_usec(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_iso8601_local_format(uc_vm_t *vm, size_t nargs);

/* tree.c */
uc_value_t *uc_ubbf_navigate_or_create(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_get(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_instances(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_enabled(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_interface_to_name(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_lower_layer_resolve(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ethernet_interface_path(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_upstream_interface_ref(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_lower_layers_wifi(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_port_snooped(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_tree_leaves(uc_vm_t *vm, size_t nargs);

/* uci_track.c */
uc_value_t *uc_ubbf_uci_change_update(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_uci_last_changed(uc_vm_t *vm, size_t nargs);

/* wifi.c */
uc_value_t *uc_ubbf_freq_to_channel(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_antenna_count(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_txpower_pct_to_dbm(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_wifi_operating_standard(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_standards_to_highest(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_standards_bandwidth_to_htmode(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_clamp_htmode(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_channel_width_to_bandwidth(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_band_to_uci(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_band_to_index(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_radio_address_derive(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_dscp_parse(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_qos_map_set_render(uc_vm_t *vm, size_t nargs);

/* wifi_dataelements.c */
uc_value_t *uc_ubbf_ht_caps_encode(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_vht_caps_encode(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_sta_he_caps_build(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_sta_he_caps_from_nl80211(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_sta_he_caps_from_flags(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_sta_he_caps_from_frame_body(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_chipset_vendor_get(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_radio_survey_build(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_radio_capability_build(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_local_sta_data_build(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_radio_band_priority(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_topology_devices_build(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_device_api_data_build(uc_vm_t *vm, size_t nargs);

/* wifi_phy.c */
uc_value_t *uc_ubbf_phy_max_standard(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_phy_supported_bandwidths(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_phy_max_bandwidth(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_phy_max_ssids(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_phy_max_bitrate(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_phy_max_txpower(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_phy_supported_bands(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_phy_supported_standards(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_phy_possible_channels(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_channel_valid_for_bandwidth(uc_vm_t *vm, size_t nargs);

/* wifi_psk.c */
uc_value_t *uc_ubbf_wpa_psk(uc_vm_t *vm, size_t nargs);

#endif /* UBBF_BINDINGS_H */
