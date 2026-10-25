# TR-181 Handler Module Guidelines

This document gives the rules for TR-181 handler modules in `files/usr/share/ucode/ubbf/tr181/`. Use it when you write or review handler code.

An out-of-tree module in `modules/<name>/` follows the same rules for data and types. It cannot use `import`. It gets its helpers from `ubbf_module` instead. Read "Out-of-tree modules" in `ARCHITECTURE.md` before you write one.

## File Structure

A handler module must use this structure:

```ucode
'use strict';

// 1. Imports (grouped by type)
import * as fs from 'fs';
import * as ubbf from 'ubbf';
import { utility_function } from 'ubbf.utils.<utility>';

// 2. Constants (if any)
const SOME_PATH = '/path/to/resource';

// 3. Private helper functions (converter functions first, then data fetchers)
function item_to_object(item) { ... }
function data_fetch() { ... }

// 4. Get handlers
function container_get(ctx) { ... }
function instance_get(ctx) { ... }

// 5. Set handlers (if any)
function instance_set(ctx) { ... }

// 6. Operation handlers (if any)
function operation_handler(input, instance, complete, command_key, root) { ... }

// 7. Model export (last, before the operations export)
export const model = { ... };

// 8. Operations export (if any)
export const operations = { ... };
```

## Import Ordering

Put the imports in two groups, in this order:

1. Standard ucode modules (`fs`, `uloop`, `ubus`, `uci`).
2. Project code: the native `ubbf` module, `ubbf.utils.*` and other `ubbf.*` modules.

The order inside a group is free. A handler does not import `ubbf.schemas.*`: it names its schemas with strings (see "Model Export Structure").

```ucode
// CORRECT
import * as uloop from 'uloop';
import * as fs from 'fs';
import * as ubus from 'ubus';
import * as ubbf from 'ubbf';
import { netifd_status_get } from 'ubbf.utils.netifd';

// WRONG - a project utility between two standard modules
import * as fs from 'fs';
import { netifd_status_get } from 'ubbf.utils.netifd';
import * as ubus from 'ubus';
```

## Mandatory Helpers

### The native `ubbf` module

The C module `ubbf` (`src/ucode-mod-ubbf/`) supplies the helpers for enumeration, aliases and file reads. The function table `module_fns` in `src/ucode-mod-ubbf/ubbf.c` lists all of them.

```ucode
import * as ubbf from 'ubbf';
```

### Enumerate Pattern

If a handler supports enumerate mode (`ctx.instance == null`), it must use `ubbf.enumerate_instances()` and `ubbf.get_by_instance()`. Source: `src/ucode-mod-ubbf/instance.c`.

`ubbf.enumerate_instances(items, converter)`:

- `items`: an array of raw data items.
- `converter`: a function `(item, index)` that returns the TR-181 object. `index` starts at 0.
- Returns an object with the keys `"1"`, `"2"` and so on.
- Returns an empty object `{}` if `items` is not an array or `converter` is not callable.

`ubbf.get_by_instance(items, instance)`:

- `items`: an array of raw data items.
- `instance`: the 1-based instance number from `ctx.instance`.
- Returns the item at position `instance - 1`, or `null` if the position is out of range.

### File Reads

For small text files, for example in sysfs, use the readers of the native module. Source: `src/ucode-mod-ubbf/sysfs.c`.

| Function | Returns |
|----------|---------|
| `ubbf.readfile_trim(path, default)` | The trimmed content, or `default` |
| `ubbf.readfile_int(path, default)` | The content as a base-10 integer, or `default` (0 if not given) |
| `ubbf.uptime_read()` | The seconds from `/proc/uptime` as an integer, or 0 |

### Interface Statistics

For network interface statistics, you must use the existing utility:

```ucode
import { ifstats_get, ifstats_reset } from 'ubbf.utils.ifstats';
```

`ifstats_get(ifname)` returns a complete TR-181 `Stats` object from the `udevstats` counters. `ifstats_reset(ifname)` sets these counters to zero for the netdev. Do not read the sysfs counters directly. See "Interface counters" in `ARCHITECTURE.md`.

### Netifd Status

For the status of a netifd interface:

```ucode
import { netifd_status_get } from 'ubbf.utils.netifd';
```

`netifd_status_get(name)` calls `network.interface.<name> status` on each call. It does not use the cache.

### Alias Generation

For an Alias that the device generates, use `ubbf.alias_from_mac()` or `ubbf.alias_from_name()`.

`ubbf.alias_from_mac(mac)` (`src/ucode-mod-ubbf/mac.c`):

- `mac`: a MAC address string, for example `"04:7C:16:5D:B5:2C"`.
- Returns the `cpe-` prefix followed by the MAC in lower case without colons, for example `"cpe-047c165db52c"`.
- Returns an empty string if `mac` is not a string or is empty.

`ubbf.alias_from_name(name)` (`src/ucode-mod-ubbf/string.c`):

