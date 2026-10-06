#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PPPOE_PID=""

cleanup() {
    echo "Cleaning up..."

    if [ -n "$PPPOE_PID" ] && kill -0 "$PPPOE_PID" 2>/dev/null; then
        echo "Stopping pppoe-server (PID $PPPOE_PID)..."
        kill "$PPPOE_PID" 2>/dev/null || true
        wait "$PPPOE_PID" 2>/dev/null || true
    fi

    nftables_unload
    chap_secrets_restore
    vlan_destroy

    echo "Cleanup complete."
}

trap cleanup EXIT INT TERM

check_root
check_commands pppoe-server pppd nft ip
check_interface "$VLAN_PARENT_IF"
check_interface "$UPSTREAM_IF"

vlan_create
forwarding_enable
nftables_load
chap_secrets_setup

print_config "PPPoE"

pppoe-server -I "$VLAN_IF" \
    -L "$PPP_LOCAL_IP" \
    -R "$PPP_REMOTE_IP_START" \
    -N "$MAX_SESSIONS" \
    -O "$SCRIPT_DIR/ppp-options" \
    -F &

PPPOE_PID=$!

wait "$PPPOE_PID"
