#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

LISTEN_ADDR="10.99.1.1"
LISTEN_ADDR_PREFIX="24"

XL2TPD_PID=""
XL2TPD_CONF=""
XL2TPD_CONTROL=""
XL2TPD_PIDFILE=""

cleanup() {
    echo "Cleaning up..."

    if [ -n "$XL2TPD_PID" ] && kill -0 "$XL2TPD_PID" 2>/dev/null; then
        echo "Stopping xl2tpd (PID $XL2TPD_PID)..."
        kill "$XL2TPD_PID" 2>/dev/null || true
        wait "$XL2TPD_PID" 2>/dev/null || true
    fi

    [ -n "$XL2TPD_CONF" ] && rm -f "$XL2TPD_CONF"
    [ -n "$XL2TPD_CONTROL" ] && rm -f "$XL2TPD_CONTROL"
    [ -n "$XL2TPD_PIDFILE" ] && rm -f "$XL2TPD_PIDFILE"

    nftables_unload
    chap_secrets_restore
    vlan_destroy

    echo "Cleanup complete."
}

trap cleanup EXIT INT TERM

check_root
check_commands xl2tpd pppd nft ip
check_interface "$VLAN_PARENT_IF"
check_interface "$UPSTREAM_IF"

vlan_create

echo "Assigning IP $LISTEN_ADDR/$LISTEN_ADDR_PREFIX to $VLAN_IF..."
ip addr add "$LISTEN_ADDR/$LISTEN_ADDR_PREFIX" dev "$VLAN_IF"

forwarding_enable
nftables_load
chap_secrets_setup

XL2TPD_CONF=$(mktemp /tmp/xl2tpd.conf.XXXXXX)
XL2TPD_CONTROL=$(mktemp /tmp/xl2tpd.control.XXXXXX)
XL2TPD_PIDFILE=$(mktemp /tmp/xl2tpd.pid.XXXXXX)
rm -f "$XL2TPD_CONTROL"

sed -e "s|__LISTEN_ADDR__|${LISTEN_ADDR}|g" \
    -e "s|__PPP_LOCAL_IP__|${PPP_LOCAL_IP}|g" \
    -e "s|__PPP_REMOTE_START__|${PPP_REMOTE_IP_START}|g" \
    -e "s|__PPP_REMOTE_END__|${PPP_REMOTE_IP_END}|g" \
    -e "s|__PPP_OPTIONS__|${SCRIPT_DIR}/ppp-options|g" \
    "$SCRIPT_DIR/xl2tpd.conf" > "$XL2TPD_CONF"

print_config "L2TP"
echo "  L2TP listen: $LISTEN_ADDR:1701"
echo ""

xl2tpd -D -c "$XL2TPD_CONF" -C "$XL2TPD_CONTROL" -p "$XL2TPD_PIDFILE" &
XL2TPD_PID=$!

wait "$XL2TPD_PID"
