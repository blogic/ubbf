# ubbf architecture

This document describes the implementation of ubbf: the directory structure, the module system, the main components and the rules for out-of-tree modules.

## Directory structure

```
files/usr/share/ucode/ubbf/
├── datamodel.uc          # Core engine: get, set, add, delete, transactions
├── ubus-object.uc        # The bbf-dm ubus object
├── usp.uc                # Glue for the USP agent
├── cwmp-dm.uc            # Glue for the CWMP agent
├── acl.uc                # ACL filter for the web UI
├── initial.json          # Default configuration
├── schemas/              # TR-181 schema definitions
│   ├── WiFi.uc           # Device.WiFi.*
│   ├── IP.uc             # Device.IP.*
│   └── ...
├── tr181/                # Handlers for runtime data
│   ├── WiFi.uc
│   ├── IP.uc
│   ├── DeviceInfo/       # Sub-handlers of Device.DeviceInfo
│   └── ...
├── tr143/                # Diagnostic operations
│   ├── Diagnostics.uc    # Registers the handlers below
│   ├── Ping.uc
│   ├── TraceRoute.uc
│   ├── Download.uc
│   ├── Upload.uc
│   ├── UDPEcho.uc
│   └── ServerSelection.uc
├── render/               # Generation of the UCI configuration
│   ├── renderer.uc       # Runs the templates
│   ├── services.uc       # Service reload tracking
│   ├── helpers.uc        # Render state helpers
│   ├── uci_helpers.uc    # UCI batch line helpers
│   ├── ubbf_helpers.uc   # TR-181 tree access helpers
│   └── templates/        # One template per subsystem
│       ├── wifi.uc       # Device.WiFi to wireless
│       ├── ip.uc         # Device.IP to network
│       ├── dhcp.uc       # Device.DHCPv4 and DHCPv6 to dhcp
│       ├── firewall.uc   # Device.Firewall to firewall
│       └── ...
└── utils/                # Shared helpers

modules/                  # Domains packaged separately as ubbf-mod-<name>
├── lldp/                 # Device.LLDP
│   ├── handler.uc        # Runtime handlers; fills model and operations
│   ├── schema.uc         # Included by handler.uc
│   └── render.uc         # UCI template; runs after the in-tree templates
├── dslite/               # Device.DSLite
├── usfpd/                # Device.SFPs and Device.Optical, both from usfpd
├── qosify/               # Device.X_UBBF.QoSify
│   └── files/            # Tree installed at /: the qosify shadow file
├── multicast/            # Device.X_UBBF.MulticastProxy, igmpproxy or omcproxy
├── umdns/                # Device.DNS.SD
├── testbed/              # Device.X_UBBF.Testbed and the test harness RPC service
├── location/             # Device.DeviceInfo.Location, from ucode-gps
└── cellular/             # Device.Cellular, from the ModemManager rpcd plugin
```

`modules/` is outside `files/` because the base package does not ship it. Each module is its own package. See "Out-of-tree modules" below.

## Entry points

```
USP agent (OBUSPA)   CWMP agent     ubus clients (web UI, bbf-cli)
        |                 |                     |
        v                 v                     v
      usp.uc          cwmp-dm.uc         ubus-object.uc (bbf-dm)
        |                 |                     |
        +-----------------+---------------------+
                          |
                          v
                    datamodel.uc
                          |
              +-----------+-----------+
              v                       v
         tr181/*.uc              tr143/*.uc
```

## Render pipeline

On a commit, the render pipeline converts the TR-181 tree into OpenWrt UCI configuration:

```
/etc/ubbf/config.json
        |
        v
renderer.uc
        |
        v
render/templates/*.uc
        |
        v
/tmp/ubbf/uci.batch
        |
        v
uci batch, uci commit
        |
        v
service reloads
```

## Programs

### Command line

| Program | Description |
|---|---|
| `bbf-cli` | Command line client of `bbf-dm`: get, set, add, del, operate, apply. See `docs/CLI.md`. |