- `name`: any string identifier, for example `"device:green:power"`.
- Returns the `cpe-` prefix followed by the name. Each character outside `[A-Za-z0-9_-]` becomes `_`.
- Returns an empty string if `name` is not a string or is empty.

TR-181 requirements for an Alias (data type `Alias` in `dm/spec/tr-181-2-19-0-usp-full.xml`):

- The value must not be empty.
- The value must start with a letter.
- The value is a unique key for the instance.
- If the controller does not assign a value at creation time, the agent must assign a value with the `cpe-` prefix.

| Source data | Function | Example input | Example output |
|-------------|----------|---------------|----------------|
| MAC address | `alias_from_mac` | `"04:7C:16:5D:B5:2C"` | `"cpe-047c165db52c"` |
| LED name | `alias_from_name` | `"device:green:power"` | `"cpe-device_green_power"` |
| USB device | `alias_from_name` | `"1-2.1"` | `"cpe-1-2_1"` |
| Interface name | `alias_from_name` | `"eth0"` | `"cpe-eth0"` |

If the source is only an index, use `sprintf()` for a sequential Alias:

```ucode
Alias: sprintf('cpe-processor%d', idx + 1)     // tr181/DeviceInfo/Processor.uc
Alias: sprintf('cpe-Stack%d', index)           // tr181/InterfaceStack.uc
Alias: sprintf('cpe-config%d', instance)       // tr181/DeviceInfo/VendorConfigFile.uc
```

## Enumerate Mode Pattern

### Correct Pattern

```ucode
function item_to_object(item) {
    return {
        Property1: item.field1 ?? '',
        Property2: sprintf('%d', item.field2 ?? 0)
    };
}

function instance_get(ctx) {
    let items = data_fetch();

    if (ctx.instance == null)
        return ubbf.enumerate_instances(items, item_to_object);

    let item = ubbf.get_by_instance(items, ctx.instance);
    if (!item)
        return null;

    return item_to_object(item);
}
```

Source: `led_get()` in `modules/leds/handler.uc`.

### Converter with Additional Context

If the converter needs external data, for example a configuration or a parent context, create a closure:

```ucode
function item_to_object(item, config) {
    return {
        Property1: item.field1,
        ConfigValue: config.some_value
    };
}

function instance_get(ctx) {
    let config = config_load();
    let items = data_fetch();
    let to_object = (item) => item_to_object(item, config);

    if (ctx.instance == null)
        return ubbf.enumerate_instances(items, to_object);

    let item = ubbf.get_by_instance(items, ctx.instance);
    if (!item)
        return null;

    return to_object(item);
}
```

### Converter with Index

`ubbf.enumerate_instances()` gives the 0-based index to the converter as the second argument:

```ucode
function item_to_object(item, idx) {
    return {
        Alias: sprintf('cpe-item%d', idx + 1),
        Value: item.value
    };
}

function instance_get(ctx) {
    let items = data_fetch();

    if (ctx.instance == null)
        return ubbf.enumerate_instances(items, item_to_object);

    let item = ubbf.get_by_instance(items, ctx.instance);
    if (!item)
        return null;

    return item_to_object(item, ctx.instance - 1);
}
```

### When Not to Use the Enumerate Helpers

The enumerate helpers make sequential 1-based keys (`"1"`, `"2"`, `"3"`). Do not use them in these cases:

1. The keys are identifiers, for example the PIDs in `ProcessStatus`.
2. The keys are not sequential, for example CPU numbers from `/proc/stat`.
3. The code counts instances in nested containers.
4. The code searches for an item by name or by another criterion.

```ucode
// ProcessStatus uses PIDs as keys (tr181/DeviceInfo/ProcessStatus.uc)
let result = {};
for (let pid in pids)
    result[sprintf('%d', pid)] = process_to_object(pid);
```

### Forbidden Pattern

Do not write a manual loop for sequential instance numbers:

```ucode
// WRONG
function instance_get(ctx) {
    let items = data_fetch();

    if (ctx.instance == null) {
        let result = {};
        for (let i = 0; i < length(items); i++)
            result[sprintf('%d', i + 1)] = item_to_object(items[i]);
        return result;
    }

    let idx = ctx.instance - 1;
    if (idx < 0 || idx >= length(items))
        return null;

    return item_to_object(items[idx]);
}
```

## Container Get Pattern

If a container object returns its child instances inline:

```ucode
function container_get(ctx) {
    let items = data_fetch();

    return {
        ChildNumberOfEntries: sprintf('%d', length(items)),
        Child: ubbf.enumerate_instances(items, child_to_object)
    };
}
```

A table can have its own `{i}` handler and no stored rows. In this case the dispatcher writes `<Child>NumberOfEntries` on the parent, if the parent schema declares that key. `subtree_dispatch()` in `src/ucode-mod-ubbf/dm_get.c` counts the rows after the model walk. The parent handler does not need to calculate the count. This also covers a module table under a core parent, where the module cannot change the parent handler.

## Converter Functions

### Naming Convention

A converter function must have the name `<singular_noun>_to_object`:

- `address_to_object` (`modules/hosts/handler.uc`)
- `port_to_object` (`modules/lldp/handler.uc`)
- `lease_to_client` (`tr181/DHCPv4.uc`): permitted when the target differs from the source.

Do not use names such as `build_host` or `convert_host`.

### Structure

A converter function must:

1. Take the raw item as the first parameter.
2. Optionally take the index as the second parameter.
3. Return a plain object with TR-181 parameter names.
4. Use `??` for default values.
5. Use `sprintf('%d', ...)` to convert numbers to strings.

```ucode
function device_to_object(dev) {
    return {
        Name: dev.name ?? '',
        Status: dev.active ? 'Active' : 'Inactive',
        ByteCount: sprintf('%d', dev.bytes ?? 0),
        Enable: dev.enabled ? 'true' : 'false'
    };
}
```

### Nested Instances

If a converter builds nested instance collections:

```ucode
function port_to_object(port) {
    return {
        PortID: port.id,
        TTL: sprintf('%d', port.ttl)
    };
}

function device_to_object(dev) {
    return {
        Name: dev.name,
        PortNumberOfEntries: sprintf('%d', length(dev.ports)),
        Port: ubbf.enumerate_instances(dev.ports, port_to_object)
    };
}
```

## Data Fetch Functions

### Naming Convention

- `<plural>_fetch()` or `<plural>_get()` for collections.
- `<singular>_status_get()` for status queries.
- `config_load()` for configuration.

### Cache for Expensive Calls

An expensive call can occur more than once in one request, for example a ubus call or an iwinfo query. For such a call, use the cache of `ubbf.so` (`ubbf_module.ubbf.cache_call` in a module):

```ucode
import { cache_call } from 'ubbf';
```

`cache_call(fn, ...args)` returns the result of `fn(...args)` and keeps it for 2 seconds. The first call that stores a result starts a 2-second timer. When the timer expires, the complete cache clears. There is no expiry per entry.

The cache key is the function itself and the arguments. Pass a function that you declare at the top level of the file. A function expression in the call is a new function each time, so it never finds its result in the cache.

Write an uncached `*_fetch()` function. Then export a cached `*_get()` function that calls it through `cache_call()`:

```ucode
/**
 * Fetches WiFi association list for an interface (uncached).
 *
 * @param {string} ifname - Interface name
 * @returns {object} Station associations keyed by MAC address
 */
function assoclist_fetch(ifname) {
	iwinfo_update();
	if (!iwinfo.ifaces?.[ifname])
		return {};
	return iwinfo.assoclist(ifname);
}

/**
 * Gets WiFi association list for an interface (cached).
 *
 * @param {string} ifname - Interface name
 * @returns {object} Station associations keyed by MAC address
 */
export function assoclist_get(ifname) {
	return cache_call(assoclist_fetch, ifname);
};
```

Source: `utils/wifi.uc`.

Use the cache for these calls:

- ubus calls, for example `network.wireless status` and `dhcp ipv6leases`.
- iwinfo queries, for example `iwinfo.assoclist` and `iwinfo.update`.
- Sysfs reads that occur more than once in one walk of the data model.

Cached functions in the code:

- `utils/wifi.uc`: `wireless_status_get()`, `phys_get()`
- `utils/wifi_iwinfo.uc`: `assoclist_get()`, `iwinfo_update()`. iwinfo calls hostapd when it loads, so no render template may import this module.
- `utils/dhcp.uc`: `dhcpsnoop_dump_get()`, `ipv6_leases_get()`, `ipv6_leases_raw_get()`

### Error Handling

If a fetch fails, return an empty array `[]` or `null`. Do not throw:

```ucode
function devices_fetch() {
    let result = ubus?.call('service', 'list', {});
    if (!result?.devices)
        return [];
    return result.devices;
}
```

## Handler Functions

### Get Handlers

The dispatcher calls a get handler with the context `{ instance, config, parent, root }`. Source: `get_handler_call()` in `src/ucode-mod-ubbf/dm_get.c`.

| Field | Content |
|-------|---------|
| `ctx.instance` | The instance number as an integer, or `null` in enumerate mode |
| `ctx.instances` | The instance numbers of the path as integers, outermost first, for example `[ 2, 1 ]` for `Button.2.TriggerCondition.1`. In enumerate mode, those of the parent rows. A handler below a row learns from it which row it serves |
| `ctx.config` | The stored configuration of this instance |
| `ctx.parent` | The stored configuration of the parent instance: for `X.{i}.Y` and for a table `X.{i}.Y.{i}`, the row `X.{i}`. A table with no `{i}` above it gets its container |
| `ctx.root` | The runtime tree |

```ucode
function instance_get(ctx) {
    if (!ctx.config)
        return null;

    let status = status_fetch(ctx.config.Name);

    return {
        ...ctx.config,
        Status: status?.up ? 'Up' : 'Down',
        RuntimeProperty: status?.value ?? ''
    };
}
```

### Set Handlers

