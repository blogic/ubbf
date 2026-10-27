/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"
#include "bindings.h"

/**
 * Reads and parses a JSON file.
 *
 * @param vm    ucode VM context
 * @param path  file to read
 * @return      parsed value, owned by the caller, or NULL when the file is
 *              missing, empty or not JSON
 */
uc_value_t *
json_file_load(uc_vm_t *vm, const char *path)
{
	struct json_tokener *tok;
	struct json_object *jobj;
	uc_value_t *parsed;
	FILE *fp;
	char *buf;
	long len;

	fp = fopen(path, "r");
	if (!fp)
		return NULL;

	fseek(fp, 0, SEEK_END);
	len = ftell(fp);
	fseek(fp, 0, SEEK_SET);

	if (len <= 0) {
		fclose(fp);
		return NULL;
	}

	buf = xalloc(len + 1);
	if ((long)fread(buf, 1, len, fp) != len) {
		free(buf);
		fclose(fp);
		return NULL;
	}

	buf[len] = '\0';
	fclose(fp);

	tok = json_tokener_new();
	if (!tok) {
		free(buf);
		return NULL;
	}

	/* the NUL ends a top-level number; anything but space after the value
	 * makes the file no JSON */
	jobj = json_tokener_parse_ex(tok, buf, len + 1);
	if (jobj && (json_tokener_get_error(tok) != json_tokener_success ||
		     buf[json_tokener_get_parse_end(tok) +
			 strspn(buf + json_tokener_get_parse_end(tok), " \t\r\n")] != '\0')) {
		json_object_put(jobj);
		jobj = NULL;
	}
	free(buf);
	json_tokener_free(tok);

	if (!jobj)
		return NULL;

	parsed = ucv_from_json(vm, jobj);
	json_object_put(jobj);

	return parsed;
}

/* ---- tree operations --------------------------------------------------- */

/**
 * Recursively deep-clones a ucode value.
 *
 * Objects and arrays are duplicated structurally; primitive values are
 * shared via reference count increment. The function does not detect
 * cycles, so circular structures will recurse until stack exhaustion.
 *
 * @param vm   ucode VM context
 * @param val  value to clone (may be NULL)
 * @return     new value owning a fresh reference, or NULL if `val` was NULL
 */
uc_value_t *
value_deep_clone(uc_vm_t *vm, uc_value_t *val)
{
	if (!val)
		return NULL;

	switch (ucv_type(val)) {
	case UC_OBJECT: {
		uc_value_t *clone = ucv_object_new(vm);

		ucv_object_foreach(val, key, child)
			ucv_object_add(clone, key, value_deep_clone(vm, child));

		return clone;
	}

	case UC_ARRAY: {
		size_t len = ucv_array_length(val);
		uc_value_t *clone = ucv_array_new_length(vm, len);

		for (size_t i = 0; i < len; i++)
			ucv_array_push(clone, value_deep_clone(vm, ucv_array_get(val, i)));

		return clone;
	}

	default:
		return ucv_get(val);
	}
}

/**
 * Walks an object by path-parts, creating intermediate objects as needed.
 *
 * Each missing or non-object child along the path is replaced with a new
 * empty object. Returns the resolved leaf object.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: data object, parts array)
 * @return       resolved object, or null on bad arguments
 */
uc_value_t *
uc_ubbf_navigate_or_create(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *data = uc_fn_arg(0);
	uc_value_t *parts = uc_fn_arg(1);
	uc_value_t *current;
	size_t i, plen;

	if (ucv_type(data) != UC_OBJECT || ucv_type(parts) != UC_ARRAY)
		return NULL;

	current = data;
	plen = ucv_array_length(parts);

	for (i = 0; i < plen; i++) {
		uc_value_t *part = ucv_array_get(parts, i);
		const char *key = ucv_string_get(part);

		if (!key)
			return NULL;

		current = object_child_make(vm, current, key);
	}

	return ucv_get(current);
}

/**
 * Loads a JSON file that holds an object.
 *
 * @param vm    ucode VM context
 * @param path  file path
 * @return      new reference to the object; an empty object when the file
 *              is missing, not JSON or holds something else
 */