### Helpers

The helpers are in `/usr/libexec/ubbf/`. The table lists the main helpers.

| Helper | Description |
|---|---|
| `apply` | Renders the configuration and applies the UCI batch |
| `capabilities` | Detects the hardware (radios, ports, features) and writes `/tmp/ubbf/capabilities.json` |
| `deviceinfo` | Collects device information (model, serial number, versions) |
| `boot-cause` | Detects the boot reason (power cycle, watchdog, user reboot) |
| `serverselection` | Runs TR-143 ServerSelectionDiagnostics |
| `default_config` | Generates the first-boot configuration. It builds the router preset from the hardware probes and derives the other presets (`/etc/ubbf/config-<mode>.json`). `--dry-run [--mode NAME]` prints the presets on a build host. |

### Init scripts

| Script | Description |
|---|---|
| `ubbf-device` | Device daemon: lifecycle operations (reboot, factory reset, upgrade) and the scheduled apply |
| `ubbf-apply` | Applies the configuration at boot |
| `ubbf-udpecho` | UDP echo server for TR-143 |
| `ubbf-bulkdata` | Bulk data collection and upload |
| `bbf-qos` | QoS service |

## Module system

### Import patterns

| Kind | Pattern |
|---|---|
| Schema | `import * as schemas from 'ubbf.schemas.DomainName'` |
| TR-181 handler | `import * as Module from 'ubbf.tr181.Module'` |
| TR-143 handler | `import { handler } from 'ubbf.tr143.Operation'` |
| Utility | `import { func } from 'ubbf.utils.helper'` |
| Render helper | `import { func } from 'ubbf.render.helper'` |

A module path matches the file path under `files/usr/share/ucode/ubbf/`. For example, `ubbf.schemas.DNS` is `schemas/DNS.uc`, and `ubbf.utils.netifd` is `utils/netifd.uc`.

### File names

- Schema files and TR-181 handlers: the name of the TR-181 root object, for example `DNS.uc` and `WiFi.uc`.
- TR-143 handlers: the name of the operation, for example `Ping.uc`.
- Render templates: the domain in lower case, for example `dns.uc`.

## Out-of-tree modules

The sections above describe the code in the ubbf package. A domain can also live in a directory under `/usr/share/ucode/ubbf/modules/`. A separate package can install this directory, or one of the `ubbf-mod-*` packages of this repository.

```
/usr/share/ucode/ubbf/modules/<name>/handler.uc   optional, for the data model
                                    schema.uc    optional, included by handler.uc
                                    render.uc    optional
```

A module must have `handler.uc`, `render.uc` or both. A directory with only `render.uc` configures the system but adds nothing to the data model. The loader skips it.

### Loading

`external_modules_register()` in `datamodel.uc` runs each `handler.uc` with `include()`, after the built-in model is complete. The include scope has one entry, `ubbf_module`, which `module_api_build()` creates. After the include, the loader merges the `model` and `operations` of that object into the data model. `renderer.uc` includes each `render.uc` after the in-tree domain templates and before `templates/device.uc`.

The handler binds the values it needs from `ubbf_module` at the top of the file. Then it fills `model`. It imports nothing and returns nothing:

```javascript
'use strict';

const ubbf = ubbf_module.ubbf;            // bind first, see below
const utils = ubbf_module.utils;
const model = ubbf_module.model;

const fs = require('fs');                 // stock ucode modules: require()

let schemas = {};
include('schema.uc', { schemas });        // resolves against this directory

function device_get(ctx) {
    return {
        Host: utils.hosts.host_path_by_mac(ctx.root, mac),
        Port: ubbf.enumerate_instances(ports, port_to_object)
    };
}

model['Device.LLDP'] = { schema: schemas.LLDP, get: lldp_get };
```

`ubbf_module` holds:

- `ubbf`: the C module
- `utils`: in-tree helpers, keyed by their `ubbf.utils.*` module name
- `model` and `operations`: empty objects for the module to fill

