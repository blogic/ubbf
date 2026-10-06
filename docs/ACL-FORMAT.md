# Web UI ACL Format

This document describes the format of the access control list (ACL) for the web UI. The ACL controls which parts of the TR-181 data model the web UI can read and change.

The ACL applies to two methods of the `bbf-dm` ubus object:

- `webui-show` returns the data tree, filtered by the `read` section.
- `webui-transaction` applies a batch of operations, checked against the `write` section.

The other `bbf-dm` methods, for example `batch`, do not use the ACL.

## File Location

The ACL is stored at:
```
/etc/ubbf/webui-acl.json
```

The repository ships a default ACL in `files/etc/ubbf/webui-acl.json`.

The daemon that publishes `bbf-dm` keeps the ACL in a cache after the first successful load. Nothing clears this cache. If you change the file, you must restart that daemon.

## Structure

The ACL file is a JSON object with two sections:

```json
{
    "read": { ... },
    "write": { ... }
}
```

| Section | Description |
|---------|-------------|
| `read` | The paths and properties that the web UI can read |
| `write` | The paths and properties that the web UI can change, add and delete |

If a section is missing, the ACL denies all access of that type.

## Path Patterns

Each key in a section is a path pattern. The pattern is a dotted path. The `*` wildcard matches one path segment, usually an instance number.

A pattern matches a path if these conditions are true:

- The path has at least as many segments as the pattern.
- Each pattern segment is `*` or is equal to the path segment at the same position.

The path can continue after the end of the pattern. A pattern therefore matches its own path and every path below it.

| Pattern | Matches |
|---------|---------|
| `Device.DeviceInfo` | `Device.DeviceInfo` and every path below it |
| `Device.WiFi.Radio.*` | `Device.WiFi.Radio.1`, `Device.WiFi.Radio.2.Channel`, and so on |
| `Device.WiFi.AccessPoint.*.Security` | `Device.WiFi.AccessPoint.1.Security` and the paths below it |
| `Device.Firewall.Chain.*.Rule.*` | Any rule in any chain, and the paths below it |

If more than one pattern matches a path, the pattern with the most segments applies. A longer pattern thus overrides a shorter pattern for its part of the tree.

Do not write two patterns with the same number of segments that match the same path. In that case, the code uses the first match in the key order of the JSON object.

## Property Access Formats

Each path pattern maps to a rule. The rule has one of the formats below.

### 1. All Properties (`true`)

The rule gives access to all properties at and below the matching paths.

```json
{
    "read": {
        "Device.DeviceInfo": true
    }
}
```

### 2. Property List (Array)

The rule gives access only to the listed names. The code compares the list with the first path segment after the pattern.

```json
{
    "read": {
        "Device.WiFi.Radio.*": ["Enable", "Channel", "OperatingChannelBandwidth"]
    }
}
```

For example, the rule above gives read access to `Device.WiFi.Radio.1.Channel`. If the list holds the name of a child object, the rule gives access to the full child object.

### 3. Conditional Access (Object with Filter)

The rule gives access only to instances that match the filter conditions.

```json
{
    "read": {
        "Device.IP.Interface.*": {
            "filter": { "Upstream": "false" },
            "properties": ["Enable", "Name", "Type"]
        }
    }
}
```

| Field | Description |
|-------|-------------|
| `filter` | Optional. An object of property and value pairs. All pairs must match. |
| `properties` | Required. An array of allowed property names, as in format 2. |

If the object has no `properties` field, the rule denies access.

### Other Values

Any other value, for example `false`, denies access. Because the longest pattern applies, a `false` rule can deny part of a tree that a shorter pattern allows.

### Paths Equal to the Pattern

A list rule and an object rule have different results for a path that is equal to the pattern:

- In the `read` section, the rule allows that path.
- In the `write` section, the rule denies that path.

For example, the write rule `"Device.WiFi.SSID.*": ["Enable", "SSID"]` denies `del` on `Device.WiFi.SSID.1`. To allow the delete, the longest matching write pattern must have the value `true`. A list rule on a shorter pattern that names the table, here `SSID`, also allows it if no longer pattern matches.

## Filter Matching

A filter compares property values of an instance with the values in the filter:

```json
{
    "filter": { "Upstream": "false" },
    "properties": ["Enable", "Name"]
}
```

