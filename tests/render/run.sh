#!/bin/sh
# Runs a host test of the renderer in a private mount namespace. The
# renderer reads its templates and the modules from the installed paths
# below /usr/share/ucode/ubbf, and the templates write below /etc, /run
# and /tmp/ubbf; this lays the source tree out there and gives the writes
# empty tmpfs. Run from the repository root:
#   tests/render/run.sh <host build of src/ucode-mod-ubbf> tests/render-dry-run.uc

build=$1
test=$2
repo=$PWD

[ -n "$build" ] && [ -n "$test" ] || { echo "usage: $0 <build dir> <test>" >&2; exit 2; }

exec unshare -rm sh -e -c '
	repo=$1 build=$2 test=$3
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
	mount -t tmpfs none /tmp/ubbf
	exec ucode -L "$repo/tests/render/*.uc" \
		-L "$repo/tests/hosts/*.uc" -L "/usr/share/ucode" \
		-L "$build/*.so" -L "$build/mods/*.so" "$repo/$test"
' sh "$repo" "$build" "$test"