uc_value_t *
json_file_load_object(uc_vm_t *vm, const char *path)
{
	uc_value_t *val = json_file_load(vm, path);

	if (ucv_type(val) == UC_OBJECT)
		return val;

	ucv_put(val);

	return ucv_object_new(vm);
}

/**
 * Identifies the content of a file by inode, modification time and size,
 * so a cache of the parsed file notices a rewrite.
 *
 * @param path  file path
 * @param buf   receives the identity, "" when the file is missing
 * @param len   size of buf
 */
void
file_id(const char *path, char *buf, size_t len)
{
	struct stat st;

	if (stat(path, &st) != 0) {
		buf[0] = '\0';
		return;
	}

	snprintf(buf, len, "%llu:%lld:%lld", (unsigned long long)st.st_ino,
		 (long long)st.st_mtime, (long long)st.st_size);
}

/* ---- data model helper functions --------------------------------------- */

/**
 * Walks a tree along path segments.
 *
 * @param root   root of the walk
 * @param parts  segments, each an object key
 * @param cnt    number of segments to walk
 * @return       the node (borrowed), `root` for no segments, or NULL when a
 *               segment is missing or a value on the way is no object
 */
uc_value_t *
tree_node_get(uc_value_t *root, char **parts, int cnt)
{
	for (int i = 0; i < cnt && root; i++)
		root = ucv_object_get(root, parts[i], NULL);

	return root;
}

/**
 * Returns the object child of a node, made new when the key is missing or
 * holds no object.
 *
 * @param vm    ucode VM context
 * @param node  object to look in
 * @param key   child name
 * @return      the child (borrowed)
 */
uc_value_t *
object_child_make(uc_vm_t *vm, uc_value_t *node, const char *key)
{
	uc_value_t *child = ucv_object_get(node, key, NULL);

	if (ucv_type(child) != UC_OBJECT) {
		child = ucv_object_new(vm);
		ucv_object_add(node, key, child);
	}

	return child;
}

/**
 * Walks a tree along path segments with object_child_make(), so that every
 * object on the way exists afterwards.
 *
 * @param vm     ucode VM context
 * @param root   root object of the walk
 * @param parts  segments
 * @param cnt    number of segments to walk
 * @return       the object at the end (borrowed)
 */
uc_value_t *
tree_node_make(uc_vm_t *vm, uc_value_t *root, char **parts, int cnt)
{
	for (int i = 0; i < cnt; i++)
		root = object_child_make(vm, root, parts[i]);

	return root;
}

/**
 * Resolves a value in a nested object by a dotted TR-181 path string.
 *
 * The path is split with `path_split()` (so a leading and a trailing dot
 * are tolerated) and then each segment is looked up as an object key.
 * Returns a borrowed reference into the input tree.
 *
 * @param vm    ucode VM context
 * @param data  root object to navigate
 * @param path  dotted path string
 * @return      resolved value (borrowed), or NULL on missing or bad
 *              arguments or an invalid path
 */
uc_value_t *
navigate_by_path(uc_vm_t *vm, uc_value_t *data, const char *path)
{
	char *buf, *parts[PATH_PARTS_MAX];
	uc_value_t *current;
	int cnt;

	if (!path || !*path || ucv_type(data) != UC_OBJECT)
		return NULL;

	buf = xstrdup(path);
	cnt = path_split(buf, parts, PATH_PARTS_MAX, 0);
	if (cnt < 0) {
		free(buf);
		return NULL;
	}

	current = tree_node_get(data, parts, cnt);

	free(buf);
	return current;
}

/**
 * Retrieves the value at a TR-181 path within a configuration tree.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: config object, path string)
 * @return       value at the path, or null when missing
 */
uc_value_t *
uc_ubbf_get(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *config = uc_fn_arg(0);
	uc_value_t *path_val = uc_fn_arg(1);
	uc_value_t *result;

	if (ucv_type(path_val) != UC_STRING)
		return NULL;

	result = navigate_by_path(vm, config, ucv_string_get(path_val));

	return result ? ucv_get(result) : NULL;
}

