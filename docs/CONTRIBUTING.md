# Contributing to ubbf

ubbf implements the TR-181 device data model for OpenWrt. It connects the USP and CWMP management agents to the UCI configuration of OpenWrt. The code is written in ucode, the JavaScript-like script language of OpenWrt.

## Data flow

```
USP / CWMP agent --> datamodel.uc --> tr181/*.uc (handlers) --> schemas/*.uc
config.json --> renderer.uc --> render/templates/*.uc --> UCI batch --> services
```

All paths below are relative to `files/usr/share/ucode/ubbf/`.

| Directory | Content |
|---|---|
| `datamodel.uc` | The core engine. It imports all handlers. |
| `tr181/` | TR-181 domain handlers (Wi-Fi, Ethernet, DNS, Firewall and others) |
| `tr143/` | TR-143 diagnostic handlers |
| `schemas/` | TR-181 schema definitions |
| `render/templates/` | Templates that generate UCI |
| `utils/` | Shared utilities |

Some domains are packaged separately as `ubbf-mod-<name>`. Their source is in `modules/<name>/` at the top level of the repository. A module gets its helpers through a scope, not through imports. Read "Out-of-tree modules" in `docs/ARCHITECTURE.md` before you change a module.

## Development

- ubbf runs on OpenWrt devices only. A local run on the build host is not possible.
- The command line tool on the device is `bbf-cli`. See `docs/CLI.md`.
- The schemas in `schemas/` are maintained by hand, although their headers say that a generator made them. Do not run the generator. See "TR-181 Schema Files" in `README.md`.
- At runtime, ubbf writes `/tmp/ubbf/schema.json` and `/tmp/ubbf/uci.batch`.
- Each function must have a JSDoc comment.

## Code patterns

### Handler context

Each `get` handler receives a context object:

```javascript
function handler_get(ctx) {
    ctx.instance  // Instance number, for example 1 for Device.WiFi.Radio.1
    ctx.config    // Stored configuration of this instance
    ctx.parent    // Configuration of the parent object
}
```

### Shared render state

Templates share computed values through the render state:

```javascript
device_state_set(render_state, name, 'speed', '1000');
let speed = render_state.device[name].speed;
```

`device_state_set()` and `device_state_list_add()` are in `render/helpers.uc`.

### Type conversion

TR-181 stores every value as a string. Use the helpers to convert:

```javascript
ubbf_to_bool(value)  // "true" or "false" to true or false
ubbf_to_int(value)   // "123" to 123
```

### Interface resolution

`lower_layer_resolve(config, interface_path)` resolves a TR-181 interface reference to a system interface.

### Configuration traversal

```javascript
ubbf_get(config, 'Device.WiFi.Radio.1')      // One object
ubbf_instances(config, 'Device.WiFi.Radio')  // All instances
```

## Common tasks

### Add a parameter to a handler

1. Add the parameter to the schema in `schemas/<Domain>.uc`.
2. Add a default value if the parameter needs one.
3. If the parameter has runtime data, update the `get` handler in `tr181/<Domain>.uc`.
4. If the parameter changes the UCI output, update the render template.

### Add a render template

1. Create `render/templates/<name>.uc`. Put all logic in a `render_config()` function and call it at the end of the file. A template has no top-level imports; its helpers come through the scope that `renderer.uc` builds.
2. Append UCI batch lines to the shared `output` array with the `uci_set_*`, `uci_named_section` and `uci_comment` helpers.
3. Add `include('templates/<name>.uc', scope);` to `renderer.uc`.
4. In the template, call `services.set_enabled()` for each service that the template configures. `apply` then enables and starts, or disables and stops, each service and runs `reload_config`.

### Add a diagnostic operation

1. Create the handler in `tr143/<Name>.uc`.
2. Implement the operation as an asynchronous state machine.
3. Register the handler with the operation handlers in `datamodel.uc`.
4. If the operation runs an external process, add a helper in `files/usr/libexec/ubbf/`.

### Extend the ubus API

1. Add the method to `ubus-object.uc`, with a JSDoc comment on its handler.
2. If the web UI needs access, add the ACL rules in `acl.uc`.

## Documentation

Read the related documents before you change code:

| Document | Content |
|---|---|
| `docs/ARCHITECTURE.md` | Implementation details, directory structure, module system, checklist for new domains |
| `docs/MODULE-GUIDELINES.md` | Handler requirements, mandatory utilities, verification checklist |
| `docs/CLI.md` | `bbf-cli` usage and operations |
| `docs/ACL-FORMAT.md` | Web UI ACL format |