The dispatcher stores the new value first. Then it calls the set handler with the context `{ path, param, value, instance, config, root }`. Source: `set_handler_invoke()` and `uc_dm_params_set()` in `src/ucode-mod-ubbf/dm_set.c`.

| Field | Content |
|-------|---------|
| `ctx.path` | The full parameter path |
| `ctx.param` | The name of the parameter |
| `ctx.value` | The new value |
| `ctx.instance` | The last instance number in the path, or `null` |
| `ctx.config` | The stored configuration of the object |
| `ctx.root` | The configuration tree that the write changes |

To reject the write, return a negative integer. The dispatcher then restores the previous value. Any other return value accepts the write.

A writable parameter in a table that the CPE maintains (`addable: false` or `maxInstances: 0` on the entry, or `addable: false` or `max_instances: 0` on the schema) needs `runtime_instances` and `writable_rows` on the entry (see "Runtime Rows Next to Persisted Rows"), or a set handler, or the write fails with 7020: the dispatcher does not store a row that only a get handler makes. See "Tables under a core parent" in `ARCHITECTURE.md`.

```ucode
function pool_set(ctx) {
    if (ctx.param == 'IAPDAddLength') {
        if (ctx.value == null || ctx.value == '')
            return 0;
        if (!prefix_length_nibble_check(ctx.value)) {
            log_err('DHCPv6 Pool.IAPDAddLength must be 0 or a multiple of 4, got %s', ctx.value);
            return -1;
        }
    }
    return 0;
}

export const model = {
    'Device.DHCPv6.Server.Pool.{i}': {
        schema: 'DHCPv6.Server_Pool',
        get: pool_get,
        set: pool_set
    }
};
```

Source: `pool_set()` in `tr181/DHCPv6.uc`. A set handler can also change other parts of `ctx.root`. For an example, see `easymesh_controller_set()` in `modules/easymesh/x_ubbf_easymesh.uc`.

### Parent Access

If a handler needs the parent context:

```ucode
function child_get(ctx) {
    let parent = ctx.parent ?? ctx.config;
    if (!parent?.Name)
        return null;

    let data = data_fetch_for(parent.Name);
    // ...
}
```

### Stats Handlers

For interface statistics, find the device name. Then use the utility:

```ucode
import { ifstats_get } from 'ubbf.utils.ifstats';

function stats_get(ctx) {
    let parent = ctx.parent ?? ctx.config;
    if (!parent?.Name)
        return null;

    let status = netifd_status_get(parent.Name);
    let device = status?.l3_device ?? status?.device;
    if (!device)
        return null;

    return ifstats_get(device);
}
```

## Nesting and Control Flow

A handler function must not have more than 3 levels of indentation. Use these methods to decrease the nesting.

### Early Returns

```ucode
// CORRECT
function handler(ctx) {
    if (!ctx.config)
        return null;
    if (!ctx.config.Name)
        return null;

    let data = fetch(ctx.config.Name);
    if (!data)
        return null;

    return build_result(data);
}

// WRONG
function handler(ctx) {
    if (ctx.config) {
        if (ctx.config.Name) {
            let data = fetch(ctx.config.Name);
            if (data) {
                return build_result(data);
            }
        }
    }
    return null;
}
```

### Continue in Loops

```ucode
// CORRECT
for (let item in items) {
    if (!item.valid)
        continue;
    if (item.type != 'target')
        continue;

    process(item);
}

// WRONG
for (let item in items) {
    if (item.valid) {
        if (item.type == 'target') {
            process(item);
        }
    }
}
```

### Helper Functions

If a loop body is complex, move it into a helper function:

```ucode
function child_process(child) {
    if (!child.active)
        return;
    if (child.type != 'target')
        return;
    process(child);
}

for (let a in items) {
    if (!a.valid)
        continue;
    for (let b in a.children)
        child_process(b);
}
```

## Type Conversions

### Boolean to String

A TR-181 boolean is the string `"true"` or `"false"`:

```ucode
Enable: value ? 'true' : 'false'
Active: !!runtime_value ? 'true' : 'false'
```

### Number to String

Each TR-181 numeric value must be a string:

```ucode
Count: sprintf('%d', count ?? 0)
BytesSent: sprintf('%d', bytes)

// WRONG - returns an integer, not a string
InterfaceNumber: info.bInterfaceNumber

// CORRECT (modules/usb/handler.uc)
InterfaceNumber: sprintf('%d', info.bInterfaceNumber ?? 0)
```

### Default Values

Use `??` for default values. Do not use `||`:

```ucode
// CORRECT - ?? applies the default only to null
Name: data.name ?? ''
Count: sprintf('%d', data.count ?? 0)
Status: status_map[data.state] ?? 'Unknown'

// WRONG - || applies the default to each falsy value (0, '', false, null)
Count: sprintf('%d', data.count || 0)
Name: data.name || 'default'           // replaces a valid '' with 'default'
```

The `??` operator applies the default only if the value is `null`. It keeps valid falsy values such as `0`, `''` and `false`.

## Deduplication

### Existing Helpers

