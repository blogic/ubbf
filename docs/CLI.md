# bbf-cli Reference

`bbf-cli` is the command-line client of the UBBF TR-181 data model. It runs on the device. Each command sends one ubus call to the `bbf-dm` object or to the `bbf-device` object.

## Synopsis

```
bbf-cli <command> [args...]
bbf-cli -h | --help
```

## Commands

| Command | Description | ubus call |
|---------|-------------|-----------|
| `show [path]` | Show the data model tree (default: `Device.`) | `bbf-dm show` |
| `get <path> [path...]` | Get one or more parameter values | `bbf-dm get` |
| `set <path> <value>` | Set one parameter value | `bbf-dm set` |
| `add <path>` | Add an instance to a multi-instance object | `bbf-dm add` |
| `del <path>` | Delete an instance of a multi-instance object | `bbf-dm del` |
| `operate [path] [input...]` | Run an operation, or list the operations | `bbf-dm operate` |
| `batch <json>` | Run set, add and del operations in one transaction | `bbf-dm batch` |
| `apply [options] [file]` | Apply a configuration file | `bbf-dm apply` or `bbf-device apply` |
| `reboot` | Reboot the device | `bbf-device reboot` |
| `factory` | Reset the device to factory defaults | `bbf-device factory_reset` |
| `upgrade <file>` | Upgrade the firmware | `bbf-device sysupgrade` |

## Output and Exit Status

- `bbf-cli` writes the reply of the ubus call to stdout as formatted JSON.
- If the arguments are not valid, `bbf-cli` writes an error message to stderr and to the system log. The exit status is then 1.
- An error that the ubus object reports is part of the JSON reply, for example `{ "error": "readonly" }`. The exit status is then 0, except for `apply`.
- If the ubus call fails or times out, `bbf-cli` prints nothing. The ubus call times out after 30 seconds.
- Without a command, `bbf-cli` prints the usage text and exits with status 1. With `-h` or `--help`, the exit status is 0.

---

## Browsing the Data Model

### show

```
bbf-cli show [path]
```

Shows the data model subtree at `path` as a nested JSON object. The tree contains the stored configuration and the runtime state. If you do not give a path, `bbf-cli` uses `Device.`.

```bash
bbf-cli show
bbf-cli show Device.WiFi.
bbf-cli show Device.DeviceInfo.
```

### get

```
bbf-cli get <path> [path...]
```

Gets the values of one or more parameters. A path can name one parameter or one object. An object path ends with a dot. For an object path, `bbf-cli` returns all parameters below that object, including the runtime state.

```bash
bbf-cli get Device.DeviceInfo.ModelName
bbf-cli get Device.WiFi.Radio.1.Channel Device.WiFi.Radio.1.Enable
bbf-cli get Device.DeviceInfo.
```

The reply is a flat JSON object. Each key is a full parameter path and each value is the parameter value:

```json
{
    "Device.DeviceInfo.ModelName": "OpenWrt Router",
    "Device.DeviceInfo.SerialNumber": "ABC123"
}
```

---

## Changing the Configuration

`set`, `add`, `del` and `batch` each run in one transaction. If the transaction changes the stored configuration, `bbf-dm` applies the new configuration to the system. Thus you do not need to run `apply` after these commands. The system applies the change approximately 1 second after the reply.

If an operation fails, `bbf-dm` aborts the transaction and the configuration does not change. The error is one of these reasons:

| Reason | Meaning |
|--------|---------|
| `value_required` | A `set` operation has no value |
| `unknown` | The parameter path is not in the schema |
| `readonly` | The parameter is not writable |
| `invalid_value` | The value does not agree with the schema constraints |
| `invalid_path` | The path is missing or not valid, or the object does not accept `add` |
| `not_found` | The object or instance does not exist |
| `rejected` | The data model refused the change |
| `max_instances` | The object has the maximum number of instances |
| `unknown_op` | The `op` field of a batch operation is not `set`, `add` or `del` |
| `busy` | An operation that runs in the background holds the transaction |
| `apply_failed` | The commit did not apply the configuration to the system |

### set

```
bbf-cli set <path> <value>
```

Sets one parameter to a new value. `bbf-cli` sends the value as a string.

```bash
bbf-cli set Device.WiFi.Radio.1.Channel 6
bbf-cli set Device.WiFi.Radio.1.Enable true
bbf-cli set Device.WiFi.AccessPoint.1.Security.ModeEnabled WPA2-Personal
bbf-cli set Device.WiFi.AccessPoint.1.Security.KeyPassphrase "my passphrase"
```

Reply on success:

```json
{
    "success": true
}
```