/**
 * Returns the instances of a TR-181 multi-instance object as an array.
 *
 * Each returned entry is the config of an instance key decorated with
 * `.instance` (the key) and `.path` (the fully qualified path, without a
 * trailing dot of the table path). Note that the decoration mutates the
 * underlying config object in place.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: config object, path string)
 * @return       array of instance objects, possibly empty
 */
uc_value_t *
uc_ubbf_instances(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *config = uc_fn_arg(0);
	uc_value_t *path_val = uc_fn_arg(1);
	uc_value_t *data, *arr;
	const char *path;
	char *row_path;
	size_t len;

	if (ucv_type(path_val) != UC_STRING)
		return ucv_array_new(vm);

	path = ucv_string_get(path_val);
	data = navigate_by_path(vm, config, path);

	if (ucv_type(data) != UC_OBJECT)
		return ucv_array_new(vm);

	arr = ucv_array_new(vm);

	len = strlen(path);
	if (len && path[len - 1] == '.')
		len--;

	ucv_object_foreach(data, key, inst_config) {
		if (!key_is_instance(key) || ucv_type(inst_config) != UC_OBJECT)
			continue;

		xasprintf(&row_path, "%.*s.%s", (int)len, path, key);
		ucv_object_add(inst_config, ".instance", ucv_string_new(key));
		ucv_object_add(inst_config, ".path", ucv_string_new(row_path));
		ucv_array_push(arr, ucv_get(inst_config));
		free(row_path);
	}

	return arr;
}

/**
 * Reports whether a value at a TR-181 path is truthy.
 *
 * Booleans pass through; strings are truthy when equal to `"true"` or `"1"`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: config object, path string)
 * @return       boolean truthiness of the resolved value
 */
uc_value_t *
uc_ubbf_enabled(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *config = uc_fn_arg(0);
	uc_value_t *path_val = uc_fn_arg(1);
	uc_value_t *value;

	if (ucv_type(path_val) != UC_STRING)
		return ucv_boolean_new(false);

	value = navigate_by_path(vm, config, ucv_string_get(path_val));

	return ucv_boolean_new(value_to_bool(value));
}

static int
numkey_cmp(const void *a, const void *b)
{
	const struct numkey *ka = a, *kb = b;

	return (ka->n > kb->n) - (ka->n < kb->n);
}

/**
 * Lists the keys of a table that are all digits, leading zeros included,
 * ascending by number: the order of `sort(keys)` with a numeric compare in
 * ucode. The names point into the table, which must not change while they
 * are used.
 *
 * @param table  table object, or anything else for no keys
 * @param out    receives the keys; the caller frees out->list
 */
void
numkeys_sorted(uc_value_t *table, struct numkeys *out)
{
	out->count = 0;
	out->list = xcalloc(ucv_object_length(table) + 1, sizeof(*out->list));

	ucv_object_foreach(table, key, val) {
		(void)val;
		if (!*key || strspn(key, "0123456789") != strlen(key))
			continue;

		out->list[out->count].name = key;
		out->list[out->count++].n = strtoll(key, NULL, 10);
	}

	qsort(out->list, out->count, sizeof(*out->list), numkey_cmp);
}

/**
 * Resolves a TR-181 interface reference to the `Name` of the referenced
 * object.
 *
 * @param vm      ucode VM context
 * @param config  configuration tree
 * @param ref     reference path
 * @return        the Name (borrowed), or NULL when the reference is no
 *                string or names no object
 */
uc_value_t *
interface_name_get(uc_vm_t *vm, uc_value_t *config, uc_value_t *ref)
{
	uc_value_t *data;

	if (ucv_type(ref) != UC_STRING)
		return NULL;

	data = navigate_by_path(vm, config, ucv_string_get(ref));

	return (ucv_type(data) == UC_OBJECT) ? ucv_object_get(data, "Name", NULL) : NULL;
}

/**
 * Resolves a TR-181 interface reference to its system interface name, see
 * interface_name_get().
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: config, reference path)
 * @return       Name string, or null when the reference is missing
 */
uc_value_t *
uc_ubbf_interface_to_name(uc_vm_t *vm, size_t nargs)
{
	return ucv_get(interface_name_get(vm, uc_fn_arg(0), uc_fn_arg(1)));
}