Before you write new code, find out if a helper exists:

1. Interface statistics: `ifstats_get()` and `ifstats_reset()` in `utils/ifstats.uc`.
2. Uptime: `ubbf.uptime_read()`.
3. Enumerate mode: `ubbf.enumerate_instances()` and `ubbf.get_by_instance()`.
4. Sysfs and other small files: `ubbf.readfile_trim()` and `ubbf.readfile_int()`.
5. Netifd status: `netifd_status_get()` in `utils/netifd.uc`.
6. Cached calls: `ubbf.cache_call()` and `ubbf.cache_invalidate()`.
7. Alias values: `ubbf.alias_from_mac()` and `ubbf.alias_from_name()`.

### New Utilities

Create a new utility function if all of these conditions are true:

1. The same code pattern occurs in 3 or more files.
2. The pattern has more than 5 lines of code.
3. The pattern has no dependency on one specific file.

Put the new utility in a related `utils/*.uc` file. If no related file exists, create a new one.

## Model Export Structure

```ucode
export const model = {
    'Device.Module': {
        schema: 'Module.Module',
        get: module_get
    },

    'Device.Module.Child': {
    },

    'Device.Module.Child.{i}': {
        schema: 'Module.Child',
        get: child_get
    },

    'Device.Module.Child.{i}.SubChild.{i}': {
        schema: 'Module.SubChild',
        get: subchild_get
    }
};
```

`schema` is the name `'<File>.<Export>'` of an export in `schemas/<File>.uc`. The build compiles these exports into the table `schema-core.so`, and the dispatcher reads the schema from that table. See "Schema tables" in `ARCHITECTURE.md`. A get handler that merges the defaults of a schema calls `ubbf.schema_defaults()` with the same name:

```ucode
let cfg = { ...ubbf.schema_defaults('Firewall.Service'), ...ctx.config };
```

Source: `service_get()` in `tr181/Firewall.uc`. An out-of-tree module uses `ubbf_module.schema(key)` and `ubbf_module.schema_defaults(key)` instead, with the keys of its `schema.uc`.

### Rules

1. The paths must be in ascending order of depth.
2. A container path (without `{i}`) usually has no handlers.
3. An instance path (`{i}`) must have a schema.
4. A get handler is optional if all data comes from the configuration.
5. An entry can have `protocol: 'cwmp'` or `protocol: 'usp'` if the object belongs to one management protocol. An entry without `protocol` serves both. At load, `model_filter()` in `datamodel.uc` removes the entries of the other protocol.
6. An entry can have `since: '2.<minor>'` and `until: '2.<minor>'` if the object exists only in some TR-181 versions. A schema can tag its members in the same way, with `since` and `until` tables next to `defaults`. At load, the core removes what the image's version does not have. See "TR-181 versions" in `ARCHITECTURE.md`.

A schema can have the optional `constraints` table. See "Schemas" in `ARCHITECTURE.md`. Declare `secured: true` there for each credential that the module models. Without it, an ACS or a controller reads the real value. Declare there also the values that TR-181 allows; the core refuses other values. A table that the CPE maintains itself has `addable: false` next to `constraints`.

Commands (`Name()`) and events (`Name!`) are USP objects. In a CWMP image, `member_protocol_ok()` in `datamodel.uc` removes them from the advertised schema. To keep a command or an event, its schema member must declare `protocol: 'cwmp'` or `protocol: 'both'`. A module needs no annotation for the default case.

## Operations Export Structure

```ucode
export const operations = {
    'Device.Module.Operation()': {
        type: 'async',
        handler: operation_handler
    },

    'Device.Module.Child.{i}.InstanceOperation()': {
        type: 'async',
        handler: instance_operation_handler
    },

    'Device.Module.ConfigOperation()': {
        type: 'async',
        commit: true,
        handler: config_operation_handler
    }
};
```

### Async Operation Handlers

`run_async_op()` in `datamodel.uc` calls an async handler with these arguments:

- For a path without `{i}`: `handler(input, instance, complete, command_key, root)`.
- For a path with `{i}`: `handler(input, instance, complete, instances, command_key, root)`. `instances` is the array of instance numbers in the path.

The handler must call `complete(instance, err, msg, output)` once. For success, `err` is 0. For an error, use a `USP_ERR_*` constant. The native module defines these constants as globals in `scope_inject_globals()` in `src/ucode-mod-ubbf/ubbf.c`.

On an error, give `{}` as `output`. The controller gets only `err` and `msg`: `usp_msg_notify_oper_complete()` in `src/usp-service/usp-protocol.c` sends the output arguments only for `err` 0, and `operation_complete()` in `datamodel.uc` gives a ubus caller no output on an error. Source: `tr143/Ping.uc`, `modules/packetcapture/handler.uc`.

Run blocking work in a child process with `task_run()` from `utils/process.uc` (`ubbf_module.utils.process.task_run` in a module), not with `uloop.task()` directly. uloop calls no callback for a child that dies without a message, so with `uloop.task()` the operation can stay pending until a restart.

