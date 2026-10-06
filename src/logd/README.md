# ubbf-logd

`ubbf-logd` forwards syslog messages for TR-181 `Device.Syslog`. It replaces
syslog-ng and the ucode `ubbf-syslog-bridge`.

- Input: the logd ring over ubus (`log read` with `stream`), network
  listeners for `Source.{i}.Network` (UDP, TCP, TLS), and datagram Unix
  sockets for `Source.{i}.UnixDomainSocket`.
- Output: a file for `Action.{i}.LogFile`, a remote syslog server for
  `Action.{i}.LogRemote` (UDP, TCP, TLS).
- The render template `modules/syslog/render.uc` writes the config file
  `/var/run/ubbf-logd/config.json` and calls `ubus call ubbf-logd reload`.
  The daemon runs only while an action has a destination.
- The daemon runs as root in a ujail (`modules/syslog/files/etc/init.d/ubbf-logd`):
  it sees `/etc/ssl/certs`, `/etc/ubbf` and its config directory read-only,
  and `/var/log` and `/var/run/ubbf-syslog` writable, and keeps only
  `CAP_NET_BIND_SERVICE`.

## Command line

```
ubbf-logd [-c <config>]
```

The default config is `/var/run/ubbf-logd/config.json`. A missing file
means no actions. The file is in a directory of its own, because the jail
mounts the directory and the render replaces the file.

## Config file

```json
{
  "sources": {
    "1": { "kernel": true, "system": true },
    "3": { "kernel": false, "system": false,
           "network": { "proto": "tls", "port": 6514, "default_pri": 13,
                        "cert": "/path/cert-and-key.pem", "ca_dir": "/dir",
                        "peer_verify": false } },
    "4": { "kernel": false, "system": false,
           "unix": { "path": "/var/run/ubbf-syslog/app.sock", "default_pri": 13 } }
  },
  "filters": {
    "1": { "facilities": 16, "severities": 15, "pattern": "foo", "action": "stop" }
  },
  "templates": { "1": { "expression": "<$PRI>$ISODATE $HOST $MSGHDR$MSG", "escape": false } },
  "actions": [
    { "id": 2, "sources": [ 1, 3 ], "filters": [ 1 ], "template": 1, "structured": false,
      "file": "/var/log/messages",
      "remote": { "proto": "tcp", "address": "192.0.2.1", "port": 514,
                  "cert": null, "ca_dir": null, "peer_verify": false } }
  ]
}
```

- `facilities`: bit `1 << facility`; 0 means all facilities.
- `severities`: bit `1 << severity` (emerg is 0); 0 matches nothing.
- `action`: `log`, `block` or `stop`.
- `default_pri`: the priority of a received frame without a valid `<PRI>`.
- `cert`: one PEM file that holds the certificate and its private key.
- `ca_dir`: `ca-certificates.crt` in the directory when it has one, else
  every regular file that is not a symbolic link.
- `unix`: a datagram socket, as `/dev/log`. `path` must be one file name
  directly in `/var/run/ubbf-syslog/`; the daemon refuses any other path.
  It replaces a socket file of an earlier run but no other kind of file,
  gives the socket mode 0666, and removes it with the listener. A frame
  without a host name gets the host name of the device.
- `file`: a path below `/var/log/`, without `.` or `..` components. The
  daemon refuses any other path and does not follow a symbolic link.

## Message processing

- The actions run in the order of the file. For one action:
  1. The message must come from one of its sources. A local source takes
     kernel messages, system messages, or both. A network source takes the
     frames of its listener.
  2. A `stop` filter that matches ends the message for this action and for
     all later actions. `stop` filters are checked before the other filters.
  3. Every `log` filter must match, and no `block` filter may match.
- A filter matches when the facility, the severity and the pattern match.

## Patterns

`pattern` is a POSIX extended regular expression (`regcomp()` with
`REG_EXTENDED`), matched against the message text. PCRE syntax such as
`\d`, `\w` or lookarounds is not supported. A pattern that does not compile
fails closed: a `log` filter matches nothing, and a `block` or `stop`
filter matches every message of its facilities and severities. `reload`
reports it for each action that uses it. The data model refuses such a
pattern at set time.

## Templates

`$NAME` and `${NAME}` expand to:

| Macro | Value |
|---|---|
| `PRI` | priority number |
| `FACILITY` | facility name, as syslog-ng names it |
| `LEVEL`, `SEVERITY` | severity name |
| `DATE` | `Mmm dd hh:mm:ss`, local time |
| `ISODATE` | RFC 3339 with the local offset |
| `HOST` | host name |
| `PROGRAM` | program name |
| `PID` | process id |
| `MSGHDR` | `PROGRAM[PID]: ` or `PROGRAM: ` |
| `MSG`, `MESSAGE` | message text |

Any other text, including an unknown macro, is copied as it is. With
`escape`, the characters `'`, `"` and `\` in `MSG` get a backslash.

Without a template:

- file: `$DATE $HOST $MSGHDR$MSG`
- remote: RFC 3164 `<PRI>DATE HOST MSGHDR MSG`, or RFC 5424
  `<PRI>1 ISODATE HOST PROGRAM PID - - MSG` when `structured` is set.

TCP and file output end each line with a newline. TLS output uses the
octet counting of RFC 5425, `MSG-LEN SP SYSLOG-MSG`.

## Network input

- UDP: one datagram is one frame.
- TCP and TLS: newline framing, or RFC 6587 octet counting when a frame
  starts with a digit. A line longer than 2048 bytes is cut into frames of
  2048 bytes. At most 16 clients per listener; a new client closes the
  oldest one.
- With `peer_verify`, a TLS client must present a certificate that a CA of
  `ca_dir` signed; a client without a certificate is closed.
- Sources with the same listener parameters share one socket; each of them
  gets every frame, parsed with its own `default_pri`.
- A control character in a message (below 0x20, and 0x7f) becomes `#` and
  its three-digit octal code, as rsyslog writes it: a newline is `#012`.
  This applies to received frames and to the logd ring.
- A frame is parsed as RFC 5424 when `<PRI>1 ` starts it, else as RFC 3164.
  Structured data of a received frame is dropped.
- A frame without a host name takes the sender address.
- The listener binds to all addresses. The firewall rule comes from the
  TR-181 `Interface` (`source_firewall()` in `modules/syslog/handler.uc`).

## Output

- An output is kept across a reload when its parameters do not change, with
  its connection and its queue. An output with changed parameters is a new
  output; the lines queued for the old one are dropped.
- A host name is resolved in a child process, so a name server that does
  not answer does not stop the daemon. Resolution and connection together
  time out after 10 s.
- UDP, TCP and TLS try again after 1 s, doubling up to 30 s. While the
  destination is down, up to 1000 lines or 256 KiB wait in a queue for TCP
  and TLS; then the oldest line is dropped.
- TCP keepalive finds a peer that went away silently after about 90 s.
- `sent` counts a line once it left the stream buffers; lines still in the
  buffers when a connection closes count as `dropped`.
- A TLS output whose context fails (no TLS backend, certificate not
  loadable) is in state `error` and tries again with the same backoff, and
  at once on each reload. A TLS listener tries again every 5 s.
- With `peer_verify`, a TLS connection needs a trusted certificate that
  names the address.
- A file that someone else rotates or removes is opened again by its path.
  `ubbf-logd` does not rotate files.
- TLS uses `libustream-ssl.so`, loaded at run time. Without it, TLS outputs
  report `tls unavailable`.

## ubus

- `ubus call ubbf-logd reload`: read the config file again. The reply has
  `success` and `actions` with `ok` or an error for each action. The status
  is always OK, so that callers that drop the data of an error reply still
  see it.
- `ubus call ubbf-logd status`: the logd input, the state of each action
  output (`connecting`, `connected`, `unreachable`, `error`, with `sent`,
  `dropped`, `queued` and `error`), and each listener.

`modules/syslog/handler.uc` maps an `unreachable` remote to
`LogRemote.Status = Error_Unreachable`, and an `error` remote or an action
error to `Error`.

## Input

The daemon reads the logd ring at start. When a reload brings the first
actions, it reads the ring again: at boot the daemon starts before the first
apply writes its config, and would else drop the boot messages.

## Tests

`tests/test.c` checks the message parser, the framing, the templates and
the filters on the host:

```
cmake -B build -DCMAKE_C_FLAGS=-D_GNU_SOURCE . && make -C build ubbf-logd-test && (cd build && ctest)
```

The testbed suite `syslog` checks the daemon on a DUT.
