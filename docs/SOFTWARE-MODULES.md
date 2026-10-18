# Device.SoftwareModules

The module `modules/softwaremodules/` publishes TR-181 Issue 2 Amendment 19 Software Modules for the OpenWrt container stack: apk packages built by the containers feed, `uvol` volumes, `uxc` registrations and `procd` supervision. The data model keeps no record of the stack. Every row is read from the stack when a controller asks, and every write goes through a stack command.

## Stack

| Component | Role |
|---|---|
| containers feed (`container.mk`, `compose.mk`) | Builds `container-<name>` packages from OCI images: a sealed OCI bundle on a content-addressed read-only uvol `sha256-<hash>`, a registration on the `.meta` uvol, requirement tags in the apk index. `stack-<app>` packages compose containers. |
| apk | Installs, upgrades and removes the packages. Container packages are apk layer 1; their installed records live on `.meta` with the registrations. |
| uvol | Read-only image volumes, read-write data volumes `<container>.<volume>` and persistent overlays `<container>`. The `uvol` ubus object reports capacities and removes volumes. |
| uxc | Registrations `/tmp/run/uvol/.meta/uxc/<name>.json` (package owned), operator settings `settings/<name>.json` (uxc owned, written by `uxc set`), state `state/<name>/`, the lifecycle verbs and `uxc list --format json`, the merged view of all three. |
| procd, ujail | Create, start, stop and respawn the container; the respawn policy of the settings file is applied by procd. |
| uxc-net | Realises the network attach of a container over ubus and publishes it as `container-network` in the instance data. |
| uxc-req | Evaluates a deployment request against the requirement tags of a package in the signed index before anything is downloaded. |

## Mapping

| TR-181 | Stack |
|---|---|
| `ExecEnvClass.1` | the uxc OCI runtime; `Capability.1` is `OCIImage`, runtime spec versions `[1.1.0,1.3.0]` as `ujail` accepts them |
| `ExecEnv.1` | uxc. `Enable` is the inverse of the `uxc disable-all` marker; `Status` is `Up` while the procd `container` object exists. `AllocatedDiskSpace` and `AvailableDiskSpace` are uvol total and free; `AvailableAccessInterfaces` lists the `Device.IP.Interface` names. `Restart()` stops every container and runs `uxc boot`; `Reset()` removes every container and stack package with its data. Run levels, roles, constraints, `Remove()` and `AddExecEnv()` are not offered. |
| `ExecEnv.1.ApplicationData.{i}` | one row per data volume and overlay of every execution unit, in execution unit order: `Name` is the uvol name, `Retain` is `Forever` for a volume and `UntilStopped` for a tmpfs overlay, `ApplicationUUID` the UUID of the owning deployment unit. `Remove()` needs an idle execution unit and removes the volume. |
| `DeploymentUnit.{i}` | an installed `container-*` or `stack-*` package. `DUID` is the package name, `Name` the registration name (the stack name for a stack), `Vendor` the publisher of the registration, `Version` the apk version, `UUID` the Annex C version 5 UUID of `<Name>.<Vendor>.`, `Resolved` whether every image volume is up, `Status` `Installed` or the running apk transaction, `ModuleVersion` the settings key of the same name. `Installed` and `LastUpdate` are the unknown time until apk records an install time. |
| `ExecutionUnit.{i}` | a uxc registration. `Status` follows the OCI state (`running` and `paused` are `Active`, `creating` and `created` are `Starting`, else `Idle`); `ExecutionFaultCode` comes from the `last-exit` record; `AutoStart`, `ShutdownDelay` and `AutoRestart` are the effective settings and are written back with `uxc enable`, `uxc set --stop-timeout` and `uxc set --respawn`; `Privileged` is the `userns=off` tag; memory, CPU and id mappings of a running container come from its cgroup and `/proc`; `References` and `NetworkConfig.AccessInterfaceRefList` are the `Device.IP.Interface` rows of the attached network or egress zones. |
| `ExecutionUnit.{i}.HostObject.{i}` | provisioned files, data volume mounts and the hosts file of the registration and settings |
| `ExecutionUnit.{i}.EnvVariable.{i}` | the settings `env` table |
| `InstallDU()` | `URL` is `apk://<package>[=<version>]`. The request is checked with `uxc-req check` against the index tags, so `Privileged`, `NetworkConfig`, `Resources` and `ApplicationData` that contradict the sealed image are refused before the download; `apk add` installs; `ShutdownDelay`, `AutoRestart`, `ModuleVersion`, `EnvVariable`, `HostObject`, `ApplicationData` and `Resources` are written with `uxc set`. The output carries the UUID, the apk version and the ExecEnv reference. |
| `Update()` | `apk upgrade <package>`, or `apk add <package>=<version>` when the URL names a version, then the settings as for an install. Without `RetainData` the data volumes and secrets are removed after the upgrade and the running units are created and started again. |
| `Uninstall()` | `apk del <package>`; the post-deinstall hook names the kept volumes and secrets, which are removed unless `RetainData` is true. |
| `SetRequestedState()`, `Restart()` | `uxc create` and `uxc start`, `uxc kill`, `uxc restart`, started in the background; the result shows in `Status` and `ExecutionFaultCode`. |
| `DUStateChange!` | sent after every install, update and uninstall with the TR-181 fault codes 7002, 7004, 7223 and 7229. |

Instance numbers come from the instance map (`utils/instance-map.uc`): `DeploymentUnit` by package name, `ExecutionUnit` by registration name, `ApplicationData` by registration and volume name. A row keeps its number while other rows come and go, and a number is not given to another package or registration (TR-369 R-ARC.8). A package that is installed again gets its old number.

`ExecEnv` and `ExecutionUnit` are `runtime_instances` tables with `writable_rows`: a write into a row read from the stack stores that row, and the get handler shows the stack over the stored values. The set handler checks the write and keeps its uxc command; the commit hook runs the commands of the transaction, so an aborted transaction changes nothing in the stack. `Uninstall()` deletes the stored rows of the execution units that go with the package.

## Not modelled

- Port mappings. The ingress redirects of a routed container are fw4 state that uxc-net creates over ubus, with no `Device.NAT.PortMapping` row; `PortMappingRefList` is empty and `NetworkConfig.PortMapping` arguments are only validated against the sealed ingress list.
- `CPUPercentInUse`. The cgroup gives cumulative CPU time, a percentage needs a sampler; the value is -1.
- Credentials. `Username` and `Password` are not used; apk repositories carry their own credentials.
- URLs other than `apk://`. A package file has no index tags to validate a request against.

## Dependencies

`ubbf-mod-softwaremodules` needs `uxc`, `uxc-req`, `uvol` with its rpcd plugin, `apk` and `ucode-mod-digest`.

The package in `ubbf-feed/ubbf/Makefile` depends on `uxc`, `uvol`, `kmod-fs-ext4`, `block-mount`, `kmod-veth` and `ucode-mod-digest`; the base package pulled the first five before. `apk` is part of every image. `uxc-req` is not a dependency yet: the OpenWrt tree of this project has no package of that name, and the containers feed was not checked for it.

## Verification

With a container package installed on the device:

```
bbf-cli get Device.SoftwareModules.
bbf-cli operate Device.SoftwareModules.ExecutionUnit.1.SetRequestedState() '{"RequestedState":"Active"}'
bbf-cli operate Device.SoftwareModules.InstallDU() '{"URL":"apk://container-traefik-whoami"}'
```

`uxc list --format json` and `uxc state <name>` show the values the rows are built from.