```ucode
function operation_handler(input, instance, complete, command_key, root) {
    if (!input?.RequiredParam) {
        complete(instance, USP_ERR_INVALID_ARGUMENTS, 'RequiredParam is required', null);
        return;
    }

    let result = perform_operation(input);

    complete(instance, 0, null, { ResultField: result.value });
}
```

### Sync Operation Handlers

`run_sync_op()` in `datamodel.uc` calls a sync handler with these arguments:

- For a path without `{i}`: `handler(input, command_key, root)`.
- For a path with `{i}`: `handler(input, command_key, instances, root)`.

The return value gives the result:

- An object: success. The object is the output of the command.
- A negative `USP_ERR_*` code: failure with that code. Use `-USP_ERR_INVALID_COMMAND_ARGS` for a bad or missing input argument. `sync_op()` in `usp.uc` gives the code to OBUSPA, and the ubus method `operate` returns it as `code`.
- `null`: failure with `USP_ERR_COMMAND_FAILURE` (7022).

The controller gets the code only, without a message, so log the cause of a failure. Source: `wol_send_magic_packet()` in `modules/wol/handler.uc`.

### Commit Operations

If the entry has `commit: true`, the dispatcher starts a transaction before it calls the handler. `root` is then the configuration tree. If the handler completes with `err` 0, the dispatcher commits the changes. Otherwise, it aborts the transaction.

```ucode
function config_operation_handler(input, instance, complete, command_key, root) {
    root.Section ??= {};
    root.Section.Value = input.Value;

    complete(instance, 0, null, { Status: 'Success' });
}
```

Source: `modules/easymesh/operations.uc`.

## JSDoc Documentation

Each function must have a JSDoc header. The header gives the purpose, the parameters and the return value.

### Required Format

```ucode
/**
 * Brief description of what the function does.
 *
 * @param {type} param_name - Description of parameter
 * @returns {type} Description of return value
 */
function example_function(param_name) {
    // implementation
}
```

### Example

```ucode
/**
 * Get handler for Device.LEDs.LED.{i}.
 *
 * @param {object} ctx - Context with optional instance number
 * @returns {object|null} Single LED or enumerated LEDs
 */
function led_get(ctx) {
    let leds = fs.lsdir('/sys/class/leds');

    if (ctx.instance == null)
        return ubbf.enumerate_instances(leds, led_to_object);

    let led = ubbf.get_by_instance(leds, ctx.instance);
    if (!led)
        return null;
    return led_to_object(led);
}
```

Source: `modules/leds/handler.uc`.

### Rules

1. Each function must have a JSDoc header.
2. Use `@param` for each parameter, with the type and a description.
3. Use `@returns` for the return value, with the type and a description.
4. Keep the descriptions short.
5. Use `{object}` for plain objects, `{array}` for arrays and `{string|null}` for nullable types.

## Verification Checklist

When you review a TR-181 handler module, make sure that:

1. [ ] The file starts with `'use strict';`.
2. [ ] The imports are in the correct groups and order.
3. [ ] Enumerate mode uses `ubbf.enumerate_instances()` and `ubbf.get_by_instance()`, with no manual loops.
4. [ ] The converter functions use the `*_to_object` names.
5. [ ] The module uses the helpers for sysfs and statistics, and does not read them again.
6. [ ] No function has more than 3 levels of nesting.
7. [ ] The code uses early returns, not deep nesting.
8. [ ] All TR-181 values are strings, booleans and numbers included.
9. [ ] Default values use the `??` operator.
10. [ ] The model paths are in ascending order.
11. [ ] Each function has a JSDoc header.
12. [ ] Each `export function` has a semicolon after its closing brace.

## Common Mistakes

The sections above show these mistakes: manual enumerate loops, deep nesting, `||` for defaults and mixed import groups. This section shows the other mistakes.

### Duplicate Statistics Reads

```ucode
// WRONG
return {
    BytesSent: ubbf.readfile_trim(`/sys/class/net/${dev}/statistics/tx_bytes`, '0'),
    BytesReceived: ubbf.readfile_trim(`/sys/class/net/${dev}/statistics/rx_bytes`, '0'),
    // ... 15 more lines
};

// CORRECT
import { ifstats_get } from 'ubbf.utils.ifstats';
return ifstats_get(dev);
```

### Native Types

```ucode
// WRONG
return {
    Enable: true,
    Count: 42
};

// CORRECT
return {
    Enable: 'true',
    Count: '42'
};
```

### Missing Null Guards

```ucode
// WRONG - fails if status is null
return {
    Address: status.addresses[0].ip
};

// CORRECT
let addrs = status?.addresses ?? [];
return {
    Address: length(addrs) > 0 ? addrs[0].ip : ''
};
```

## Reference Files

These handler modules show the patterns of this document:

