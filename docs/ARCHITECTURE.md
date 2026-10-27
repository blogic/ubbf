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
├── lldp/                 # Device.LLDP (docs/modules/lldp.md)
│   ├── handler.uc        # Runtime handlers; fills model and operations
│   ├── schema.uc         # Included by handler.uc
│   └── render.uc         # UCI template; runs after the in-tree templates
├── dslite/               # Device.DSLite
├── usfpd/                # Device.SFPs and Device.Optical, both from usfpd
├── qos/                  # Device.QoS, bbf-qos-apply (docs/modules/qos.md)
├── qosify/               # Device.X_UBBF.QoSify (docs/modules/qosify.md)
│   └── files/            # Tree installed at /: the qosify shadow file
├── multicast/            # Device.X_UBBF.MulticastProxy, omcproxy (docs/modules/multicast.md)
├── mdns/                 # Device.DNS.SD
├── testbed/              # Device.X_UBBF.Testbed and the test harness RPC service
├── location/             # Device.DeviceInfo.Location: controller row, GPS row from ucode-gps
├── cellular/             # Device.Cellular, from the ModemManager rpcd plugin
└── softwaremodules/      # Device.SoftwareModules, from uxc and apk; see docs/SOFTWARE-MODULES.md
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
| `ubbf-device` | Device daemon (ubus `bbf-device`): lifecycle operations (reboot, factory reset, upgrade), the scheduled apply, the fault and reboot records, and the system events. Modules add plugins, see "ubbf-device plugins" |
| `ubbf-apply` | Applies the configuration at boot |
| `ubbf-udpecho` | UDP echo server for TR-143 |

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
                                    schema.uc    optional, the schemas of handler.uc
                                    render.uc    optional
/usr/lib/ubbf/schema-<name>.so                   optional, schema.uc compiled to a table
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
const schema = ubbf_module.schema;

const fs = require('fs');                 // stock ucode modules: require()

function device_get(ctx) {
    return {
        Host: utils.hosts.host_path_by_mac(ctx.root, mac),
        Port: ubbf.enumerate_instances(ports, port_to_object)
    };
}