/**
 * Resolves the first entry of a TR-181 LowerLayers CSV to a system name.
 *
 * Strips leading spaces from the first comma-separated reference,
 * navigates `config`, and returns the `Name` of the referenced object.
 *
 * @param vm      ucode VM context
 * @param config  data tree
 * @param layers  LowerLayers string
 * @return        Name value (borrowed), or NULL when no reference resolves
 */
uc_value_t *
lower_layer_name_get(uc_vm_t *vm, uc_value_t *config, const char *layers)
{
	char *buf, *comma, *ref;
	uc_value_t *data;

	if (!layers || !*layers)
		return NULL;

	buf = xstrdup(layers);
	comma = strchr(buf, ',');
	if (comma)
		*comma = '\0';

	ref = buf;
	while (*ref == ' ')
		ref++;

	data = navigate_by_path(vm, config, ref);
	free(buf);

	if (ucv_type(data) != UC_OBJECT)
		return NULL;

	return ucv_object_get(data, "Name", NULL);
}

/**
 * ucode: `lower_layer_resolve(config, lower_layers)`, see
 * lower_layer_name_get().
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: config, LowerLayers string)
 * @return       Name string, or null when no reference resolves
 */
uc_value_t *
uc_ubbf_lower_layer_resolve(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *layers = uc_fn_arg(1);

	if (ucv_type(layers) != UC_STRING)
		return NULL;

	return ucv_get(lower_layer_name_get(vm, uc_fn_arg(0), ucv_string_get(layers)));
}

/**
 * Returns the Device.Ethernet.Interface row of a netdev, the reverse of
 * interface_to_name() for a layer 1 interface.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: root, netdev name)
 * @return       row path, or '' when no row has that Name
 */
uc_value_t *
uc_ubbf_ethernet_interface_path(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *netdev = uc_fn_arg(1);
	uc_value_t *rows, *name, *rv;
	char *path;

	if (ucv_type(netdev) != UC_STRING || !*ucv_string_get(netdev))
		return ucv_string_new("");

	rows = navigate_by_path(vm, uc_fn_arg(0), "Device.Ethernet.Interface");
	if (ucv_type(rows) != UC_OBJECT)
		return ucv_string_new("");

	ucv_object_foreach(rows, key, row) {
		if (!key_is_instance(key) || ucv_type(row) != UC_OBJECT)
			continue;

		name = ucv_object_get(row, "Name", NULL);
		if (ucv_type(name) != UC_STRING ||
		    strcmp(ucv_string_get(name), ucv_string_get(netdev)))
			continue;

		xasprintf(&path, "Device.Ethernet.Interface.%s", key);
		rv = ucv_string_new(path);
		free(path);

		return rv;
	}

	return ucv_string_new("");
}

/* An absent Enable keeps the interface enabled. */
static bool
upstream_iface_active(uc_value_t *iface)
{
	uc_value_t *enable = ucv_object_get(iface, "Enable", NULL);

	return ucv_type(iface) == UC_OBJECT &&
	       value_to_bool(ucv_object_get(iface, "Upstream", NULL)) &&
	       (!enable || value_to_bool(enable));
}

/**
 * Returns the path of the upstream Device.IP.Interface: the first enabled
 * upstream interface with NAT (an enabled Device.NAT.InterfaceSetting),
 * else the first enabled upstream interface. upnpd serves the external
 * address of this interface, and the runtime rows of UPnP (mappings and
 * pinholes) reference it as their Interface.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: root config data)
 * @return       Device.IP.Interface.{i} path, or null
 */