`utils` holds only the helpers that a module needed so far. If a module needs another helper, add it as a literal key.

### Bind at the top of the file

The include scope exists only while the include runs. `uc_callfunc()` replaces the global scope of the VM with the include scope and restores the original afterwards. A free name in a function is resolved in the global scope that is active when the function runs. Thus top-level code sees `ubbf_module`, but a get handler that OBUSPA calls later does not. OBUSPA uses strict declarations, so the first read then fails with `access to undeclared variable ubbf`, although the module registered without error. A file-level `const` is an upvalue and stays valid. For this reason the three bindings come first.

### Why a scope and not require()

An image built with `CONFIG_UBBF_MINIFY` runs every file under `usr/share/ucode` through the minifier as a module. A module cannot contain a top-level `return` (`'return' outside of function`). `include()` is the only loader that takes a scope, so the scope is the only channel that works in both directions.

Reference modules in this repository:

- `modules/lldp`, `modules/dslite` and `modules/usfpd`: the basic shape
- `modules/usfpd`: registers an operation and has two domains in one handler
- `modules/cellular`: logs through `utils.logging`

### Rules

Each rule below prevents a failure that is difficult to trace back from its symptom.

- **No `export`, no `import` and no top-level `return`** in `handler.uc` or in a file that it includes. `include()` compiles with module mode off, so `export` and `import` are syntax errors at load. A top-level `return` is a syntax error in the minifier. To split a module, use `include(path, scope)`. The minifier inlines a literal include into `call(function() {...}, null, scope)` and deletes the included source. For this reason `schema.uc` is not in a minified image.
- **Do not import from `ubbf.*`.** A minified image changes the export names in the whole in-tree bundle. An out-of-tree module that asks for the original name gets `Module does not export '...'`. This is a compile error, and the loader cannot catch it. For the same reason, `module_api_build()` lists each helper as a literal key and never passes a namespace object: literal keys survive the minifier, namespace members do not.
- **Assume strict mode.** OBUSPA compiles its VM with `strict_declarations = true`, and `include()` inherits the configuration of the calling VM. An undeclared global is a hard error in OBUSPA, but not in `apply` and `cwmp-dm`. `ubbf_module` is declared only while the include runs.

If a module breaks a rule, or leaves `model` and `operations` empty, the loader logs the error and skips the module. The loader never passes the error on: an uncaught exception at this point stops `vendor_ucode_init()`, and the agent does not start.

### Tables under a core parent

A module can add a table under a parent object that an in-tree handler owns. For example, `modules/location` registers `Device.DeviceInfo.Location.{i}`, and `Device.DeviceInfo` stays with the in-tree handler.

- Do not register the parent key from a module. The model merge keeps the last writer, so the core `get` would be lost.
- The module does not maintain `<Table>NumberOfEntries` of the parent. For a table with no stored rows, `dispatch_subtree()` in `src/ucode-mod-ubbf/dm.c` counts the rows that the handler enumerated. After the model walk, it writes the count to the parent, if the parent schema declares the key. The count is therefore correct even when the parent handler merges its schema default `"0"`.
- A runtime table refuses an `Add` from a controller with `maxInstances: 0` on its `{i}` entry. The runtime discovery of the dispatcher runs only while no row is stored, so an added row would hide the live rows.

### Render templates of modules

A module `render.uc` runs after all in-tree domain templates and before `templates/device.uc`, which writes the shared `network device` sections.

- It can read all values that the in-tree templates computed, through the shared scope and `render_state`.
- It can feed `render_state.device` through `device_state_set()`, the same as an in-tree domain. For example, `modules/usfpd/render.uc` maps `Optical.Interface.{i}.Enable` to `enabled` of the cage netdev.
- Do not write a second `network device` section for the same netdev. `config_device_add()` in netifd applies each section with that name to the same device, one after the other, and `device_set_config()` resets the settings flags each time. A section with only `enabled` then removes the `autoneg`, `speed` or `mtu` that `ethernet.uc` and `ip.uc` set.
- `services.uc` is a global with last-write-wins. If a module calls `services.set_enabled()` on a name that an in-tree template also sets, the module wins because it runs later. A `render_state.device` key that both sides set behaves the same.
- A module can append sections to a package that an in-tree template already rendered, if the UCI order does not change the meaning for that package. For example, `modules/multicast/render.uc` adds its `Allow-Mcast-*` rules to `firewall`. This is correct because fw4 evaluates every `rule` before the zone forwardings.

