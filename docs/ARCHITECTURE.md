# ubbf architecture

This document describes the implementation of ubbf: the directory structure, the module system, the main components and the rules for out-of-tree modules.

## Directory structure

```
files/usr/share/ucode/ubbf/
├── datamodel.uc          # Core engine: get, set, add, delete, transactions
├── ubus-object.uc        # The bbf-dm ubus object
├── usp.uc                # Glue for the USP agent
├── cwmp-dm.uc            # Glue for the CWMP agent
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
├── schedules/            # Device.Schedules; the core handles ScheduleRef, see "Schedule references"
├── hardware/             # Device.Hardware: CPUs from cpufreq, Buttons from gpio-keys; a ubbf-device plugin
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

- `ubbf`: the C module, which also holds the helpers that moved to C, for example `ubbf.log_info()` and `ubbf.active_protocol()`
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
- `modules/cellular`: logs through `ubbf.log_warn()`
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
- The module does not maintain `<Table>NumberOfEntries` of the parent. For a table with no stored rows, `subtree_dispatch()` in `src/ucode-mod-ubbf/dm_get.c` counts the rows that the handler enumerated. After the model walk, it writes the count to the parent, if the parent schema declares the key. The count is therefore correct even when the parent handler merges its schema default `"0"`. The parent handler returns `"0"` itself, so that the parameter has a value when the module is not installed; the dispatcher does not fill in the schema default for it.
- A module that refers to a row of such a table depends on the package that provides it, as `ubbf-mod-lldp` and `ubbf-mod-upnp` depend on `ubbf-mod-hosts`. A module without that dependency gets an empty reference while the table is missing: `utils.hosts.host_path_by_mac()` returns `''` (`host_reference_get()` in `datamodel.uc`).
- A runtime table refuses an `Add` from a controller with `addable: false` or `maxInstances: 0` on its `{i}` entry, or `addable: false` or `max_instances: 0` on its schema; `uc_dm_object_add()` honours both. A key of the entry wins over the schema. Source: `schema_entry_addable()` and `schema_entry_max_instances()` in `schema.c`. The runtime discovery of the dispatcher runs only while no row is stored, so an added row would hide the live rows.
- A table with `runtime_instances: true` (stored and runtime rows side by side) refuses a write into a row that is not stored, also when the configuration has no container for the table. USP answers 7013 for a row that exists at run time, 7016 otherwise. Source: `path_runtime_instance_absent()` in `dm_set.c`, `runtime_row_exists()` in `datamodel.uc`. With `writable_rows: true` as well, a write into a runtime row that the get handler returns stores the row (`runtime_row_live()`); see "Runtime Rows Next to Persisted Rows" in `MODULE-GUIDELINES.md`.
- For the same reason, `uc_dm_params_set()` in `dm_set.c` refuses a write into a row that is not stored when the table is maintained by the CPE (`addable: false` or `maxInstances: 0`, with a get handler). USP answers 7020. If the written object has a set handler, the dispatcher stores the value as before and calls the handler, so that table must cope with a stored row. A table with `runtime_instances` and `writable_rows` stores the write without a set handler, after `runtime_row_live()` confirmed the row. Source: `path_runtime_row_write()`.

### Schedule references

`ScheduleRef` (TR-181 2.18) is a strong reference list from an object to rows of `Device.Schedules.Schedule`, a table of `modules/schedules`. The core handles the parameter for every object that has it, so no object depends on the module, and a new object with `ScheduleRef` needs only its effect in its template. The functions are in `schedule.c` of `ubbf.so`.

- Write: `schedule_ref_checks_install()` in `datamodel.uc` gives each model entry whose schema has `ScheduleRef` a set handler (`schedule_ref_set()`, before the set handler of the entry). An empty value is always valid. Any other value needs the module (`modules_registered.schedules`) and a row for each item, else USP 7012.
- Delete: after each commit, and after a configuration replace or load, `schedule_refs_prune()` removes from every `ScheduleRef` the items whose row no longer exists.
- Render: `schedule_windows(refs, inline_rows)` in the renderer scope returns the fw4 time windows, or null when the object is not scheduled. A disabled row, a row without `StartTime` (a daily allowance, not supported: its `Status` is Error) and all rows while `Device.Schedules.Enable` is false count as not referenced. Without the module (no `modules/schedules/handler.uc`) every `ScheduleRef` counts as empty. A window past midnight continues on the next day; `InverseMode` uses the rest of the week. `rule_window_set()` in `render/uci_helpers.uc` writes `start_time`, `stop_time` and `weekdays` of a window to the last fw4 rule.
- Users: `firewall-acl.uc` (`Hosts.AccessControl`: an ACCEPT rule per window before the block pair; until 2.21 also the inline `AccessControl.{i}.Schedule` rows) and `firewall-pinholes.uc` (a rule per window). `pinhole_get()` in `tr181/Firewall.uc` reports `Status` Inactive outside the windows. `NAT.PortMapping` and `NAT.PortTrigger` have no `ScheduleRef` in their schemas yet.
- nft turns the local times of `meta hour` into UTC when the firewall loads; a change of daylight saving time takes effect at the next firewall reload.

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
- Each package declares the daemon it needs: `+lldpd`, `+ds-lite`, `+usfpd`, `+qosify`, `+omcproxy`, `+ucode-mdns`, `+ucode-gps`, `+ddns-scripts`. `testbed`, `usb`, `users`, `leds`, `wol` and `schedules` need no daemon. `hardware` ships a ubbf-device plugin and the hotplug script `/etc/hotplug.d/button/50-ubbf-hardware`, which forwards the button events of gpio-button-hotplug to it. `cellular` pulls ModemManager, its rpcd plugin and the USB modem drivers. `pcp` and `bulkdata` ship their own daemon in `files/` and declare what it uses: `+libpcpnatpmp` with the ucode modules `uloop`, `ubus`, `socket` and `fs`, and `+mosquitto-client-ssl` with `+ucode-mod-zlib`. The base build compiles `pcp.so` and `openssl.so` whether their packages are selected or not, so the feed lists `libpcpnatpmp` and `openssl` in `PKG_BUILD_DEPENDS`. `pty` ships the remote PTY agent `upty` in `files/` and pulls `+uwsc`. `userinterface` pulls the web UI `+ubbf-ui`, and `+ubbf-mod-security` for `certificates.uc`, which resolves its `Certificate` and `CABundle` references. `qos` ships `bbf-qos-apply` with its init script and pulls `+ratelimit`, `+tc` and `+nftables`; see `docs/modules/qos.md`. `syslog` ships the init script of `ubbf-logd`, which starts the daemon in a ujail with only `CAP_NET_BIND_SERVICE` (`files/etc/capabilities/ubbf-logd.json`), installs the binary through `install-extra`, and pulls `+ubbf-mod-security` (see below). `ppp` ships `pppoe-relay` with its init script, installs its BPF object through `install-extra`, and pulls `+ucode-mod-bpf`, `+ucode-mod-struct` and `+kmod-sched-bpf`; see `docs/modules/ppp.md`. `packetcapture` pulls `+tcpdump`. `ieee8021x` pulls `+ubbf-mod-security` for the `EAPTLS` references and ships a ubbf-device plugin, which adds `driver=wired` interfaces to the wpad daemon through `wpa_supplicant config_add`; the agent reads them through `wpa_supplicant.<netdev> eapol_status` (a method of the `wpa_supplicant.uc` of ubbf-openwrt). The wpad must be a full variant: the basic and mini variants build wpa_supplicant without EAPOL, EAP-MD5 and EAP-TLS, and hostapd without a RADIUS client. The `render.uc` of the module sets the netifd option `auth` on the port of each `X_UBBF_Authenticator` row that can run (`templates/device.uc` writes it), so netifd keeps the port out of the bridge until the plugin reports an authorised station. `tr471` pulls `+udpst`. `hosts` pulls `+nlbwmon` for the WAN counters of each host. `lldp` and `upnp` also pull `+ubbf-mod-hosts`, because they refer to rows of `Device.Hosts.Host`. `lldp` also needs the lldpd init script of `ubbf-openwrt`, which runs lldpd on the member ports of the LAN bridge instead of the bridge itself; see `docs/modules/lldp.md`. `easymesh` pulls `+umap-controller` and `+umap-agent`, and with them umapd. `softwaremodules` pulls the container stack, `+uxc`, `+uvol`, `+kmod-fs-ext4`, `+block-mount` and `+kmod-veth`, which the base package pulled before; see `docs/SOFTWARE-MODULES.md`.
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
- Code that a module and a render template share goes in an include-style file of the module, which adds its functions to the object in the include scope. `modules/security/certificates.uc` numbers the certificates for `handler.uc` in the agent, for the handlers of `userinterface` and `ieee8021x`, for the `render.uc` of `syslog`, `userinterface` and `ieee8021x` in `apply`, which include it as `../security/certificates.uc`, and for the ieee8021x plugin of `ubbf-device`. The `Device.Security.Certificate` and `CABundle` instance numbers come from the instance map (see "Instance numbers of runtime rows"), and config.json pins the ones that a stored reference names, so the reference keeps its certificate when the CA store changes. `certificates.uc` calls the instance map of `ubbf.so`, which numbers new certificates in the agent and only reads the numbers in `apply` and `ubbf-device`. A certificate alone in its file is known by the path, one in a file of several by its SHA-256 fingerprint; a number is never given to another certificate. The rows come from `/etc/ssl/certs` (bundle `system-ca`), `/etc/ubbf/ca` (bundle `local-ca`) and the `*.pem` files of `/etc/ubbf`, the device certificates, which no bundle trusts. A module that includes a file of another module depends on that package. `modules/easymesh` splits one domain over several files the same way: `handler.uc` includes them in order, and each file passes the functions that a later file needs through a shared object.
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
- Plugins of this repository: `ieee8021x` (`modules/ieee8021x`, runs a wired wpa_supplicant interface for each enabled `Device.IEEE8021x.Supplicant` row and carries out `StartFailurePolicy` and `AuthenticationSuccessPolicy`; runs a wired hostapd interface for each enabled `Device.IEEE8021x.X_UBBF_Authenticator` row and opens the port with `network.device set_state` while hostapd authorises a station on it), `sfp_allow` (`modules/usfpd`, blocks the SFPs that `Device.SFPs.AllowedSFPs` does not allow), `easymesh_events` (`modules/easymesh`, the umap events of `Device.WiFi.DataElements` and the methods `event_data_status` and `event_data_clear`) and `hardware` (`modules/hardware`, the button state and trigger conditions of `Device.Hardware.Buttons`, and the stored cpufreq settings; methods `button_event`, `button_simulate`, `hardware_status`).
- Host tests: `tests/device-plugins.uc`, `tests/sysfs/hardware-plugin.uc`, `tests/ieee8021x-plugin.uc`.

## Components

### Schemas (`schemas/*.uc`)

A schema defines the structure of a TR-181 object. Each schema exports an object with these keys:

| Key | Content |
|---|---|
| `path` | TR-181 path pattern, for example `Device.WiFi.Radio.{i}.` |
| `schema` | Parameter types and flags |
| `defaults` | Default values for new instances. A read also shows them for a parameter that is not stored: the get handler merges them, and for an object without a get handler `subtree_dispatch()` adds them, also to a single-instance object below an existing row |
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

`uc_dm_params_set()` in `dm_set.c` checks each value against the type and the rule before it stores the value, through `schema_entry_value_ok()` in `schema.c`. It refuses a value that is not a boolean for a boolean, not an integer for an integer type, or outside the rule, logs the reason to stderr, and returns -4. USP answers 7012, the `bbf-dm` operations answer `invalid_value`, and CWMP answers 9007. No other step checks values.

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
- Handlers do not check the version for this: the core hides the items. A get handler can still return a hidden member: `result_project()` in `dm_get.c` removes each parameter of a get result that the schema of the entry does not declare. A child object and a key that starts with a dot (internal metadata such as `.instance`) stay. A removed key that the schema does not have at all is logged once per pattern and key to stderr; a member the protocol or the version hides goes without a log line. The subtree that an ancestor handler returns is not filtered yet.

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

### Instance numbers of runtime rows

A table whose rows the CPE finds at run time (cages, USB devices, modems, hosts, sessions) numbers them through the instance map of `ubbf.so` (`map.c`; callers import `instance_numbers()` and the other functions from `ubbf`, modules call `ubbf.instance_*()`). The map holds a stable key per row, for example a cage name, and the next free number of each table, so a row keeps its number while other rows come and go, and a number is not given to another row (TR-369 R-ARC.8). A nested table has its own map, named by the table path with the numbers of its parent rows, for example `Device.USB.USBHosts.Host.2.Device`.

- The map lives in `/tmp/ubbf/instance-map.json` only. A reboot ends a runtime row that the configuration does not store or name, and the row can come back with another number.
- Each entry holds the number and `last_seen`, the monotonic time a read last saw its key (refreshed at most every 3 hours, so a read rarely writes the map). `instance_numbers()` takes every key present and removes the keys that no read saw for 24 hours, so a table of clients that come and go does not grow until the next reboot; the table's `next` stays, so the number is not given to another row, and a client that comes back later gets a new one. A key that `config.json` pins (`_instances`) and a retired key (`#n`) stay. `instance_number()` numbers one key for a caller that does not know the other rows present, and removes nothing.
- Only the agent (obuspa or cwmp-dm) gives out numbers: `datamodel.uc` calls `instance_map_own(true)`. In another process (`apply`, `ubbf-device`) the same functions only read: `instance_numbers()` returns the numbers the map holds, and `instance_prune()`, `instance_retire()` and the number of a `dm.object_add()` (`instance_map_add_number()` in `map.c`) change nothing. A process reads the file again when another process wrote it (inode, mtime and size). When the file is missing, after a reboot, the first process that reads the map seeds it from the `_instances` section of `config.json`, so a render before the agent starts resolves the pinned numbers.
- `config_persist()` writes an `_instances` section next to `Device` in `config.json`: for each mapped table, the numbers and keys of the rows that the configuration stores (rows written through `writable_rows`) and of the rows that a stored string names (`Device.<table>.<n>`, also in a comma list). `instance_pins_new()` in `map.c` computes it from the live map, so the same configuration gives the same section, and the digest check writes `config.json` only when the configuration or its pins change. A string that only looks like a path, for example in a Description, reserves its number as well.
- At each load, `dm.config_load()` takes the section out of the live tree and seeds the map with it (`config_pins_take()` in `config.c`): a pinned key gets its number back, and the number stays reserved while the row is absent. A whole-file restore (`config_replace()`) does the same with the section of the restored file.
- A handler of a table with stored and runtime rows passes `instance_floor()` of the stored table, one above its highest stored row, so that the rows the CPE finds follow the stored rows.
- Stored and runtime rows of a table share one pool of numbers. A controller add goes through `dm.object_add()`: for a table that the map numbers, the add takes the next number of the map (`instance_map_add_number()` in `map.c`), so no runtime row gets it afterwards. Other tables take the lowest number that no stored row holds (`instance_next_free()` in `instance.c`).
- A table whose stored rows describe live entries that need no number of their own across a reboot uses `instance_stack()` and no map: a stored row keeps its number and takes the live entry that it names, and the other entries follow the highest stored row in the order the source gives. `IP.Interface.{i}.IPv4Address`, `IPv6Address` and `IPv6Prefix` do this (`ipv4_items()`, `ipv6_address_items()`, `ipv6_prefix_items()` in `tr181/IP.uc`): a row with an address takes that address, a DHCP or DHCPv6 row the lease (odhcp6c gives a lease as /128). `interface_get()` and the per-row getters number through the same function, so the two views agree.
- `WiFi.DataElements.Network.Device` is on the map by AL MAC (`devices_numbered()` in `modules/easymesh/dataelements.uc`; the operations resolve a number with `device_by_instance()`), so a stored row of a device stays with it when the topology changes order. An EasyMesh SSID keeps the number it got when `SetSSID()` added it (`instance` in its `EasyMesh.SSIDs` entry); outside EasyMesh, `Network.SSID.{i}` has the number of its `WiFi.SSID` row.
- Tables whose rows a controller reaches by number, in a later read, a reference or an operation, are on the map by a key of the row: `DHCPv4.Server.Pool.{i}.Client` by MAC (`pool_leases_numbered()`) and `DHCPv6.Server.Pool.{i}.Client` by DUID (`ipv6_pool_clients_numbered()`, both in `utils/dhcp.uc`), which `Hosts.Host.{i}.DHCPClient` also uses; `WiFi.AccessPoint.{i}.AssociatedDevice` by MAC (`stations_numbered()`, `station_number()` in `utils/wifi.uc`), which `Hosts.Host.{i}.AssociatedDevice` also uses; the EasyMesh `BSS` by BSSID and `STA` by MAC (`bss_by_instance()`, `sta_by_instance()` in `modules/easymesh/objectdata.uc`, scoped by radio and BSS identity), which the BSS and STA operations use.
- The records of `DeviceInfo.ProcessFaults`, `KernelFaults` and `Reboots` carry an `id` in their stores under `/etc/ubbf`, the instance number of the row, so `Remove()` and the rotation of a full store move no other row (`instance_ids()`). `ubbf-device` gives the ids; a record without one gets the next number in list order, the same in every reader. The fault stores keep the next id in `meta.next_id`; the reboot store takes the highest id + 1, so the id of the newest reboot comes back after it is removed.

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
| `curl.uc` | File transfers: `curl_upload()`, `curl_download()`, and `curl_send()` for an HTTP POST or PUT of a body file; credentials go to curl in a 0600 config file, not on the command line; `curl_insecure_allowed()` is the TLS gate of developer images |
| `dhcp.uc` | DHCP lease queries |
| `events.uc` | `dm_event_send(path, args)`, see "Events" below |
| `hosts.uc` | Host table for `Device.Hosts` |
| `ifstats.uc` | TR-181 `Stats` objects from the udevstats counters |
| `netifd.uc` | netifd status queries |
| `path.uc` | TR-181 path parsing and interface resolution. A module also gets `utils.path.path_kind(path)`, which is `dm.path_known()`: 0 for a path the model does not describe, 1 for an object, 2 for a parameter |
| `schedule.uc` | Time windows of schedule rows and the `ScheduleRef` handling, see "Schedule references" |
| `process.uc` | Command execution: `popen_async()` and `task_run()`, which runs a function in a `uloop.task` and calls its callback once, also when the child dies or runs past `timeout`. Use `task_run()` instead of `uloop.task()`: uloop calls no callback for a child that ends without a message |
| `wifi.uc` | Wi-Fi status and capabilities |

In `src/ucode-mod-ubbf/`, the `ubbf.dm` resource has five files:
- `dm.c`: the resource, the transactions, the config and its digest.
- `dm_get.c`: reads, the subtree dispatch and the instance refresh.
- `dm_set.c`: writes, `object_add()` and `object_del()`.
- `dm_names.c`: the names and `path_known()`.
- `dm_model.c`: the model lookups that the other files share.

`dm-priv.h` holds their shared declarations. `ubbf.h` declares the C functions that the files of the module share, and `bindings.h` the functions that `ubbf.c` exports to ucode.

Helpers that moved to C are functions of `ubbf.so`, and callers import them from `ubbf` directly; no `utils/` file passes them on. `log.c`: `log_init(ident)`, `log_debug()` ... `log_err()` with ucode `sprintf()` formats, and `log_exception(path, e)`, through libubox ulog to syslog (and to stderr on a terminal) and a udebug ring of 64 KiB / 512 entries per process; C code calls `ubbf_log()`. `protocol.c`: `active_protocol()` (`'cwmp'` or `'usp'`) and `cwmp_mode()`, from the presence of `/usr/sbin/cwmpd`; C code calls `ubbf_cwmp_mode()`. `config.c`: `config_path_check(path)` (a reason string for a path that is not absolute or holds `.` or `..`, else null), `config_validate(path)` (dry run of `/usr/libexec/ubbf/apply`, `{ success, output }`), `config_restore(path, done)` through the hook that `datamodel.uc` sets with `config_restore_hook_set(fn)`. `tree.c`: `ethernet_interface_path(root, netdev)`, the `Device.Ethernet.Interface` row of a netdev or `''`. C code runs a program without a shell and reads its output with `spawn_output()` in `proc.c`. `order.c`: `order_snapshot(data)` and `orders_compute(data, before)`, the TR-181 data type Order for the tables that have it (an entry without a value goes last, a taken value moves the entries from it on down by one, a deletion compacts). `schema.c`: `schema_extract(model, members_get)` (`{ objects, events }` for the USP core) and `schema_param_info(schema, name)`, for a schema table name and for the object schema of a module without a table. Shared helpers: `text_clamp(value, max)` (`string.c`), `datetime_format(ts)` (`time.c`, `0001-01-01T00:00:00Z` for no time), `upstream_interface_ref(root)`, `lower_layers_wifi(lower_layers)` and `port_snooped(port)` (`tree.c`), `transfer_complete(ctx, fault)` (`protocol.c`: the `TransferComplete!` event and `ctx.complete()`). A module calls them as `ubbf_module.ubbf.<name>()`. `gate.c`: `write_gate_create(busy, schedule, on_error)`, the gate that queues the writes made while a USP transaction holds the config (`write(job, done)`, `release()`, `drain()`; `schedule(gate)` must call `gate.drain()` after the current event). `write_reply()` in `utils/write-gate.uc` stays in ucode, because it passes the gate a new closure over the ubus request. `cache.c`: `cache_call(fn, ...args)` keeps results for 2 s after the first result (a libubox uloop timer clears the cache), `cache_invalidate(fn)` drops the results of one function after a change. `cmd_build(parts)` (`string.c`) builds a shell command from an argv-style list. `rtnl.c` (libnl-tiny, route netlink): `link_local_addresses_get(dev)` and `ra_prefixes_get(dev)`, the kernel IPv6 link-local addresses and RA prefix routes of a device, and `bridge_fdb_parse()` and `ipv6_neigh_parse()`, the bridge FDB and the IPv6 neighbours by MAC for `utils/hosts.uc`. `ethtool.c` (libnl-tiny, ethtool generic netlink): `ethtool_properties_get(dev)` (link modes, duplex, MDI-X) and `ethtool_stats_get(dev)` (`{ mac, rmon, hist_rx }`); `tr181/Ethernet.uc` maps the statistics in `rmon_stats_build(ctx, stats_fetch)`, which the host test calls with fixtures. Both send their requests through `nl_request_run()` in `netlink.c`, which reads the reply up to the ACK or the end of the dump. `uci_track.c`: `uci_change_update(dir, state_path)` (the apply pipeline hashes the rendered UCI files; a time moves only when the MD5 changes) and `uci_last_changed(config)`. `sys.c`: `deviceinfo_get()`, `/etc/usp/deviceinfo.json`, read once per VM. Persistence of the live config: `dm.config_load(path)` loads `config.json`, takes the `_instances` pins out (`config_pins_take()` in `config.c`, also a binding for `config_replace()`) and sets the digest over the canonical content; `dm.config_persist(path, runtime_path, mode)` writes the runtime copy each time and the persistent file (atomic) only when the SHA-256 (libmd) of the content changes. `config_persist()` in `datamodel.uc` adds the `bbf-dm.digest` ubus event. `dm.names_compute()` sets the derived `Name` of rows through the `name` callbacks of the model until a pass changes nothing; `dm.wildcard_expand(path)` expands `*` instance segments over the rows of the runtime tree; `ubbf.tree_leaves(node, prefix, out)` flattens a subtree into leaf paths. Callers add rows with `dm.object_add()` directly. The transactions stay in `datamodel.uc`: they run the hooks and the `bbf-device` apply over ubus. `acl.c`: the web UI ACL (`acl_role_load`, `acl_can_write`, `acl_can_add`, `acl_can_diagnose`, `acl_filter_tree`); a role file is read again when it changes. `status.c`: `ifop_status_derive(enable, ifname, lower_layers, root, ssid_ifname)` and `bridge_status_derive(enable, ifname)`; the caller passes `ssid_ifname_get()` of `utils/wifi.uc`, which reads the wireless status over ubus, to resolve WiFi.SSID lower layers. `firewall_reconcile.c`: `firewall_reconcile(model, root)` runs the `firewall` hooks of the model entries and adds, adopts or removes the `Device.Firewall.Service`, `InterfaceSetting` and `Policy` rows they claim, and gives every `Firewall.Level` a Chain. `firewall.c`: `chain_rules_ordered()`, `firewall_set_resolve()`, `chain_rule_set_matches()` and `chain_rule_unsupported()` for the fw4 render, `firewall_rules_expired()` and `firewall_expiry_next()` for `ExpiryDate`; the UCI helpers `rule_window_set()` and `redirect_emit_reflection()` are in `render/uci_helpers.uc`. `schedule.c`: the week schedules (`schedule_intervals()`, `schedule_windows()`, `schedule_state()`, the check and pruning of `ScheduleRef`). `routing.c`: `router_table_id()`, the source tables of IPv4Forwarding rows with a source (`source_tables()`, `source_table_contents()`, `source_rules()`, `main_source_rules()`), `policy_resolve()` for `Device.Routing.Policy`, and the constants `MAIN_TABLE`, `SOURCE_TABLE_BASE` and `SOURCE_TABLE_MAX` as members of the module. `nptv6.c`: `prefix6_parse()`, `prefix6_contains()` and `nptv6_setting_check()` for `Device.NAT.NPTv6.InterfaceSetting`. `sfp.c`: `sfp_type_resolve()` and `sfp_allowed()` for `Device.SFPs`, shared by `modules/usfpd` and the `sfp-allow` plugin of ubbf-device, and the constant `SUPPORTED_SFP_TYPES`. `ssh_keys.c`: `key_acceptable(key, accepted, min_rsa_bits)`, the check of an authorized_keys line before the render deploys it; `KEY_TYPES` and `MIN_RSA_BITS` stay in `utils/ssh_keys.uc`, which `schemas/SSH.uc` imports. `dns.c`: `dns_learned_row(row)` for `Device.DNS.Client.Server` and `Device.DNS.Relay.Forwarding`; the resolv file paths stay in `utils/dns.uc`. `wifi.c`: `freq_to_channel()`, `antenna_count()`, `txpower_pct_to_dbm()`, the htmode helpers (`standards_to_highest()`, `standards_bandwidth_to_htmode()`, `clamp_htmode()`, `channel_width_to_bandwidth()`), `band_to_uci()`, `band_to_index()`, `radio_address_derive()`, `dscp_parse()` and `qos_map_set_render()`. `wifi_phy.c`: the capabilities of a wiphy per band from its iwinfo description (`phy_max_standard()`, `phy_supported_bandwidths()`, `phy_max_bandwidth()`, `phy_max_ssids()`, `phy_max_bitrate()`, `phy_max_txpower()`, `phy_supported_bands()`, `phy_supported_standards()`, `phy_possible_channels()`, `channel_valid_for_bandwidth()`). `wifi_psk.c`: `wpa_psk(passphrase, ssid)`, PBKDF2-HMAC-SHA1 with libmd, with a cache of 32 keys. `ifstats.c`: `ifstats_build(replies, full)`, the Stats object of the sum of udevstats replies, and `ip_interface_members(root, iface)`; `utils/ifstats.uc` keeps the udevstats ubus calls. `ipv6.c`: `prefix_length_nibble_check(len)`, `ra_prefixes_hook_read(iface)` (the state file of the odhcp6c hook) and `ipv6_prefix_rows_build(name, upstream, netifd6, l2_dev)`; `ipv6_prefix_rows()` in `utils/ipv6.uc` passes it the netifd status. `dhcp.c`: `leases_parse()`, `pool_leases_by_key(pool)` (the DHCPv4 pool numbering keys), `ipv6_leases_by_mac(raw)`, `ipv6_pool_clients_build(status, raw)`, `static_address_states(root)`, `dhcp_option_value()` and `hex_to_printable()`; `utils/dhcp.uc` keeps the ubus reads, their caches and the `instance_rows()` calls. `hosts.c`: the maps of the host scan (`hosts_leases_by_mac()`, `hosts_ap_ssids()`, `ipv6_maps_merge()`, `netifd_interfaces_build()`, `ap_by_ssid_instance()`), `pool_client_paths()` for `Hosts.Host.{i}.DHCPClient`, the ActiveLastChange state in `/tmp/ubbf/hosts-state.json` (`hosts_state_load()`, `host_active_track()`, `hosts_downstream_build()`, `hosts_inactive_drop()`, `hosts_state_flush()`) and `host_path_by_ip_find()`; `utils/hosts.uc` keeps the ubus and iwinfo reads, the caches, the numbering and `station_number()`. `wifi_dataelements.c`: the HT, VHT and HE capability encoders (`ht_caps_encode()`, `vht_caps_encode()`, `sta_he_caps_build()`, `sta_he_caps_from_nl80211()`, `sta_he_caps_from_flags()`, `sta_he_caps_from_frame_body()`), `chipset_vendor_get()`, the builders from iwinfo and nl80211 data (`radio_survey_build()`, `radio_capability_build()`, `local_sta_data_build()`), `topology_devices_build()` and `device_api_data_build()` for the umap replies; `utils/wifi-dataelements.uc` keeps the iwinfo, nl80211 and ubus reads, `find_phy()` and the caches. `curl.c`: `curl_download()`, `curl_upload()`, `curl_send()`, `curl_exit_to_status()`, `curl_insecure_allowed()` and the constant `CURL_TRANSFER_TIMEOUT_S`; curl runs through `spawn_output()` without a shell, the credentials go in a curl config file of mode 0600. `process_spawn()` in `proc.c` uses `posix_spawnp()`, so a bare program name is looked up in PATH. `utils/wifi.uc` keeps the ubus and iwinfo reads, the station numbering, `phy_for_band()` (reads `iwinfo.phys`) and `mld_links_select()` (takes a callback).

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

- [ ] A host test in `tests/` (see Host tests below) covers the handler and the render.
- [ ] `ubus call bbf-dm names` lists the new objects and parameters.
- [ ] Get and set work through ubus.
- [ ] The render produces valid UCI lines.
- [ ] The services reload as expected.

## Host tests

The ucode host tests in `tests/*.uc` use utest (the `ucode-utest` package). `tests/run.sh <host build of src/ucode-mod-ubbf>` runs them in one private mount namespace: the source tree is laid out below `/usr/share/ucode/ubbf`, `/etc`, `/run`, `/tmp` and `/var/log` are empty tmpfs, and the tests of `tests/sysfs/` run once more with an empty tmpfs on `/sys`. Without a bundle it also runs `src/ucode-mod-ubbf/test_ubbf_mod.uc`, the test of the native modules, with its own `utest.config.uc`: it needs the real `usb` and `users` modules, which `tests/lib/` stands in for. Extra arguments go to utest, for example `-r compact`, `-f <regex>` or a bundle such as `tests/hosts.uc`.

- `utest.config.uc` mocks `ubus` and `uci`. A test steers them with `mock.global.patch()`; `tests/lib/netifd_mock.uc` gives the netifd status of a map of interfaces.
- `tests/lib/` holds one stand-in for each module the host lacks (`iwinfo`, `nl80211`, `udebug`, `wifi.utils`, `uwsc`, `wde`, `usb`, `users`) and `state_clear()`, which empties `/tmp/ubbf` and `/etc/ubbf` for a test that needs a clean state: all files of a run share the namespace.
- `tests/bin/` holds stand-in programs (`curl`, `resolveip`, `lldpcli`, `tc`, `apk`, `uxc`), first in PATH; `run.sh` exports the paths they log to.
- utest shuffles the tests of a file, so a test does not depend on another; a sequence of dependent steps is one test.
- The C code of `src/ucode-mod-ubbf` has its own cmocka tests (`ctest` in a build with `UBBF_UNIT_TESTS`).