uc_value_t *
uc_ubbf_upstream_interface_ref(uc_vm_t *vm, size_t nargs)
{
	static const char prefix[] = "Device.IP.Interface.";
	uc_value_t *root = uc_fn_arg(0);
	uc_value_t *ifaces = navigate_by_path(vm, root, "Device.IP.Interface");
	uc_value_t *settings = navigate_by_path(vm, root, "Device.NAT.InterfaceSetting");
	uc_value_t *ref, *rv;
	const char *key;
	char *path;

	if (ucv_type(ifaces) != UC_OBJECT)
		return NULL;

	ucv_object_foreach(settings, skey, ifs) {
		(void)skey;
		ref = ucv_object_get(ifs, "Interface", NULL);
		if (ucv_type(ifs) != UC_OBJECT ||
		    !value_to_bool(ucv_object_get(ifs, "Enable", NULL)) ||
		    ucv_type(ref) != UC_STRING ||
		    strncmp(ucv_string_get(ref), prefix, sizeof(prefix) - 1))
			continue;

		key = ucv_string_get(ref) + sizeof(prefix) - 1;
		if (!*key || key[strspn(key, "0123456789")])
			continue;

		if (upstream_iface_active(ucv_object_get(ifaces, key, NULL)))
			return ucv_get(ref);
	}

	ucv_object_foreach(ifaces, ikey, iface) {
		if (!upstream_iface_active(iface))
			continue;

		xasprintf(&path, "%s%s", prefix, ikey);
		rv = ucv_string_new(path);
		free(path);

		return rv;
	}

	return NULL;
}

/**
 * Reports whether the lower layers of a bridge port are WiFi SSIDs only.
 * The wireless configuration adds such a port to the bridge, not netifd.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: comma-separated lower
 *               layer references)
 * @return       true when every reference is a WiFi SSID
 */
uc_value_t *
uc_ubbf_lower_layers_wifi(uc_vm_t *vm, size_t nargs)
{
	static const char prefix[] = "Device.WiFi.SSID.";
	uc_value_t *layers = uc_fn_arg(0);
	uc_value_t *refs, *ref;
	const char *num;
	bool wifi;

	if (ucv_type(layers) != UC_STRING || !*ucv_string_get(layers))
		return ucv_boolean_new(false);

	refs = csv_list_new(vm, ucv_string_get(layers), "-1");
	wifi = true;

	for (size_t i = 0; wifi && i < ucv_array_length(refs); i++) {
		ref = ucv_array_get(refs, i);
		num = ucv_string_get(ref);

		if (strncmp(num, prefix, sizeof(prefix) - 1)) {
			wifi = false;
			continue;
		}

		num += sizeof(prefix) - 1;
		wifi = *num && !num[strspn(num, "0123456789")];
	}

	ucv_put(refs);

	return ucv_boolean_new(wifi);
}

/**
 * Reports whether a bridge port keeps multicast snooping: IGMP and MLD both
 * true. A row stored before TR-181 2.21 has neither value and keeps the
 * snooping it had.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: bridge port row)
 * @return       true when the port is snooped
 */
uc_value_t *
uc_ubbf_port_snooped(uc_vm_t *vm, size_t nargs)
{
	static const char *const names[] = { "IGMP", "MLD" };
	uc_value_t *port = uc_fn_arg(0);
	uc_value_t *val;

	for (size_t i = 0; i < ARRAY_SIZE(names); i++) {
		val = ucv_object_get(port, names[i], NULL);
		if (val && !value_to_bool(val))
			return ucv_boolean_new(false);
	}

	return ucv_boolean_new(true);
}

static void
leaves_add(uc_vm_t *vm, uc_value_t *node, const char *prefix, uc_value_t *out)
{
	char *full;

	ucv_object_foreach(node, key, val) {
		if (key[0] == '.')
			continue;

		if (ucv_type(val) == UC_OBJECT) {
			xasprintf(&full, "%s%s.", prefix, key);
			leaves_add(vm, val, full, out);
		} else {
			xasprintf(&full, "%s%s", prefix, key);
			ucv_object_add(out, full, ucv_get(val));
		}

		free(full);
	}
}

/**
 * Flattens a subtree into leaf paths. Keys beginning with a dot are the
 * metadata of the tree, not parameters.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (3 expected: subtree, path prefix with
 *               the trailing dot, object that receives `<path>: <value>`)
 * @return       null
 */
uc_value_t *
uc_ubbf_tree_leaves(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *prefix = uc_fn_arg(1);
	uc_value_t *out = uc_fn_arg(2);

	if (ucv_type(out) == UC_OBJECT)
		leaves_add(vm, uc_fn_arg(0), ucv_type(prefix) == UC_STRING ? ucv_string_get(prefix) : "", out);

	return NULL;
}
