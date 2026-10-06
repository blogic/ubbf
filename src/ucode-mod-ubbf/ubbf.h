/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#ifndef UBBF_H
#define UBBF_H

#include <ucode/lib.h>
#include <ucode/vm.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include <sys/stat.h>

int path_split(char *buf, char **parts, int max_parts);
bool path_resolve_aliases(uc_value_t *config, char **parts, int cnt,
			  char *slot_buf, size_t slot_stride, int slot_max);

bool key_is_instance(const char *key);
int count_instance_keys(uc_value_t *obj);
void do_find_nested_instances(uc_value_t *arr, const char *base_path,
			      uc_value_t *data, uc_vm_t *vm);
void do_collect_instances(uc_value_t *result, uc_value_t *pattern_parts,
			  uc_value_t *data, size_t parts_idx,
			  const char *current_path, uc_vm_t *vm);

uc_value_t *deep_clone_value(uc_vm_t *vm, uc_value_t *val);
uc_value_t *navigate_by_path(uc_vm_t *vm, uc_value_t *data, const char *path);

char *sysfs_read_file(const char *path);
char *netdev_read(const char *ifname, const char *file, const char *def);
const char *operstate_map(const char *state);
void str_to_upper(char *s);

/* utils.c */
uc_value_t *uc_ubbf_path_to_parts(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_navigate(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_match_pattern(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_pattern_matches_path(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_to_bool(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_to_int(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_csv_to_list(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ip_to_int(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_int_to_ip(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_cidr_to_netmask(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_netmask_to_cidr(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ipv6_expand(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ipv6_prefix_match(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_shell_escape(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_format_param_value(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_iso8601_format(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_iso8601_format_usec(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ctx_config(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ctx_parent(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_alias_from_mac(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_alias_from_name(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_enumerate_instances(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_get_by_instance(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_name_sanitise(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_uci_value_sanitise(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_mac_is_valid(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_transfer_url_validate(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_mac_normalise(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_mac_from_duid(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_tr181_ref_parse(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_to_int_positive(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_port_range_format(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_protocol_to_uci(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_freq_to_channel(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_antenna_count(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ipv6_lifetime_status(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_htmode_to_standard(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_htmode_to_bandwidth(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_tmpfile_name(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_write_file_atomic(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_counter_bump(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_rate_limit_check(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_wol_send(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_arch_get(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_apk_installed(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_statvfs_info(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_du_kib(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_mac_to_base64(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_int_to_hexbin(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_dscp_map_to_hex(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_bss_index_by_bssid(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ipv4_addr_to_object(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ipv6_addr_to_object(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ipv6_prefix_to_object(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_txpower_pct_to_dbm(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_wifi_operating_standard(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_led_read_info(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_cpu_stats(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_process_count(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_process_info(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_leases_parse(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_curl_w_metrics_parse(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_diag_result_expand(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ping_output_parse(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_traceroute_output_parse(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_usb_enumerate(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_usb_device_info(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_usb_interface_info(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_usb_net_interfaces(uc_vm_t *vm, size_t nargs);

/* tree.c */
uc_value_t *uc_ubbf_deep_clone(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_navigate_or_create(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_set_nested_value(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_get(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_instances(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_enabled(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_interface_to_name(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_lower_layer_resolve(uc_vm_t *vm, size_t nargs);

/* instance.c */
uc_value_t *uc_ubbf_is_instance_key(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_count_instances(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_find_next_instance(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_instance_num_extract(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_last_instance_idx(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_pattern_has_more_instances(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_find_nested_instances(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_collect_instances_for_pattern(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_get_parent_config(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_entries_count_update(uc_vm_t *vm, size_t nargs);

/* sysfs.c */
uc_value_t *uc_ubbf_readfile_trim(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_readfile_int(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_readfile_hex(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_uptime_read(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_operstate_to_status(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_link_properties_get(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ethernet_properties_get(uc_vm_t *vm, size_t nargs);

/* sysfs.c -- host discovery */
uc_value_t *uc_ubbf_arp_parse(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_bridge_fdb_parse(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_ipv6_neigh_parse(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_hosts_merge(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_layer3_interface_find(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_ubbf_host_primary_ip(uc_vm_t *vm, size_t nargs);

void ipv6_expand_to_buf(const char *addr, char *result);

/* dm.c */
uc_value_t *uc_ubbf_create(uc_vm_t *vm, size_t nargs);

void dm_register_type(uc_vm_t *vm);

#endif /* UBBF_H */
