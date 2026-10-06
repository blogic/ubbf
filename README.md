# ubbf

ubbf (Unified Broadband Firmware) implements the Broadband Forum TR-181 Device:2 data model on OpenWrt. It connects the USP (TR-369) and CWMP (TR-069) management agents to the native configuration system of OpenWrt.

ubbf runs on an unmodified OpenWrt tree. It uses ubus for inter-process communication and UCI for configuration. It is written in ucode, with a small set of C extension modules.

## Design

ubbf keeps the device configuration as a TR-181 tree in `/etc/ubbf/config.json`. On each commit, the render pipeline generates the complete UCI state from this tree. ubbf does not edit UCI in steps, so the UCI state always matches the TR-181 tree.

```
USP / CWMP agent, web UI, bbf-cli
                |
                v
        ubus object bbf-dm
                |
                v
       data model engine (datamodel.uc)
        |               |
        v               v
  TR-181 handlers    schemas
  (live state)       (types, defaults, access)
        |
        v
  /etc/ubbf/config.json
        |
        v
  render pipeline (renderer.uc, render/templates/*.uc)
        |
        v
  UCI batch --> service reloads (network, firewall, wireless, ...)
```

### Write path

1. A client sends `set`, `add` or `del` to `bbf-dm`.
2. The engine checks each value against the schema and runs the handler, if the parameter has one.
3. The engine keeps the change in a transaction until the commit.
4. On commit, the engine stores the tree. The renderer then generates the UCI batch, applies it and reloads the affected services.

### Read path

1. A client sends `get` to `bbf-dm`.
2. The engine reads the stored configuration of the requested path.
3. Handlers add the live values, for example interface status, counters and associated stations.
4. The engine returns the merged result.

## Management agents

- **USP**: OB-USP-Agent (OBUSPA) loads ubbf through an embedded ucode VM. OBUSPA provides the USP transports, for example MQTT.
- **CWMP**: a CWMP agent uses the same data model through `cwmp-dm.uc`.
- **Local**: the web UI and `bbf-cli` use the same ubus object, `bbf-dm`.

All clients use the same data model and the same validation.

## Data model coverage

Schemas exist for these TR-181 domains (`files/usr/share/ucode/ubbf/schemas/`):

Bridging, DeviceInfo, DHCPv4, DHCPv6, DNS, Ethernet, Firewall, GatewayInfo, Hosts (AccessControl; the Host table is the module `hosts`), InterfaceStack, IP (with the TR-143 diagnostics), LocalAgent, ManagementServer, NAT, NeighborDiscovery, RouterAdvertisement, Routing, SoftwareModules, SSH, Time, UnixDomainSockets, WiFi, and the vendor extensions under `Device.X_UBBF`.

Modules add more domains. Each module is a separate package, `ubbf-mod-<name>`, built from `modules/<name>/`: bulkdata, cellular, ddns, dslite, easymesh (IEEE1905 and WiFi DataElements), hosts, leds, lldp, location, multicast, packetcapture, pcp, ppp, pty, qos, qosify, security, syslog, testbed, tr471, umdns, upnp, usb, userinterface, users (with LANConfigSecurity), usfpd and wol (Ethernet WoL). The modules for domains that were part of the base package are selected by default.

### Diagnostics

| Operation | Standard |
|---|---|
| `Device.IP.Diagnostics.IPPing()` | TR-181 |
| `Device.IP.Diagnostics.TraceRoute()` | TR-181 |
| `Device.IP.Diagnostics.DownloadDiagnostics()` | TR-143 |
| `Device.IP.Diagnostics.UploadDiagnostics()` | TR-143 |
| `Device.IP.Diagnostics.UDPEchoDiagnostics()` | TR-143 |
| `Device.IP.Diagnostics.ServerSelectionDiagnostics()` | TR-143 |
| `Device.IP.Diagnostics.IPLayerCapacity()` | TR-471, module `tr471` |
| `Device.DNS.Diagnostics.NSLookupDiagnostics()` | TR-181 |
| `Device.PacketCaptureDiagnostics()` | TR-181, module `packetcapture` |

## Repository layout

| Path | Content |
|---|---|
| `files/` | Files installed on the device: ucode modules, init scripts, helpers |
| `files/usr/share/ucode/ubbf/` | Data model engine, handlers, schemas, render templates |
| `modules/` | Optional domains, packaged as `ubbf-mod-<name>` |
| `src/` | C extension modules and helper programs |
| `dm/` | TR-181 XML specifications and the tools that parse them |
| `examples/` | Example `config.json` files |
| `tools/` | Host tools |

## TR-181 schema files

The schemas in `files/usr/share/ucode/ubbf/schemas/*.uc` have an "Auto-generated" header, but they are maintained by hand. Edit them directly: parameter types, the `WRITABLE` bit, defaults and enumerations. The generator, `dm/generate_ucode_schemas.py` with `dm/tr181.csv`, is kept for reference only. If you run it again, it overwrites the changes made by hand.

- A parameter must be in the `schema` table, or the model does not describe it. An entry in `defaults` alone is not sufficient. The default puts the key in the tree, so GetParameterNames lists it, but GetParameterValues then returns fault 9005. TR-069 A.3.2.3 does not permit this. To remove a parameter, remove it from both tables.
- Properties that the type integer cannot hold, for example the TR-181 `secured` attribute and the allowed values, go in the optional `constraints` table next to `schema` and `defaults`. See the schema section of `docs/ARCHITECTURE.md`.
- The TR-181 XML specifications in `dm/spec/` are a read-only copy of the Broadband Forum standard. Do not edit them, also not for vendor extensions. Vendor parameters (`X_*`) go directly into the schema files and their handlers.
- If a schema and a test disagree, read the parameter in `dm/spec/` first. If the schema follows the standard, correct the test, not the schema. An example is a test that writes a `readOnly` parameter.
- `dm/spec/` holds the full USP XML of each TR-181 version, `tr-181-2-<minor>-<patch>-usp-full.xml`. `dm/analyze_tr181_spec.py` writes one JSON file per object of each version into `dm/json_spec/<version>/`, for the highest patch release of each minor. `dm/check_constraints.py` checks the rules of the schemas against the newest version. `dm/spec_delta.py <old> <new>` lists what changed between two versions; with `--ours <dump>` (from `dm/version_tags_dump.uc`) only for the objects ubbf has a schema for. `dm/check_version_tags.py` checks the `since`/`until` tags, see "TR-181 versions" in `docs/ARCHITECTURE.md`.

The handlers in `files/usr/share/ucode/ubbf/tr181/*.uc` are written by hand.

## Documentation

| Document | Content |
|---|---|
| [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) | Code patterns and common tasks |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Implementation details, directory structure, module system |
| [docs/MODULE-GUIDELINES.md](docs/MODULE-GUIDELINES.md) | Rules and checklist for TR-181 handlers |
| [docs/CLI.md](docs/CLI.md) | `bbf-cli` reference |
| [docs/ACL-FORMAT.md](docs/ACL-FORMAT.md) | Web UI ACL format |

## Licence

ubbf is licensed under the GNU General Public License, version 2 only (GPL-2.0-only). The TR-181 specifications in `dm/spec/` are copyright of the Broadband Forum and carry their own licence.
