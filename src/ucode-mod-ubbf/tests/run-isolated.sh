#!/bin/sh
# Runs a test program in private mount and network namespaces: empty tmpfs
# on /tmp and /etc/ubbf, so the instance map and config.json of the host
# stay untouched, and only a loopback device, so a test can add the links
# and addresses that it reads back. sysfs is mounted again, because
# /sys/class/net shows the network namespace of the mount.
# Usage: run-isolated.sh <program> [args...]
exec unshare -rmn sh -c '
	mount -t tmpfs none /tmp && mkdir -p /tmp/ubbf || exit 1
	[ ! -d /etc/ubbf ] || mount -t tmpfs none /etc/ubbf || exit 1
	mount -t sysfs none /sys || exit 1
	ip link set lo up || exit 1
	exec "$@"' sh "$@"