model['Device.LLDP'] = { schema: schema('LLDP'), get: lldp_get };
```

`ubbf_module` holds:

- `ubbf`: the C module
- `utils`: in-tree helpers, keyed by their `ubbf.utils.*` module name
- `schema(key)`: the schema that `schema.uc` sets as `schemas.<key>`. With `schema-<name>.so` installed, it returns the table name `<name>.<key>`; otherwise it includes `schema.uc` once and returns the object. See "Schema tables".
- `schema_defaults(key)`: the defaults of that schema, for a get handler that merges them
- `model` and `operations`: empty objects for the module to fill
- `members`: an empty object for the commands and events that the module adds to a core object. See "Commands on a core parent".
- `on_commit(cb)` and `on_abort(cb)`: register a callback for each persist of the configuration and for each abandoned transaction. A transaction whose apply fails is abandoned: `commit_rollback()` in `datamodel.uc` restores the configuration from before the transaction and runs the abort hooks. The commit hooks also run once after the configuration loads at start-up. A set handler can stage a side effect, and the commit hook applies it. `modules/users` writes the accounts this way.
- `on_precommit(cb)`: registers a check that runs before a transaction commits. A check that returns a string refuses the commit, which then fails and is aborted. A commit hook cannot fail the commit, so a module whose commit hook could not carry out the change checks first. `modules/users` checks that `/etc` has room for the account files.
- `config_apply(operations, done)`: applies `{ op, path, value? }` entries in one transaction, the same as a write from a controller. It is for a change that the agent makes itself, for example when a timer expires. While a USP transaction is open, the write waits at the write gate: the call returns null and `done` gets the outcome later. Do not call it from a commit hook; start a timer instead. `modules/userinterface` disables an `HTTPAccess` row this way when its `AutoDisableDuration` runs out.

`utils` holds only the helpers that a module needed so far. If a module needs another helper, add it as a literal key.

### Bind at the top of the file

The include scope exists only while the include runs. `uc_callfunc()` replaces the global scope of the VM with the include scope and restores the original afterwards. A free name in a function is resolved in the global scope that is active when the function runs. Thus top-level code sees `ubbf_module`, but a get handler that OBUSPA calls later does not. OBUSPA uses strict declarations, so the first read then fails with `access to undeclared variable ubbf`, although the module registered without error. A file-level `const` is an upvalue and stays valid. For this reason the bindings come first.

### Why a scope and not require()

The loader gives the module its helpers, and the module gives the loader its model and operations. `include()` is the only loader that takes a scope, so the scope is the only channel that works in both directions.

Reference modules in this repository:

- `modules/lldp`, `modules/dslite` and `modules/usfpd`: the basic shape
- `modules/usfpd`: registers an operation and has two domains in one handler
- `modules/cellular`: logs through `utils.logging`
- `modules/packetcapture`: adds a command to the core object `Device.` through `members`
- `modules/tr471`: adds `IPLayerCapacity()` to `Device.IP.Diagnostics.`, which `tr143/Diagnostics.uc` owns, and a table below it
- `modules/softwaremodules`: async operations that run commands through `utils.process.popen_async`, and writes to rows that exist only at request time

### Rules

Each rule below prevents a failure that is difficult to trace back from its symptom.

- **No `export` and no `import`** in `handler.uc` or in a file that it includes. `include()` compiles with module mode off, so `export` and `import` are syntax errors at load. To split a module, use `include(path, scope)`.
- **Do not load `ubbf.*` modules.** `import` is a syntax error (rule above), and `require()` cannot compile a file that uses `export`, which every `ubbf.*` module does. Use the helpers in `ubbf_module.utils`.
- **Assume strict mode.** OBUSPA compiles its VM with `strict_declarations = true`, and `include()` inherits the configuration of the calling VM. An undeclared global is a hard error in OBUSPA, but not in `apply` and `cwmp-dm`. `ubbf_module` is declared only while the include runs.

If a module breaks a rule, or leaves `model` and `operations` empty, the loader logs the error and skips the module. The loader never passes the error on: an uncaught exception at this point stops `vendor_ucode_init()`, and the agent does not start.

### Tables under a core parent

A module can add a table under a parent object that an in-tree handler owns. For example, `modules/location` registers `Device.DeviceInfo.Location.{i}`, and `Device.DeviceInfo` stays with the in-tree handler. `modules/hosts` registers `Device.Hosts.Host.{i}`, and `Device.Hosts.` with `AccessControl` stays in `tr181/Hosts.uc`, because `firewall.uc` renders the access control rules at a fixed point of the firewall rule order.

- Do not register the parent key from a module. The model merge keeps the last writer, so the core `get` would be lost.
- The module does not maintain `<Table>NumberOfEntries` of the parent. For a table with no stored rows, `dispatch_subtree()` in `src/ucode-mod-ubbf/dm.c` counts the rows that the handler enumerated. After the model walk, it writes the count to the parent, if the parent schema declares the key. The count is therefore correct even when the parent handler merges its schema default `"0"`. The parent handler returns `"0"` itself, so that the parameter has a value when the module is not installed; the dispatcher does not fill in the schema default for it.
- A module that refers to a row of such a table depends on the package that provides it, as `ubbf-mod-lldp` and `ubbf-mod-upnp` depend on `ubbf-mod-hosts`. A module without that dependency gets an empty reference while the table is missing: `utils.hosts.host_path_by_mac()` returns `''` (`host_reference_get()` in `datamodel.uc`).
- A runtime table refuses an `Add` from a controller with `addable: false` or `maxInstances: 0` on its `{i}` entry, or `addable: false` or `max_instances: 0` on its schema; `uc_dm_object_add()` honours both. A key of the entry wins over the schema. Source: `schema_entry_addable()` and `schema_entry_max_instances()` in `schema.c`. The runtime discovery of the dispatcher runs only while no row is stored, so an added row would hide the live rows.
- A table with `runtime_instances: true` (stored and runtime rows side by side) refuses a write into a row that is not stored, also when the configuration has no container for the table. USP answers 7013 for a row that exists at run time, 7016 otherwise. Source: `path_runtime_instance_absent()` in `dm.c`, `runtime_row_exists()` in `datamodel.uc`. With `writable_rows: true` as well, a write into a runtime row that the get handler returns stores the row (`runtime_row_live()`); see "Runtime Rows Next to Persisted Rows" in `MODULE-GUIDELINES.md`.
- For the same reason, `uc_dm_params_set()` in `dm.c` refuses a write into a row that is not stored when the table is maintained by the CPE (`addable: false` or `maxInstances: 0`, with a get handler). USP answers 7020. If the written object has a set handler, the dispatcher stores the value as before and calls the handler, so that table must cope with a stored row. Source: `path_runtime_row_write()`.

### Commands on a core parent

A module can add a command or an event to an object that an in-tree handler owns. For example, `modules/packetcapture` adds `PacketCaptureDiagnostics()` to `Device.`, and `Device.` stays with `tr181/Device.uc`.

- Put the commands in a schema of `schema.uc` that has no `path` and no parameters.
- Set `members[<pattern>]` to that schema, for example `members['Device'] = schema('Device_Commands');`. Put the handler in `operations`, as for any other command.
- `entry_members()` in `datamodel.uc` adds the commands to the schema of the core entry when it builds the schema for OBUSPA. `pattern_param_info()` finds them for `param_schema()`.
- Only commands and events join. `commands_add()` ignores a plain parameter, because the dispatcher has no value for it. A parameter of the core object that describes the module, for example `IPLayerCapacitySupported` on `Device.IP.Diagnostics.`, stays in the core schema, and the core get handler reports it (`ip_layer_capacity_caps()` in `tr143/Diagnostics.uc`, from `modules_registered.tr471`).
- The protocol rule for commands applies. In a CWMP image, a command without `protocol: 'cwmp'` or `protocol: 'both'` is removed: by `schema.c` for a table, and by `model_filter()` for a schema object.

### Render templates of modules

A module `render.uc` runs after all in-tree domain templates and before `templates/device.uc`, which writes the shared `network device` sections.

- It can read all values that the in-tree templates computed, through the shared scope and `render_state`.
- It can feed `render_state.device` through `device_state_set()`, the same as an in-tree domain. For example, `modules/usfpd/render.uc` maps `Optical.Interface.{i}.Enable` to `enabled` of the cage netdev.
- Do not write a second `network device` section for the same netdev. `config_device_add()` in netifd applies each section with that name to the same device, one after the other, and `device_set_config()` resets the settings flags each time. A section with only `enabled` then removes the `autoneg`, `speed` or `mtu` that `ethernet.uc` and `ip.uc` set.
- `services.uc` is a global with last-write-wins. If a module calls `services.set_enabled()` on a name that an in-tree template also sets, the module wins because it runs later. A `render_state.device` key that both sides set behaves the same.
- A module can append sections to a package that an in-tree template already rendered, if the UCI order does not change the meaning for that package. For example, `modules/testbed/render.uc` adds its `Allow-Testbed-RPC-*` rules to `firewall`. This is correct because fw4 evaluates every `rule` before the zone forwardings.

### Shadow files

`apply` runs the batch against a copy of `/etc/ubbf/shadow/`. `uci -q batch` drops every line for a package that has no file there, with exit status 0. The batch then shows the section, but `/var/run/uci/<package>` is not created. If a module `render.uc` writes to a package that no in-tree template renders, the module must ship an empty `files/etc/ubbf/shadow/<package>` in its module directory.

Such a package often has no file in `/etc/config` at all, for example `bbf-qos`. The reload trigger of its service still fires, because the `reload_config` of `ubbf-openwrt` compares `/var/run/uci/*` as well as `/etc/config/*`; stock OpenWrt compares `/etc/config` only.

### Packaging

- Each `Package/ubbf-mod-<name>` installs the `.uc` files to `/usr/share/ucode/ubbf/modules/<name>/`, and the schema table `schema-<name>.so` to `/usr/lib/ubbf/` when the build made one. The base package installs `schema-core.so`.
- Each package declares the daemon it needs: `+lldpd`, `+ds-lite`, `+usfpd`, `+qosify`, `+omcproxy`, `+ucode-mdns`, `+ucode-gps`, `+ddns-scripts`. `testbed`, `usb`, `users`, `leds` and `wol` need no daemon. `cellular` pulls ModemManager, its rpcd plugin and the USB modem drivers. `pcp` and `bulkdata` ship their own daemon in `files/` and declare what it uses: `+libpcpnatpmp` with the ucode modules `uloop`, `ubus`, `socket` and `fs`, and `+mosquitto-client-ssl` with `+ucode-mod-zlib`. The base build compiles `pcp.so` and `openssl.so` whether their packages are selected or not, so the feed lists `libpcpnatpmp` and `openssl` in `PKG_BUILD_DEPENDS`. `pty` ships the remote PTY agent `upty` in `files/` and pulls `+uwsc`. `userinterface` pulls the web UI `+ubbf-ui`, and `+ubbf-mod-security` for `certificates.uc`, which resolves its `Certificate` and `CABundle` references. `qos` ships `bbf-qos-apply` with its init script and pulls `+ratelimit`, `+tc` and `+nftables`; see `docs/modules/qos.md`. `syslog` ships the init script of `ubbf-logd`, which starts the daemon in a ujail with only `CAP_NET_BIND_SERVICE` (`files/etc/capabilities/ubbf-logd.json`), installs the binary through `install-extra`, and pulls `+ubbf-mod-security` (see below). `ppp` ships `pppoe-relay` with its init script, installs its BPF object through `install-extra`, and pulls `+ucode-mod-bpf`, `+ucode-mod-struct` and `+kmod-sched-bpf`; see `docs/modules/ppp.md`. `packetcapture` pulls `+tcpdump`. `tr471` pulls `+udpst`. `hosts` pulls `+nlbwmon` for the WAN counters of each host. `lldp` and `upnp` also pull `+ubbf-mod-hosts`, because they refer to rows of `Device.Hosts.Host`. `lldp` also needs the lldpd init script of `ubbf-openwrt`, which runs lldpd on the member ports of the LAN bridge instead of the bridge itself; see `docs/modules/lldp.md`. `easymesh` pulls `+umap-controller` and `+umap-agent`, and with them umapd. `softwaremodules` pulls the container stack, `+uxc`, `+uvol`, `+kmod-fs-ext4`, `+block-mount` and `+kmod-veth`, which the base package pulled before; see `docs/SOFTWARE-MODULES.md`.
- `utils/wifi-dataelements.uc` stays in the base package, because `datamodel.uc` gives it to the `easymesh` handler as `utils['wifi-dataelements']`. The `easymesh_events` plugin of ubbf-device imports it. Without the module, `wifi.uc` still reads `X_UBBF_EasyMesh.Agent.Enable` from the configuration and then renders no SSIDs, as for an agent; `default_config` writes that value only in the `agent` preset.
- `Device.Ethernet.WoLSupported` stays in the core schema, like `IPLayerCapacitySupported`. `ethernet_get()` in `tr181/Ethernet.uc` reports `true` when the handler of the `wol` module registered. `external_modules_register()` records the name of each module that registered in `modules_registered` (`utils/modules.uc`), which a core handler can read. The module sends the magic packet with `send()` of its native `wol` module.
- The package dependency replaces the runtime probe that `optional_modules` in `datamodel.uc` does for in-tree domains: if the module is installed, its daemon is installed too.
- Files that a module needs outside its own directory, for example a shadow file or a `uci-defaults` script, go in `modules/<name>/files/`, as a tree rooted at `/`. The package installs this tree unchanged.
- A native ucode module that only one domain uses is installed by that domain's package, not built into `ubbf.so`. The base package builds it from `src/ucode-mod-<name>/`, and the handler binds it at the top with `require('<name>')`:

  | Library | Package | Functions |
  |---|---|---|
  | `users.so` | `ubbf-mod-users` | accounts, groups, passwords, `rate_limit_check()` |
  | `pcp.so` | `ubbf-mod-pcp` | PCP client for the daemon `ubbf-pcp`, not the agent (`docs/modules/pcp.md`) |
  | `openssl.so` | `ubbf-mod-security` (pulls `+libopenssl`) | certificates |
  | `usb.so` | `ubbf-mod-usb` | `enumerate()`, `device_info()`, `interface_info()`, `net_interfaces()` |
  | `led.so` | `ubbf-mod-leds` | `read_info()` |
  | `wol.so` | `ubbf-mod-wol` | `send()` |
  | `wde.so` | `ubbf-mod-easymesh` | `mac_to_base64()`, `int_to_hexbin()`, `dscp_map_to_hex()`, `bss_index_by_bssid()` |
  | `multicast.so` | `ubbf-mod-multicast` | `mr_cache_parse()` |

  Helpers that such a library shares with `ubbf.so` (`sysfs_read_file()`, `hex_nibble()`, `hex_bytes_parse()`) are in the static library `ubbf_util` (`src/ucode-mod-ubbf/util.c`), which both link. A second source file of a library includes `<ucode/lib.h>` and `<ucode/vm.h>`, not `<ucode/module.h>`, which defines `uc_module_entry()` in every file that includes it.
- Code that a module and a render template share goes in an include-style file of the module, which adds its functions to the object in the include scope. `modules/security/certificates.uc` numbers the certificates for `handler.uc` in the agent, for `modules/userinterface/handler.uc`, and for the `render.uc` of `syslog` and `userinterface` in `apply`, which include it as `../security/certificates.uc`. The `Device.Security.Certificate` instance numbers come from the persistent map `/etc/ubbf/security-instances.json`, so a stored reference keeps its certificate when the CA store changes. A certificate alone in its file is known by the path, one in a file of several by its SHA-256 fingerprint; a number is never given to another certificate. The rows come from `/etc/ssl/certs` (bundle `system-ca`), `/etc/ubbf/ca` (bundle `local-ca`) and the `*.pem` files of `/etc/ubbf`, the device certificates, which no bundle trusts. A module that includes a file of another module depends on that package. `modules/easymesh` splits one domain over several files the same way: `handler.uc` includes them in order, and each file passes the functions that a later file needs through a shared object.
- Another output of the base build, for example a binary or a BPF object, is installed by the optional `Package/ubbf-mod-<name>/install-extra` in the feed Makefile. The `BuildModule` install recipe calls it with the destination directory. `ubbf-mod-syslog` installs `ubbf-logd` this way, and `ubbf-mod-ppp` installs `/lib/bpf/pppoe-relay.o`.
- The domains that moved out of the base package (`ddns`, `usb`, `users`, `pcp`, `bulkdata`, `userinterface`, `qos`, `syslog`, `ppp`, `packetcapture`, `tr471`, `hosts`, `leds`, `security`, `easymesh`, `wol`) default to selected, so an existing board configuration keeps them. A smaller image deselects the package.
- The configuration rows of a domain whose module is not installed stay in `config.json`, for example the QoS shapers that `default_config` writes. Nothing reads them, and a write to such a path fails as for any other unknown path.
- `Device.LANConfigSecurity` belongs to `modules/users`: its `ConfigPassword` is the password of the local account `admin` (TR-181, while `UserInterface.PasswordUserSelectable` is absent), staged like a `Password` write. Without `ubbf-mod-users` the object does not exist.
- The rules in "Rules" above apply to `handler.uc` and the files it includes. A daemon under `modules/<name>/files/` is a normal script and can import `ubbf.*`, for example `ubbf-pcp`, `ubbf-bulkdata` and `bbf-qos-apply`.

### Native modules

The data model handlers of a module can be C instead of `handler.uc`. Such a module is a shared object `/usr/lib/ubbf/dm/<name>.so`, built from `src/dm-modules/`, that exports `struct ubbf_dm_module` (`src/dm-host/ubbf/dm-module.h`). No module uses it yet. A converted module keeps `schema.uc`, `render.uc` and `files/` in its directory, and its `.so` replaces `handler.uc`.

- `native_modules_register()` in `utils/dm-native.uc` runs right after `external_modules_register()`. For each `.so` it starts `/usr/libexec/ubbf/dm-host <so>` with `ubbf.module_spawn()` (`posix_spawn()`, the channel on fd 3) and opens a ubus channel to it with `ubus.open_channel()`. A sync `describe` returns the objects and operations, which the loader adds to the model with get and operation handlers that forward over the channel.
- Each module runs in its own process, so a crash or a hang ends only that process. A request without a reply within 2 s ends it. Restarts follow the procd rule: an exit within 3600 s counts, after more than 5 counted exits the module stays down, otherwise it starts again after 5 s. While a module is down its objects read as absent.
- A get request carries `pattern`, `path`, `instance` (0 for none), the stored `config` and `parent` rows, and the configuration subtrees that the module names in `needs`. The module cannot ask the agent for data during a request: libubus queues a request that arrives while a sync request waits.
- Schema keys resolve through `module_api_build()`, as for a ucode module: the table name when `schema-<name>.so` is open, else the object from `schema.uc`.
- The feed installs `/usr/lib/ubbf/dm/<name>.so` with the `ubbf-mod-<name>` package (`BuildModule`). `dm-host` is in the base package.
- A channel request that arrives after its channel was lost crashed the ucode `ubus` module; the device needs ucode patch 220 of ubbf-openwrt.

### ubbf-device plugins

A module can add a part to the daemon `ubbf-device`, for work that needs a process that runs all the time: system events, timers, state that a request cannot hold. The plugin is a normal ucode module, so the rules for `handler.uc` do not apply to it: it imports `ubbf.*` like the in-tree parts in `device/`.

```
modules/<name>/files/usr/share/ucode/ubbf/device/plugins/<plugin>.uc
```

- `plugins_load()` in `device/plugin-loader.uc` loads each file of `/usr/share/ucode/ubbf/device/plugins/` with `import('ubbf.device.plugins.<plugin>')`. `import()` takes a module name, not a path, and a name allows only letters, digits and `_` (`uc_require_path()` in ucode `lib.c`). A file with another name is logged and skipped, so the file names use `_`, not `-`.
- A plugin exports any of `init()`, `ubus_methods()` and `subscribe()`. The daemon calls `init()` after the in-tree parts, adds the methods to the `bbf-device` object, and calls `subscribe()` after the publish.
- A plugin that does not compile, or whose body or `init()` throws, is logged and left out; the daemon runs on. A method whose name `bbf-device` already has is logged and left out.
- The daemon loads the plugins once at start. A package that is installed later takes effect when ubbf-device restarts.
- Plugins of this repository: `sfp_allow` (`modules/usfpd`, blocks the SFPs that `Device.SFPs.AllowedSFPs` does not allow) and `easymesh_events` (`modules/easymesh`, the umap events of `Device.WiFi.DataElements` and the methods `event_data_status` and `event_data_clear`).
- Host test: `tests/device-plugins.uc`.

## Components

### Schemas (`schemas/*.uc`)

A schema defines the structure of a TR-181 object. Each schema exports an object with these keys:

| Key | Content |
|---|---|
| `path` | TR-181 path pattern, for example `Device.WiFi.Radio.{i}.` |
| `schema` | Parameter types and flags |
| `defaults` | Default values for new instances. A read also shows them for a parameter that is not stored: the get handler merges them, and for an object without a get handler `dispatch_subtree()` adds them, also to a single-instance object below an existing row |
| `constraints` | Optional. The rule of a parameter, keyed by leaf name. See below |
| `since`, `until` | Optional. TR-181 version tags of a member, keyed by member name. See "TR-181 versions" |
| `addable` | Optional, tables only. `false` for a table the CPE maintains itself, which a controller cannot add rows to |
| `max_instances` | Optional, tables only. The row limit of the table |

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

A `schema` value is one integer with a type and the `WRITABLE` bit. Other properties go in `constraints`. `param_schema()` adds them to the answer that all front ends read:

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

The other keys of `constraints` state what TR-181 allows for the value, with the names of the spec: `enum`, `min`, `max`, `ranges` (`[[lo, hi], ...]`, `null` for an open end), `min_length`, `max_length`, `lengths`, `list`, `list_min_length` and `list_max_length`. In a list, the number limits, the enumeration and the lengths apply to each item, and the list lengths to the whole value. A key with the value `null` is absent.

`uc_dm_params_set()` in `dm.c` checks each value against the type and the rule before it stores the value, through `schema_entry_value_ok()` in `schema.c`. It refuses a value that is not a boolean for a boolean, not an integer for an integer type, or outside the rule, logs the reason to stderr, and returns -4. USP answers 7012, the `bbf-dm` operations answer `invalid_value`, and CWMP answers 9007. No other step checks values.

`dm/check_constraints.py` compares the rules and the table facts with the newest `dm/json_spec/<version>/`. It reports a difference as an error, except for the items in its `DEVIATIONS` table.

### Schema tables

A schema that is a ucode object uses memory in each process that loads the data model. The build therefore compiles the schemas into tables, which the processes read in place.

- `src/ucode-mod-ubbf/schema-gen.uc` runs on the build host and writes one C file per table: `schema-core.c` from `schemas/*.uc`, and `schema-<name>.c` from `modules/<name>/schema.uc`. It compiles each rule into a binary record (`struct schema_rule`), and stops the build for an unknown key, a value of the wrong type, or a rule or table fact without its member or table.
- Each C file becomes `/usr/lib/ubbf/schema-<name>.so`. The library holds only data. Its strings are offsets into one pool, so it has no relocations, and its pages stay shared and file-backed. `schema-table.h` defines the records and the symbols.
- `schema.c` in `ubbf.so` opens `/usr/lib/ubbf/schema-*.so` with `dlopen()` at the first lookup. It skips, and logs to stderr, a library that has another `SCHEMA_TABLE_ABI`.
- The core table names a schema `<Module>.<Export>`, for example `IP.Interface`. A module table names it `<name>.<Key>`, for example `pcp.Client`. A lookup uses the module table that the prefix names, else the core table.
- In-tree handlers name their schemas with strings. Module handlers call `ubbf_module.schema()`, which returns the name when the table of the module is open.
- Without tables (CMake option `UBBF_SCHEMA_TABLE=OFF`, or the menuconfig option off), the schemas are ucode objects: `schema_names_resolve()` in `datamodel.uc` replaces each core name with the export of `schemas/`, and `ubbf_module.schema()` includes `schema.uc`. Use this mode for development: an edited schema file takes effect without a build.
- With the tables installed, an edit to a schema file on a device has no effect until the tables are built again.
- `ubbf.schema_tables()` lists the open tables. `ubbf.schema_tables_load(glob)` opens the tables of another directory, for example of a build tree in a host test.

### TR-181 versions

One schema set serves several TR-181 versions. The image build selects one, and the data model shows only the items that exist in it.

- The version is in `/etc/ubbf/tr181-version`, for example `2.20.1`. The build writes it. A developer can edit it and reboot. `utils/dm-version.uc` reads it and exports `DM_VERSION` and `DM_MINOR`. A missing or unknown value selects the first of `DM_VERSIONS`, and `model_filter()` logs it.
- A tag is a string `'2.<minor>'`, for example `'2.21'`. The spec gives no item a patch version, so a tag has none. `since` names the first version with the item. `until` names the first version whose spec marks the item `deleted`; a deprecated or obsoleted item stays. `tag_visible()` in `utils/dm-version.uc` states the rule.
- A model entry has the tags as keys: `{ schema: ..., get: ..., until: '2.21' }`. `model_filter()` in `datamodel.uc` removes the entry and the operations below its pattern.
- A schema has the tags of its members as tables, next to `defaults`: `since: { Available: '2.21' }`. `schema.c` hides such a member for a table, and `entry_project()` in `datamodel.uc` hides it for a schema object. The defaults of a hidden member go too.
- `schema-gen.uc` stops the build for a tag that is not a string `'2.<minor>'`, and for a tag that names no member.
- Handlers do not check the version for this: the core hides the items. A get handler can still return a hidden member: `result_project()` in `dm.c` removes each parameter of a get result that the schema of the entry does not declare. A child object and a key that starts with a dot (internal metadata such as `.instance`) stay. A removed key that the schema does not have at all is logged once per pattern and key to stderr; a member the protocol or the version hides goes without a log line. The subtree that an ancestor handler returns is not filtered yet.

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
| `cache.uc` | Caches function results for one request; `invalidate(fn)` drops the results of one function after a change |
| `curl.uc` | File transfers: `curl_upload()`, `curl_download()`, and `curl_send()` for an HTTP POST or PUT of a body file; credentials go to curl in a 0600 config file, not on the command line; `curl_insecure_allowed()` is the TLS gate of developer images |
| `dhcp.uc` | DHCP lease queries |
| `events.uc` | `dm_event_send(path, args)`, see "Events" below |
| `hosts.uc` | Host table for `Device.Hosts` |
| `ifstats.uc` | TR-181 `Stats` objects from the udevstats counters |
| `logging.uc` | Logging helpers |
| `netifd.uc` | netifd status queries |
| `path.uc` | TR-181 path parsing and interface resolution. A module also gets `utils.path.path_kind(path)`, which is `dm.path_known()`: 0 for a path the model does not describe, 1 for an object, 2 for a parameter |
| `process.uc` | Command execution: `cmd_build()`, `popen_async()`, and `task_run()`, which runs a function in a `uloop.task` and calls its callback once, also when the child dies or runs past `timeout`. Use `task_run()` instead of `uloop.task()`: uloop calls no callback for a child that ends without a message |
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

- [ ] `ubus call bbf-dm names` lists the new objects and parameters.
- [ ] Get and set work through ubus.
- [ ] The render produces valid UCI lines.
- [ ] The services reload as expected.