This rule allows access only to instances where `Upstream` is equal to `"false"`, that is, downstream interfaces.

The code compares the values with the ucode `!=` operator. The schema defaults and the example configurations store boolean values as strings, for example `"false"`. Write the filter values as strings in the same form.

Multiple filter conditions use AND logic:

```json
{
    "filter": { "Enable": "true", "Status": "Up" },
    "properties": ["Name"]
}
```

The code reads the instance for the filter from these locations:

- `webui-transaction` uses the instance at the first `*` of the pattern. It reads the configuration tree.
- `webui-show` uses the matched instance, and also the instance at the first `*` of the pattern. It reads the configuration tree with the runtime state.

If the pattern has one `*`, these locations are the same instance. Use filters only on patterns with one `*`.

The code does not apply filters to `add` operations.

## Write Operations

`webui-transaction` checks each operation against the `write` section:

| Operation | Check |
|-----------|-------|
| `set` | The path must match a write rule, as described above. |
| `del` | The path must match a write rule, as described above. |
| `add` | A write pattern must be longer than the parent path and match it segment by segment. |

For example, the pattern `Device.DHCPv4.Server.Pool.*.StaticAddress.*` allows `add` on `Device.DHCPv4.Server.Pool.1.StaticAddress`.

The code checks all operations before it applies any of them. If one operation fails the check, the transaction does not change the configuration.

## Examples

### Basic WiFi Configuration

```json
{
    "read": {
        "Device.WiFi.Radio.*": ["Enable", "Channel", "Status"],
        "Device.WiFi.SSID.*": ["Enable", "SSID", "MACAddress"],
        "Device.WiFi.AccessPoint.*.Security": ["ModeEnabled"]
    },
    "write": {
        "Device.WiFi.Radio.*": ["Enable", "Channel"],
        "Device.WiFi.SSID.*": ["Enable", "SSID"],
        "Device.WiFi.AccessPoint.*.Security": ["ModeEnabled", "PreSharedKey"]
    }
}
```

### Downstream Interfaces Only

This ACL allows changes only to downstream (LAN) interfaces:

```json
{
    "read": {
        "Device.IP.Interface.*": {
            "filter": { "Upstream": "false" },
            "properties": ["Enable", "Name", "Type", "IPv4Enable"]
        }
    },
    "write": {
        "Device.IP.Interface.*": {
            "filter": { "Upstream": "false" },
            "properties": ["Enable", "Name"]
        }
    }
}
```

### Read-Only Device Information

```json
{
    "read": {
        "Device.DeviceInfo": true
    },
    "write": {}
}
```

### Firewall Rules

```json
{
    "read": {
        "Device.Firewall.Chain.*": ["Enable", "Name"],
        "Device.Firewall.Chain.*.Rule.*": ["Enable", "Description", "Target", "SourceInterface", "DestInterface"]
    },
    "write": {
        "Device.Firewall.Chain.*.Rule.*": ["Enable", "Description", "Target"]
    }
}
```

## Guidelines

1. Give access only to the properties that the web UI uses.
2. Use filters to block access to WAN (upstream) interfaces.
3. Configure `read` and `write` separately. Read access does not give write access.
4. Test each ACL change with `ubus call bbf-dm webui-show` before you deploy it.

## Troubleshooting

### ACL Not Found

`webui-show` and `webui-transaction` return `ACL_NOT_FOUND` if the daemon cannot read the ACL. Make sure that:

- The file exists at `/etc/ubbf/webui-acl.json`.
- The file is not empty.
- The daemon that publishes `bbf-dm` can read the file.

If the file contains invalid JSON, the JSON parser raises an exception. The result is not `ACL_NOT_FOUND`.

### Properties Not Visible

If expected properties do not appear:

1. Make sure that a pattern matches the data model path.
2. Make sure that the longest matching pattern lists the property.
3. For filtered rules, make sure that the instance matches the filter conditions.
4. Make sure that you restarted the daemon after the last change to the file.

### Write Access Denied

If `webui-transaction` returns `ACL_DENIED` with a `path` field:

1. Make sure that the path matches a pattern in the `write` section.
2. Make sure that the property is in the list of properties.
3. For filtered rules, make sure that the instance matches the filter conditions.

`webui-transaction` also returns `ACL_DENIED` if an operation writes to a read-only property. This result has an `op` field instead of a `path` field.