### Shadow files

`apply` runs the batch against a copy of `/etc/ubbf/shadow/`. `uci -q batch` drops every line for a package that has no file there, with exit status 0. The batch then shows the section, but `/var/run/uci/<package>` is not created. If a module `render.uc` writes to a package that no in-tree template renders, the module must ship an empty `files/etc/ubbf/shadow/<package>` in its module directory.

### Packaging

- The feed Makefile minifies `modules/` in a second pass, with its own source map.
- Each `Package/ubbf-mod-<name>` installs the `.uc` files to `/usr/share/ucode/ubbf/modules/<name>/`.
- Each package declares the daemon it needs: `+lldpd`, `+ds-lite`, `+usfpd`, `+qosify`, `+igmpproxy`, `+umdns`, `+ucode-gps`. `testbed` needs no daemon. `cellular` pulls ModemManager, its rpcd plugin and the USB modem drivers.
- The package dependency replaces the runtime probe that `optional_modules` in `datamodel.uc` does for in-tree domains: if the module is installed, its daemon is installed too.
- Files that a module needs outside its own directory, for example a shadow file or a `uci-defaults` script, go in `modules/<name>/files/`, as a tree rooted at `/`. The package installs this tree unchanged.

## Components

### Schemas (`schemas/*.uc`)

A schema defines the structure of a TR-181 object. Each schema exports an object with these keys:

| Key | Content |
|---|---|
| `path` | TR-181 path pattern, for example `Device.WiFi.Radio.{i}.` |
| `schema` | Parameter types and flags |
| `defaults` | Default values for new instances |
| `constraints` | Optional. More TR-181 properties of a parameter, keyed by leaf name |

```javascript
export const Radio = {
    path: "Device.WiFi.Radio.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Channel": dm_type.UINT | dm_type.WRITABLE,
        // ...
    },
    defaults: {
        "Enable": "true",
        "Status": "Down",
        "Channel": "0",
        // ...
    }
};
```

A `schema` value is one integer with a type and the `WRITABLE` bit. Other properties go in `constraints`. `param_schema()` merges them into the answer that all front ends read:

```javascript
export const AccessPoint_Security = {
    path: "Device.WiFi.AccessPoint.{i}.Security.",
    schema: {
        "KeyPassphrase": dm_type.STRING | dm_type.WRITABLE,
        // ...
    },
    constraints: {
        "KeyPassphrase": { secured: true }
    }
};
```

`secured` is the TR-181 attribute of the same name. Over CWMP and USP, the parameter reads back as an empty string. It stays listed and writable, and the stored value does not change. The local interfaces (`bbf-dm get`, `show`, `bbf-cli`, `webui-show`) show the real value, because the rule applies to an ACS or a controller, not to a local operator.

Do not use a `dm_type` bit for this kind of property. OBUSPA keeps its own copy of the `dm_type` constants. It passes all bits except `WRITABLE` to the USP core as a type value. A new bit therefore registers an incorrect type until the OBUSPA package is built again.

A schema without `constraints` works as before.

### Runtime handlers (`tr181/*.uc`)

The handlers supply live data and merge it with the stored configuration. Each handler module exports a `model` object that maps TR-181 paths to handlers:

```javascript
export const model = {
    'Device.WiFi.Radio.{i}': {
        schema: schemas.Radio,
        get: radio_get
    },
    // ...
};
```

A handler module can:

- define TR-181 paths and their schemas
- supply `get` callbacks for live data
- supply `set` callbacks for parameters that need custom handling
- supply `init` callbacks for dynamic instance discovery
- export `operations` for commands

### Data model engine (`datamodel.uc`)

The engine:

- imports all TR-181 and TR-143 handler modules
- merges their `model` and `operations` exports into one data model
- runs get, set, add and delete on the data model
- stores the configuration in `/etc/ubbf/config.json`

| Function | Description |
|---|---|
| `params_get(paths)` | Gets parameter values: configuration and runtime state |
| `params_set(params)` | Sets parameter values |
| `object_add(path)` | Creates an instance and returns its number |
| `object_del(path)` | Deletes an instance |
| `trans_start()` | Starts a transaction on a copy of the tree |
| `trans_commit()` | Commits the transaction and starts the apply |
| `trans_abort()` | Discards the changes of the transaction |
| `get_subtree_with_state(path)` | Gets a subtree with the runtime state merged |
| `find_operation(path)` | Finds the handler of an operation |
| `run_sync_op(path, input, key)` | Runs a synchronous operation |
| `run_async_op(path, input, ...)` | Runs an asynchronous operation |

### Diagnostic handlers (`tr143/*.uc`)

Each diagnostic handler:

- exports a `handler(input, instance, complete, command_key, root)` function, which `tr143/Diagnostics.uc` registers
- runs the measurement command with `popen_async()` from `utils/process.uc`, so the event loop does not block
- converts the command output into the TR-181 result and calls `complete()`

### Render templates (`render/templates/*.uc`)

A template is a plain ucode script that converts the TR-181 configuration into UCI batch lines. `renderer.uc` runs each template with `include(path, scope)`. The scope holds the shared `output` array, the helper functions (`ubbf_*`, `uci_*`), and the `config` and `render_state` objects. Templates append lines to `output`. After the last template, `renderer.uc` joins the array.

```javascript
function render_config() {
    let radios = ubbf_instances(config, 'Device.WiFi.Radio');
    if (length(radios) == 0)
        return;

    for (let radio in radios) {
        uci_named_section(output, `wireless.${radio.Name}`, 'wifi-device');
        uci_set_string(output, `wireless.${radio.Name}.type`, 'mac80211');
        uci_set_string(output, `wireless.${radio.Name}.channel`, radio.Channel);
    }
}
uci_comment(output, '# generated by wifi.uc');
render_config();
```

Rules for templates:

- Put all logic in a `render_config()` function, and call it at the end of the file.
- Use the `ubbf_*` helpers to read the configuration and the `uci_*` helpers to append lines to `output`.
- Do not declare a top-level `let output = []` and do not import modules. `output`, the `ubbf` module and the other dependencies come through the scope that `renderer.uc` builds.
- Register services for reload with `services.set_enabled()`.
- Share computed values between templates through `render_state`.

### Utilities (`utils/*.uc`)

The main shared helpers:

| File | Content |
|---|---|
| `cache.uc` | Caches function results for one request |
| `dhcp.uc` | DHCP lease queries |
| `events.uc` | `dm_event_send(path, args)`, see "Events" below |
| `hosts.uc` | Host table for `Device.Hosts` |
| `ifstats.uc` | TR-181 `Stats` objects from the udevstats counters |
| `logging.uc` | Logging helpers |
| `netifd.uc` | netifd status queries |
| `path.uc` | TR-181 path parsing and interface resolution |
| `process.uc` | Command execution, `cmd_build()` and `popen_async()` |
| `wifi.uc` | Wi-Fi status and capabilities |

### Events

Daemons that receive ubus notifications (hostapd, umap, bulk data and others) forward them to the data model as USP events, through the `event` method of `bbf-dm`. Each of these calls must use `dm_event_send(path, args)` in `utils/events.uc`. This function uses `return: 'ignore'`, so the event loop of the caller does not wait for a reply.

A blocking call can cause a deadlock between processes:

1. A TR-181 operate handler runs in OBUSPA with `commit: true`.
2. `trans_commit()` makes a synchronous `ubus.call('bbf-device', 'apply', ...)`. During this call, `bbf-dm` processes no requests.
3. At the same time, a subscriber daemon receives a ubus notification and waits for a reply from `bbf-dm`.
4. `bbf-dm` waits for `bbf-device`. Both sides continue only when the default ubus timeout of 30 s expires.

The USP operation then returns no result, for example `Device.WiFi.DataElements.Network.SetSSID()` with `AddRemoveChange=Change`, because the `ubus.call` of `bbf-cli` also times out.

Each new call to the `event` method of `bbf-dm`, anywhere in `files/`, must use `dm_event_send()`.

### Interface counters

The `Stats` objects of these paths read from the `udevstats` daemon, which counts packets and bytes per netdev, split into unicast, multicast and broadcast:

- `Device.Bridging.Bridge.{i}.Port.{i}`
- `Device.Ethernet.*`
- `Device.IP.Interface.{i}`
- `Device.USB.Interface.{i}`
- `Device.Cellular.Interface.{i}`
- `Device.WiFi.Radio.{i}` and `Device.WiFi.SSID.{i}`
- `Device.PPP.Interface.{i}`

Wireless and PPP netdevs get their names only when they come up. The hotplug script `/etc/hotplug.d/net/60-ubbf-udevstats-auto` then adds each of them with `ubus call udevstats add_device`.

`Stats.Reset()` calls the `clear` method of `udevstats` (in `utils/ifstats.uc`), which sets the shared counter of the netdev to zero. Each TR-181 path that reads the same netdev sees the reset, for example `Ethernet.Link.2.Stats` and `Bridging.Bridge.1.Port.2.Stats` on the same `eth1`. TR-181 permits this.

## Type flags (dm_type)

The C module defines `dm_type`, in `scope_inject_globals()` in `src/ucode-mod-ubbf/ubbf.c`.

| Flag | Description |
|---|---|
| `dm_type.STRING` | String |
| `dm_type.DATETIME` | ISO 8601 date and time |
| `dm_type.BOOL` | Boolean, `"true"` or `"false"` |
| `dm_type.INT` | Signed integer |
| `dm_type.UINT` | Unsigned integer |
| `dm_type.LONG` | Signed long |
| `dm_type.ULONG` | Unsigned long |
| `dm_type.DECIMAL` | Decimal number |
| `dm_type.BASE64` | Base64-encoded data |
| `dm_type.HEXBIN` | Hex-encoded binary |
| `dm_type.WRITABLE` | The parameter is writable |

Combine the flags with a bitwise OR: `dm_type.BOOL | dm_type.WRITABLE`.

## Checklist for a new domain

### Schema

- [ ] Copy the schema from `dm/json_schema/` to `schemas/`.
- [ ] Comment out the parameters that are not implemented.
- [ ] Check the `dm_type` flags against the TR-181 specification.
- [ ] Check the `WRITABLE` flag of each writable parameter.
- [ ] Set the default values.

### Handler

- [ ] Create `tr181/DomainName.uc`.
- [ ] Import the schemas.
- [ ] Define the container paths as empty objects.
- [ ] Define the instance paths with `{i}` and a schema reference.
- [ ] Add `get` callbacks for live data.
- [ ] Export `operations` if the domain has commands.
- [ ] Register the handler in `datamodel.uc`.

### Render template

- [ ] Create `render/templates/domainname.uc`. Put the logic in `render_config()` and end the file with `uci_comment(...)` and `render_config();`.
- [ ] Return early if the configuration is disabled or missing.
- [ ] Call `services.set_enabled(<init-script>, <bool or 'restart'>)` for each related service.
- [ ] Add `include('templates/domainname.uc', scope);` to `renderer.uc`.

### Tests

- [ ] The schema is in `/tmp/ubbf/schema.json`.
- [ ] Get and set work through ubus.
- [ ] The render produces valid UCI lines.
- [ ] The services reload as expected.
