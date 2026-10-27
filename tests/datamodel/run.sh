#!/bin/sh
# Runs a host test that imports ubbf.datamodel, in a private mount
# namespace: the source tree is laid out below /usr/share/ucode/ubbf, and
# /etc, /run and /tmp are empty tmpfs. The test runs once per phase given,
# with PHASE set; "reboot" between two phases clears /tmp/ubbf and keeps
# /etc/ubbf/config.json. Run from the repository root:
#   tests/datamodel/run.sh <host build> tests/instance-pins.uc 1 reboot 2

build=$1
test=$2
shift 2
repo=$PWD

[ -n "$build" ] && [ -n "$test" ] || { echo "usage: $0 <build dir> <test> [phase ...]" >&2; exit 2; }

exec unshare -rm sh -e -c '
	repo=$1 build=$2 test=$3
	shift 3
	mount -t tmpfs none /usr/share
	mkdir -p /usr/share/ucode/ubbf/modules
	for entry in "$repo"/files/usr/share/ucode/ubbf/*; do
		ln -s "$entry" /usr/share/ucode/ubbf/
	done
	for module in "$repo"/modules/*/; do
		ln -s "$module" /usr/share/ucode/ubbf/modules/
	done
	mount -t tmpfs none /etc
	mount -t tmpfs none /run
	mount -t tmpfs none /tmp
	mkdir -p /etc/ubbf /tmp/ubbf
	cp "$repo/files/usr/share/ucode/ubbf/initial.json" /etc/ubbf/config.json
	[ $# -gt 0 ] || set -- 1
	for phase in "$@"; do
		if [ "$phase" = reboot ]; then
			rm -rf /tmp/ubbf
			mkdir -p /tmp/ubbf
			continue
		fi
		PHASE=$phase ucode -L "$repo/tests/datamodel/*.uc" \
			-L "$repo/tests/render/*.uc" -L "$repo/tests/ip/*.uc" \
			-L "$repo/tests/hosts/*.uc" \
			-L "/usr/share/ucode" -L "$build/*.so" "$repo/$test"
	done' sh "$repo" "$build" "$test" "$@"
