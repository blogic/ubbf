#!/bin/sh
# Runs the ucode host tests with utest in a private mount and network
# namespace, so that the neighbours and bridges of the host stay out of the
# results. The
# source tree is laid out below /usr/share/ucode/ubbf, as on the device, and
# /etc, /run, /tmp and /var/log are empty tmpfs; the tests of tests/sysfs/
# get an empty tmpfs on /sys as well. The stand-in programs of tests/bin/
# come first in PATH, and log to the fixed paths exported below. Run from the
# repository root:
#   tests/run.sh <host build of src/ucode-mod-ubbf> [utest options] [bundle ...]
# Without a bundle it runs tests/, tests/sysfs/ and the test of the native
# modules, src/ucode-mod-ubbf/test_ubbf_mod.uc, with its own configuration.

[ -n "$1" ] || { echo "usage: $0 <host build> [utest options] [bundle ...]" >&2; exit 2; }

build=$(cd "$1" && pwd) || exit 2
shift

namespace_run() {
	sysfs=$1
	shift
	UBBF_HOST_BUILD=$build unshare -rmn sh -e -c '
		repo=$1 sysfs=$2
		shift 2
		mount -t tmpfs none /mnt
		mkdir -p /mnt/host /mnt/ucode/ubbf/modules
		mount --bind /usr/share/ucode /mnt/host
		for entry in /mnt/host/*; do
			ln -s "$entry" /mnt/ucode/
		done
		for entry in "$repo"/files/usr/share/ucode/ubbf/*; do
			ln -s "$entry" /mnt/ucode/ubbf/
		done
		for module in "$repo"/modules/*/; do
			ln -s "$module" /mnt/ucode/ubbf/modules/
		done
		mount --bind /mnt/ucode /usr/share/ucode
		for dir in /etc /run /tmp /var/log; do
			mount -t tmpfs none "$dir"
		done
		[ "$sysfs" = 0 ] || mount -t tmpfs none /sys
		mkdir -p /etc/ubbf /tmp/ubbf
		export PATH="$repo/tests/bin:$PATH"
		export UBBF_BUILD_DIR=$UBBF_HOST_BUILD
		export CURL_LOG=/tmp/curl-args.log
		export RESOLVEIP_LOG=/tmp/resolveip.log RESOLVEIP_V6=acs6.example.com
		export SM_LOG=/tmp/ubbf/sm.log SM_LIST=/tmp/ubbf/sm-list.json
		exec utest "$@"' sh "$PWD" "$sysfs" "$@"
}

bundles=0
for arg; do
	case "$arg" in
	tests/*) bundles=1 ;;
	esac
done

if [ "$bundles" = 1 ]; then
	case "$*" in
	*tests/sysfs*) namespace_run 1 "$@" ;;
	*) namespace_run 0 "$@" ;;
	esac
	exit
fi

namespace_run 0 "$@" tests && namespace_run 1 "$@" tests/sysfs &&
	UBBF_HOST_BUILD=$build UBBF_BUILD_DIR=$build utest -c src/ucode-mod-ubbf/utest.config.uc "$@" \
		src/ucode-mod-ubbf/test_ubbf_mod.uc