Reply on failure:

```json
{
    "error": "readonly"
}
```

### add

```
bbf-cli add <path>
```

Adds an instance to a multi-instance object. The reply contains the number of the new instance.

```bash
bbf-cli add Device.WiFi.SSID
bbf-cli add Device.NAT.PortMapping
bbf-cli add Device.Routing.Router.1.IPv4Forwarding
```

Reply on success:

```json
{
    "instance": 3
}
```

### del

```
bbf-cli del <path>
```

Deletes one instance of a multi-instance object. The path must include the instance number.

```bash
bbf-cli del Device.WiFi.SSID.2
bbf-cli del Device.NAT.PortMapping.5
```

Reply on success:

```json
{
    "success": true
}
```

### batch

```
bbf-cli batch <json>
```

Runs a list of `set`, `add` and `del` operations in one transaction. The argument is a JSON array of operation objects:

| Field | Description |
|-------|-------------|
| `op` | `set`, `add` or `del` |
| `path` | The parameter path or the object path |
| `value` | The new value; `set` only |

`bbf-dm` runs all operations before it decides the result. If one operation fails, `bbf-dm` aborts the transaction and no change occurs.

Example: set the channel and disable the automatic channel selection:

```bash
bbf-cli batch '[
    {"op":"set","path":"Device.WiFi.Radio.1.Channel","value":"36"},
    {"op":"set","path":"Device.WiFi.Radio.1.AutoChannelEnable","value":"false"}
]'
```

Reply on success:

```json
{
    "success": true,
    "digest": "<sha256 of the stored configuration>",
    "results": [
        { "op": "set", "path": "Device.WiFi.Radio.1.Channel", "success": true },
        { "op": "set", "path": "Device.WiFi.Radio.1.AutoChannelEnable", "success": true }
    ]
}
```

The result of an `add` operation also contains the number of the new instance:

```json
{ "op": "add", "path": "Device.WiFi.SSID", "success": true, "instance": 2 }
```

Reply on failure. The `error` field and the `op` field describe the first failed operation. The `results` array contains the result of each operation:

```json
{
    "error": "value_required",
    "op": { "op": "set", "path": "Device.WiFi.Radio.1.Channel" },
    "results": [
        { "op": "set", "path": "Device.WiFi.Radio.1.Channel", "success": false, "reason": "value_required" }
    ]
}
```

A batch cannot refer to the instance that an `add` in the same batch creates, because the instance number is not known in advance. To add and configure an instance, run `add` first. Then use the instance number from the reply in a `batch`.

---

## Applying a Configuration File

### apply

```
bbf-cli apply [-n | --dry-run] [-v | --verbose] [file]
```

Loads a TR-181 configuration file and applies it to the system. If you do not give a file, `bbf-dm` uses `/etc/ubbf/config.json`.

| Option | Description |
|--------|-------------|
| `-n`, `--dry-run` | Validate the configuration and generate the UCI commands, but do not apply them |
| `-v`, `--verbose` | Print the log messages and the generated UCI commands before the JSON reply |

`bbf-cli` ignores other arguments that start with `-`.

Without `-n`, `bbf-cli` calls `bbf-dm apply`. This call does these steps:

1. It reads the file. The file path must be absolute and must not contain `.` or `..` components.
2. It replaces the stored configuration with the contents of the file and writes it to `/etc/ubbf/config.json`.
3. It calls `bbf-device apply`, which validates `/etc/ubbf/config.json` and applies it approximately 1 second later.

With `-n`, `bbf-cli` calls `bbf-device apply` with `apply` set to false. This call validates the file and generates its UCI commands. Without a file, it validates `/etc/ubbf/config.json`. The same path rules apply as without `-n`.

```bash
bbf-cli apply
bbf-cli apply /tmp/new-config.json
bbf-cli apply -n
bbf-cli apply -n /tmp/new-config.json
bbf-cli apply -n -v
bbf-cli apply --dry-run --verbose
```

The reply contains these fields:

| Field | Description |
|-------|-------------|
| `success` | `true` if the validation succeeded |
| `logs` | The log messages of the validation, as `{ "level", "msg" }` objects |
| `output` | The generated UCI commands |
| `scheduled` | `false` for a dry run; only `bbf-device apply` returns this field |
| `error` | The reason for a failure |

If `success` is not `true`, `bbf-cli` writes `Apply failed: <error>` or `Dry-run failed: <error>` to stderr and exits with status 1.

---

## Running Operations

### operate

```
bbf-cli operate
bbf-cli operate <path> [<json> | <key>=<value>...]
```