- `tr181/IP.uc`: statistics through `utils/ifstats.uc`, enumerate pattern.
- `tr181/Ethernet.uc`: handlers based on the configuration, statistics through `utils/ifstats.uc`.
- `tr181/Bridging.uc`: early returns, use of utilities.
- `modules/leds/handler.uc`: enumerate helpers with a converter function.
- `modules/lldp/handler.uc`: helper functions that decrease the nesting.
- `tr181/NeighborDiscovery.uc`: early returns for complex conditions.

## Template Helper Functions

Render templates (`render/templates/*.uc`) run in script mode. `generate()` in `render/renderer.uc` fills a shared scope and then calls `include()` for each template. A template does not import modules. It gets each helper below through the scope.

### Shared State

| Name | Description |
|------|-------------|
| `output` | The array of UCI batch lines. Templates append to it through the `uci_*` helpers. |
| `config` | The TR-181 configuration (`config.json`) that `apply` reads and gives to `generate()` |
| `render_state` | An object that all templates of one run share |

### Configuration Navigation

Source: `src/ucode-mod-ubbf/tree.c`.

| Function | Description |
|----------|-------------|
| `ubbf_get(config, path)` | Returns the value at a TR-181 path |
| `ubbf_instances(config, path)` | Returns all instances under the path as an array |
| `ubbf_enabled(config, path)` | Returns `true` if the value at the path is `true`, `"true"` or `"1"` |

### Type Conversion

Source: `src/ucode-mod-ubbf/coerce.c`.

| Function | Description |
|----------|-------------|
| `ubbf_to_bool(value)` | Returns `true` for `true`, `"true"` or `"1"` |
| `ubbf_to_int(value)` | Converts a base-10 string to an integer. Returns `null` if the conversion fails. |

### UCI Command Generation

Source: `render/uci_helpers.uc`. Each helper takes the shared `output` array as its first argument.

| Function | Output line |
|----------|-------------|
| `uci_set_string(output, path, value)` | `set <path>='<value>'` (quoted) |
| `uci_set_boolean(output, path, value)` | `set <path>=1` or `set <path>=0` |
| `uci_set_number(output, path, value)` | `set <path>=<value>` (unquoted) |
| `uci_set_raw(output, path, value)` | `set <path>=<value>` (unquoted) |
| `uci_list_string(output, path, value)` | `add_list <path>='<value>'` |
| `uci_delete(output, path)` | `delete <path>` |
| `uci_section(output, 'pkg type')` | `add <pkg> <type>` (anonymous) |
| `uci_named_section(output, 'pkg.name', type)` | `set <pkg>.<name>=<type>` |
| `uci_comment(output, comment)` | The comment text. The caller supplies the `#`. |
| `uci_set_secret(output, path, value)` | `set <path>='<value>'`, shown as `'<secret>'` in a dry-run |

A template sets every secret value with `uci_set_secret()`: the value of a
parameter that its schema marks `secured`, and each field that
`EASYMESH_SECRETS` names.

### State Sharing

Templates can share calculated values through `render_state` (`render/helpers.uc`):

```javascript
device_state_set(render_state, 'br-lan', 'enabled', '1');
device_state_list_add(render_state, 'br-lan', 'ports', 'eth0');
```

### Interface Resolution

```javascript
lower_layer_resolve(config, lower_layers)
```

`lower_layer_resolve()` takes the first reference of a `LowerLayers` list. It returns the `Name` of the referenced object, or `null`.

## Adding a New TR-181 Object

Do these steps to add a new TR-181 domain to ubbf.

### Step 1: Create the Schema

Create `schemas/NewObject.uc`. The native module defines `dm_type` as a global, so the schema needs no import. The build compiles every file in `schemas/` into `schema-core.so`, so there is no list to update:

```javascript
'use strict';

export const NewObject = {
    path: "Device.NewObject.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Name": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "true",
        "Status": "Disabled",
        "Name": ""
    }
};
```

### Step 2: Create the Handler

Create `tr181/NewObject.uc`:

```javascript
'use strict';

/**
 * Get handler for Device.NewObject.{i}.
 *
 * @param {object} ctx - Context with config and instance
 * @returns {object|null} Object properties or null if not found
 */
function new_object_get(ctx) {
    if (!ctx.config)
        return null;

    return {
        ...ctx.config,
        Status: ctx.config.Enable == 'true' ? 'Enabled' : 'Disabled'
    };
}

export const model = {
    'Device.NewObject': {
    },

    'Device.NewObject.{i}': {
        schema: 'NewObject.NewObject',
        get: new_object_get
    }
};
```

### Step 3: Register the Handler in the Data Model

In `datamodel.uc`, import the handler and add its `model` to `full_model`:

```javascript
import * as NewObject from 'ubbf.tr181.NewObject';

const full_model = {
    // ...
    ...NewObject.model
};
```

If the handler exports `operations`, also add `...NewObject.operations` to `all_operations`.

### Step 4: Create the Render Template (if the object makes UCI output)

Create `render/templates/newobject.uc`:

```javascript
function render_config() {
    let instances = ubbf_instances(config, 'Device.NewObject');
    if (!length(instances))
        return;

    services.set_enabled('newobject', true);

    for (let obj in instances) {
        if (!ubbf_to_bool(obj.Enable))
            continue;

        uci_named_section(output, `newobject.${obj.Name}`, 'entry');
        uci_set_string(output, `newobject.${obj.Name}.name`, obj.Name);
        uci_set_boolean(output, `newobject.${obj.Name}.enabled`, true);
    }
}
uci_comment(output, '# generated by newobject.uc');
render_config();
```

The template has no top-level imports and no `'use strict'`. `renderer.uc` supplies all names through the shared scope, for example `output`, `config`, `ubbf_*`, `uci_*` and `services`.

### Step 5: Register the Template

In `generate()` in `render/renderer.uc`, add an `include()` line next to the other templates:

```javascript
include('templates/newobject.uc', scope);
```

The template can write to a UCI package that no other template renders. In this case, also add an empty file `files/etc/ubbf/shadow/<package>`. `apply` copies `/etc/ubbf/shadow/` and runs the batch against the copy. uci drops each line for a package that has no file in that directory. The section is then in `/tmp/ubbf/uci.batch`, but not in `/var/run/uci/`. An out-of-tree module keeps the file in `modules/<name>/files/etc/ubbf/shadow/<package>`. See "Shadow files" in `ARCHITECTURE.md`.

### Step 6: Control the Service

To enable or disable a service, call `services.set_enabled(name, enable)` in the template. `render/services.uc` needs no change. After the UCI commit, `apply` enables and starts each service with `true`, and disables and stops each service with `false`. Then it runs `reload_config`. Source: `set_enabled()` in `render/services.uc` and `files/usr/libexec/ubbf/apply`.

## Runtime Rows Next to Persisted Rows

Some tables hold rows the controller configured and rows the CPE created itself, for example `Device.NAT.PortMapping.{i}` with UPnP mappings from `upnpd`. The hydration walk runs the enumerate mode of a table only when no persisted row matched the request. A model entry with `runtime_instances: true` also runs it for the container, with `ctx.config` null, and merges the returned keys next to the persisted rows.

Rules for such a handler:

- With `ctx.config` set, return the persisted row.
- With `ctx.config` null and `ctx.instance` set, return the runtime row with that number, or `null`.
- With `ctx.config` null and no instance, return an object keyed by instance number with every runtime row.
- Number the runtime rows through the instance map (`ubbf.instance_*()`), with a stable key per row and `instance_floor()` of the stored table as floor, so that they follow the persisted rows: `instance_numbers()` or `instance_rows()`, or `instance_items()` for keys that never come back, such as a daemon's row id. Persisted and runtime rows then share one pool of numbers: a controller add takes the next number of the map (see "Instance numbers of runtime rows" in `ARCHITECTURE.md`). A `del` hook finds the key of a number with `instance_lookup()`, which numbers nothing. Source: `port_mapping_get()` and `port_mapping_del()` in `tr181/NAT.uc`.

The parent's `<Table>NumberOfEntries` is recounted on the merged table, so the parent handler needs no change.

A controller can write only the stored rows. A Set on a runtime row stores nothing: USP answers 7013 (parameter read-only) for a row that exists at run time, and 7016 for an instance that does not exist at all.

A table that the CPE maintains but whose rows have writable parameters, for example `Device.Optical.Interface.{i}` (`Enable`, `Alias`), sets `writable_rows: true` next to `runtime_instances: true`. A write into a runtime row then stores that row: the dispatcher asks the get handler for the instance (`runtime_row_live()` in `src/ucode-mod-ubbf/dm_set.c`) and accepts the write only when the handler returns the row, so no row is stored for an instance that does not exist. An add of a row in a table below such a runtime row (`object_add()`) follows the same rule: the dispatcher accepts it only when the get handler returns the parent row. The enumerate mode of the handler leaves out the instances that the configuration stores, and the stored mode returns the live values over the stored ones; the live rows of the other instances stay visible. `path_runtime_instance_absent()` in `src/ucode-mod-ubbf/dm_set.c` and `runtime_row_exists()` in `datamodel.uc` implement this. A runtime row is addressed by its instance number only: alias paths resolve against the stored rows. After a `del` hook removes a row at its source, it calls `ubbf.cache_invalidate()` for its fetch function, so that a read in the same 2 seconds no longer lists the row.

A `del` hook on the same entry receives `{ path, instance }` before the configuration is touched. It returns `true` when it removed a runtime row at its source. It returns a negative USP error code to refuse the delete, for example `-USP_ERR_OBJECT_NOT_DELETABLE` for a static row. Otherwise the persisted path goes through `dm.object_del()`. The hook runs outside the configuration transaction. USP, CWMP and `bbf-dm` all delete through `object_delete()` in `datamodel.uc`, so the hook sees every delete. Source: `runtime_del()` and `object_delete()` in `datamodel.uc`, the table walk in `src/ucode-mod-ubbf/dm_set.c`, `port_mapping_get()` and `port_mapping_del()` in `tr181/NAT.uc`, and `system_row_del()` in `modules/users/handler.uc`.
