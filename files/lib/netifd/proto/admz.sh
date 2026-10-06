#!/bin/sh

# Advanced DMZ / IP Passthrough proto handler. Behaves like the stock
# OpenWrt dhcp proto handler but invokes admz.script instead of
# dhcp.script as udhcpc's callback. admz.script branches on the
# admz.main.enable UCI flag: when off it is byte-for-byte equivalent to
# dhcp.script (so wan operates as normal DHCP); when on it binds the
# RFC2544 non-routable secondary 198.18.0.1/32 onto the WAN device
# instead of the leased public IP and publishes the lease info via
# proto_add_data so admzd can pick it up via
# `ubus call network.interface.<wan> status`.

[ -x /sbin/udhcpc ] || exit 0

. /lib/functions.sh
. /lib/functions/network.sh
. ../netifd-proto.sh
. /lib/config/uci.sh
init_proto "$@"

proto_admz_init_config() {
	renew_handler=1
	restart_handler=1

	proto_config_add_string 'ipaddr:ipaddr'
	proto_config_add_string 'hostname:hostname'
	proto_config_add_string clientid
	proto_config_add_string vendorid
	proto_config_add_boolean 'broadcast:bool'
	proto_config_add_boolean 'norelease:bool'
	proto_config_add_string 'reqopts:list(string)'
	proto_config_add_boolean 'defaultreqopts:bool'
	proto_config_add_array 'sendopts:list(string)'
	proto_config_add_boolean delegate
	proto_config_add_string zone
	proto_config_add_string customroutes
	proto_config_add_boolean classlessroute
	proto_config_add_int 'timeout'
	proto_config_add_int 'retry'
	proto_config_add_int 'tryagain'
	proto_config_add_int 'dscp'
}

proto_admz_add_sendopts() {
	[ -n "$1" ] && append "$3" "-x $1"
}

proto_admz_get_default_clientid() {
	[ -z "$1" ] && return

	local iface="$1"
	local duid
	local iaid

	network_generate_iface_iaid iaid "$iface"
	duid="$(uci_get network @globals[0] dhcp_default_duid)"
	[ -n "$duid" ] && printf "ff%s%s" "$iaid" "$duid"
}

proto_admz_setup() {
	local config="$1"
	local iface="$2"

	local ipaddr hostname clientid vendorid broadcast norelease reqopts defaultreqopts sendopts delegate zone customroutes classlessroute timeout retry tryagain dscp
	json_get_vars ipaddr hostname clientid vendorid broadcast norelease reqopts defaultreqopts delegate zone customroutes classlessroute timeout retry tryagain dscp

	local opt dhcpopts
	for opt in $reqopts; do
		append dhcpopts "-O $opt"
	done

	json_for_each_item proto_admz_add_sendopts sendopts dhcpopts

	[ -z "$hostname" ] && hostname="$(cat /proc/sys/kernel/hostname)"
	[ "$hostname" = "*" ] && hostname=

	[ "$defaultreqopts" = 0 ] && defaultreqopts="-o" || defaultreqopts=
	[ "$broadcast" = 1 ] && broadcast="-B" || broadcast=
	[ "$norelease" = 1 ] && norelease="" || norelease="-R"
	[ -z "$clientid" ] && clientid="$(proto_admz_get_default_clientid "$iface")"
	[ -n "$clientid" ] && clientid="-x 0x3d:${clientid//:/}"
	[ -n "$vendorid" ] && append dhcpopts "-x 0x3c:$(echo -n "$vendorid" | hexdump -ve '1/1 "%02x"')"
	[ -n "$zone" ] && proto_export "ZONE=$zone"
	[ -n "$customroutes" ] && proto_export "CUSTOMROUTES=$customroutes"
	[ "$classlessroute" = "0" ] || append dhcpopts "-O 121"

	local emptyvendorid
	case "$dhcpopts" in
		*"-x 0"[xX]*"3"[cC]":"* |\
		*"-x 60:"* |\
		*"-x vendor:"*)
			emptyvendorid=1
			;;
	esac

	proto_export "INTERFACE=$config"
	proto_run_command "$config" udhcpc \
		-p /var/run/udhcpc-$iface.pid \
		-s /lib/netifd/admz.script \
		-f -t "${retry:-0}" -i "$iface" \
		${timeout:+-T "$timeout"} \
		${tryagain:+-A "$tryagain"} \
		${dscp:+--dscp "$dscp"} \
		${ipaddr:+-r ${ipaddr/\/*/}} \
		${hostname:+-x "hostname:$hostname"} \
		${emptyvendorid:+-V ""} \
		$clientid $defaultreqopts $broadcast $norelease $dhcpopts
}

proto_admz_renew() {
	local interface="$1"
	local sigusr1="$(kill -l SIGUSR1)"
	[ -n "$sigusr1" ] && proto_kill_command "$interface" $sigusr1
}

proto_admz_restart() {
	local interface="$1"
	local sighup="$(kill -l SIGHUP)"
	[ -n "$sighup" ] && proto_kill_command "$interface" $sighup
}

proto_admz_teardown() {
	local interface="$1"
	proto_kill_command "$interface"
}

add_protocol admz