Runs a TR-181 operation, for example a diagnostic test. The path is the operation name with `()` at the end. Without a path, `bbf-cli` lists all operations.

You can give the input arguments in one of two formats:

- One JSON object. If the first argument starts with `{`, `bbf-cli` reads it as JSON and ignores the other arguments. JSON keeps the value types.
- One or more `key=value` arguments. Each argument must contain `=`. `bbf-cli` sends each value as a string.

```bash
bbf-cli operate 'Device.IP.Diagnostics.IPPing()' Host=192.0.2.1 NumberOfRepetitions=4
bbf-cli operate 'Device.IP.Diagnostics.IPPing()' '{"Host":"192.0.2.1","NumberOfRepetitions":4}'
bbf-cli operate
```

Reply to a list request. `type` is `sync` or `async`:

```json
{
    "operations": [
        { "path": "Device.IP.Diagnostics.IPPing()", "type": "async" }
    ]
}
```

A synchronous operation replies at once. For an asynchronous operation, `bbf-dm` sends the reply when the operation completes. If the operation takes more than 30 seconds, the ubus call times out and `bbf-cli` prints nothing.

Reply on success:

```json
{
    "success": true,
    "output": {
        "Status": "Complete",
        "SuccessCount": "4",
        "AverageResponseTime": "12"
    }
}
```

If the operation does not exist or does not start, the reply contains an `error` string, for example `{ "error": "operation not found", "path": "..." }`. If an asynchronous operation fails, the reply contains a numeric USP error code and a message. For example, 7022 is a command failure:

```json
{
    "success": false,
    "error": 7022,
    "message": "<reason>"
}
```

---

## Device Management

The commands in this section return `{ "status": "scheduled" }`. The device starts the action approximately 1 second after the reply. Before the action, the device records the reason in the persistent store (`/dev/pmsg0`) and marks the request as local.

### reboot

```
bbf-cli reboot
```

Reboots the device.

```bash
bbf-cli reboot
```

### factory

```
bbf-cli factory
```

Resets the device to factory defaults and reboots it. The reset erases the configuration, but keeps the files that connect the device to its management server:

- `/etc/config/cwmp`
- `/etc/config/obuspa`
- `/etc/usp/acs-ca.pem`

```bash
bbf-cli factory
```

### upgrade

```
bbf-cli upgrade <file>
```

Installs a firmware image with `sysupgrade`. The argument is a local file path. `sysupgrade` also accepts an `http://` or `https://` URL and downloads the image.

Before the upgrade, the device writes a backup archive to `/tmp/ubbf-backup.tgz` and gives it to `sysupgrade -f`. Only the files in this archive survive the upgrade. The archive contains these files, if they exist:

- `/etc/usp/bbf.json`
- `/etc/ubbf/config.json`
- `/etc/ubbf/firmware.json`
- `/etc/ubbf/process-faults.json`
- `/etc/ubbf/reboots.json`
- `/etc/ubbf/kernel-faults.json`
- `/etc/ubbf/webui/credentials`
- `/etc/ubbf/certs`
- `/etc/config/obuspa`
- `/etc/usp/acs-ca.pem`
- `/etc/config/cwmp`
- `/etc/ubbf/cwmp-state.json`

```bash
bbf-cli upgrade /tmp/firmware.bin
```

---

## Examples

### Show the Wi-Fi configuration

```bash
bbf-cli show Device.WiFi.
```

### Change the Wi-Fi channel

```bash
bbf-cli set Device.WiFi.Radio.1.Channel 36
```

### Add a port forwarding rule

Add the instance first:

```bash
bbf-cli add Device.NAT.PortMapping
```

If the reply is `{ "instance": 3 }`, configure instance 3 in one transaction:

```bash
bbf-cli batch '[
    {"op":"set","path":"Device.NAT.PortMapping.3.Enable","value":"true"},
    {"op":"set","path":"Device.NAT.PortMapping.3.ExternalPort","value":"8080"},
    {"op":"set","path":"Device.NAT.PortMapping.3.InternalClient","value":"192.0.2.50"},
    {"op":"set","path":"Device.NAT.PortMapping.3.InternalPort","value":"80"},
    {"op":"set","path":"Device.NAT.PortMapping.3.Protocol","value":"TCP"}
]'
```

### Test the connectivity

```bash
bbf-cli operate 'Device.IP.Diagnostics.IPPing()' Host=192.0.2.1 NumberOfRepetitions=5
```

### Validate the stored configuration

```bash
bbf-cli apply -n -v
```

### Show the connected hosts

```bash
bbf-cli get Device.Hosts.Host.
```

### Show the device information

```bash
bbf-cli get Device.DeviceInfo.
```
