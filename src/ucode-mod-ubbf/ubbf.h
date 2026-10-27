/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#ifndef UBBF_H
#define UBBF_H

#include <ucode/lib.h>
#include <ucode/vm.h>

#include "util.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include <sys/stat.h>

/* schema-gen.uc reads these defines to encode the parameter types. */
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

struct constval {
	const char *name;
	unsigned int value;
};

extern const struct constval dm_type_vals[];
extern const size_t dm_type_vals_count;
extern const struct constval routing_vals[];
extern const size_t routing_vals_count;
extern const struct constval curl_vals[];
extern const size_t curl_vals_count;

/* Capacity of the segment arrays that path_split() fills. */
#define PATH_PARTS_MAX		64
#define PATH_SPLIT_KEEP_EMPTY	0x1

/* atomic.c */
bool file_write_atomic(const char *path, const char *content, size_t len, mode_t mode);
bool tmpfile_create(const char *prefix, const char *ext, char *path, size_t len);

/* coerce.c */
bool value_to_bool(uc_value_t *val);
bool value_to_int(uc_value_t *val, int64_t *out);
bool loose_equal(uc_value_t *a, uc_value_t *b);
bool value_is(uc_value_t *val, const char *s);
bool value_loose_is(uc_value_t *val, const char *s);
bool value_int_cut(uc_value_t *val, int64_t *out);
uc_value_t *csv_list_new(uc_vm_t *vm, const char *csv, const char *filter_str);

/* config.c */
uc_value_t *config_pins_take(uc_vm_t *vm, uc_value_t *config);
char *config_content(uc_vm_t *vm, uc_value_t *config, uc_value_t *pins);
uc_value_t *sha256_new(const char *s);

/* diag.c */
uc_value_t *curl_metrics_new(uc_vm_t *vm, uc_value_t *data);

/* dhcp.c */
uc_value_t *leases_new(uc_vm_t *vm);

/* inet.c */
bool ipv4_parse(const char *s, uint32_t *out);
bool ip_prefix_match(const char *a, const char *b, int prefix);

/* instance.c */
bool key_is_instance(const char *key);
int64_t instance_next_free(uc_value_t *obj);
int instance_keys_count(uc_value_t *obj);
void entries_count_set(uc_value_t *parent, const char *table, uc_value_t *rows);
void nested_instances_find(uc_value_t *arr, const char *base_path,
			   uc_value_t *data, uc_vm_t *vm);
void instances_collect(uc_value_t *result, uc_value_t *pattern_parts,
		       uc_value_t *data, size_t parts_idx,
		       const char *current_path, uc_vm_t *vm);

/* log.c */
void ubbf_log_init(const char *ident);
void ubbf_log(int priority, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
void exception_log(uc_vm_t *vm, const char *where, uc_value_t *e);
bool exception_log_clear(uc_vm_t *vm, const char *where);

/* mac.c */
bool duid_mac_get(const char *s, size_t len, char mac[18]);

/* map.c */
int64_t instance_map_add_number(uc_vm_t *vm, const char *table, int64_t floor);
uc_value_t *instance_pins_new(uc_vm_t *vm, uc_value_t *config);
void instance_pins_seed(uc_vm_t *vm, uc_value_t *pins);

/* netlink.c */
struct nl_sock;
struct nl_msg;
bool nl_request_run(struct nl_sock *sock, struct nl_msg *msg,
		    int (*valid)(struct nl_msg *, void *), void *ctx);

/* path.c */
int path_split(char *buf, char **parts, int max_parts, unsigned int flags);
char *path_join(char **parts, int from, int to);
bool pattern_parts_match(char **pattern, char **parts, int cnt, bool numeric,
			 int64_t *inst);
uc_value_t *path_parts_new(uc_vm_t *vm, const char *path);
bool path_resolve_aliases(uc_value_t *config, char **parts, int cnt,
			  char *slot_buf, size_t slot_stride, int slot_max);
int64_t tr181_ref_instance(const char *path, const char *prefix);

/* proc.c */
char *spawn_output(char *const argv[], int *status);

/* protocol.c */
bool ubbf_cwmp_mode(void);

/* rtnl.c */
uc_value_t *ra_prefixes_new(uc_vm_t *vm, uc_value_t *dev);

/* schema.c */
uc_value_t *schema_entry_defaults(uc_vm_t *vm, uc_value_t *entry);
uc_value_t *schema_defaults_new(uc_vm_t *vm, const char *name);
uc_value_t *schema_entry_default(uc_vm_t *vm, uc_value_t *entry, const char *name);
bool schema_entry_member(uc_value_t *entry, const char *name, uint32_t *type);
bool schema_entry_hidden(uc_value_t *entry, const char *name);
uc_value_t *schema_entry_params(uc_vm_t *vm, uc_value_t *entry);
bool schema_entry_value_ok(uc_vm_t *vm, uc_value_t *entry, const char *name,
			  uc_value_t *value, char *why, size_t why_len);
bool schema_entry_addable(uc_value_t *entry);
bool schema_entry_max_instances(uc_value_t *entry, int64_t *max);

/* string.c */
void str_to_upper(char *s);
void shell_quote_append(uc_vm_t *vm, uc_stringbuf_t *sb, uc_value_t *val);

/* sys.c */
uc_value_t *deviceinfo_value(uc_vm_t *vm);

/* sysfs.c */
char *netdev_read(const char *ifname, const char *file, const char *def);
const char *operstate_map(const char *state);

/* time.c */
uc_value_t *unix_to_datetime_new(uc_value_t *ts);
bool datetime_utc_format(time_t t, int64_t usec, char *buf, size_t len);
bool datetime_parse(const char *s, int64_t *out);

/* tree.c */
uc_value_t *value_deep_clone(uc_vm_t *vm, uc_value_t *val);
uc_value_t *json_file_load(uc_vm_t *vm, const char *path);
uc_value_t *json_file_load_object(uc_vm_t *vm, const char *path);
void file_id(const char *path, char *buf, size_t len);
uc_value_t *navigate_by_path(uc_vm_t *vm, uc_value_t *data, const char *path);
uc_value_t *tree_node_get(uc_value_t *root, char **parts, int cnt);
uc_value_t *object_child_make(uc_vm_t *vm, uc_value_t *node, const char *key);
uc_value_t *tree_node_make(uc_vm_t *vm, uc_value_t *root, char **parts, int cnt);
uc_value_t *interface_name_get(uc_vm_t *vm, uc_value_t *config, uc_value_t *ref);
uc_value_t *lower_layer_name_get(uc_vm_t *vm, uc_value_t *config, const char *layers);
struct numkeys {
	size_t count;
	struct numkey { const char *name; int64_t n; } *list;
};
void numkeys_sorted(uc_value_t *table, struct numkeys *out);

/* vm.c */
uc_value_t *callback_call(uc_vm_t *vm, uc_value_t *this, uc_value_t *fn, size_t nargs,
			  uc_value_t **args);
uc_value_t *callback_invoke(uc_vm_t *vm, uc_value_t *fn, size_t nargs, ...);
uc_value_t *registry_get(uc_vm_t *vm, const char *key, uc_type_t type);

/* wifi.c */
#define WIFI_BANDWIDTHS 5
extern const char *const wifi_bandwidths[WIFI_BANDWIDTHS];
int64_t wifi_freq_channel(uc_value_t *val);
int wifi_antenna_count(uc_value_t *val);
const char *wifi_standard_highest(uc_vm_t *vm, uc_value_t *standards);

#endif /* UBBF_H */
