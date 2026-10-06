#!/bin/bash
# Common helper functions for PPP server scripts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${UPSTREAM_IF:=enp1s0}"
: "${VLAN_PARENT_IF:=enp1s0}"
: "${VLAN_ID:=7}"
: "${PPP_LOCAL_IP:=10.99.0.1}"
: "${PPP_REMOTE_IP_START:=10.99.0.10}"
: "${PPP_REMOTE_IP_END:=10.99.0.50}"
: "${PPP_SUBNET:=10.99.0.0/24}"
: "${IPV6_PREFIX:=fd00:0:0:99::/64}"
: "${IPV6_NET:=fd00:0:0:99::}"
: "${IPV6_LOCAL:=fd00:0:0:99::1}"
: "${MAX_SESSIONS:=40}"

VLAN_IF="${VLAN_PARENT_IF}.${VLAN_ID}"
CHAP_BACKUP=""

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root"
        exit 1
    fi
}

check_commands() {
    local cmds=("$@")
    for cmd in "${cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "Required command not found: $cmd"
            exit 1
        fi
    done
}

check_interface() {
    local iface="$1"
    if ! ip link show "$iface" &>/dev/null; then
        echo "Interface $iface not found"
        exit 1
    fi
}

vlan_create() {
    echo "Creating VLAN interface $VLAN_IF..."
    ip link add link "$VLAN_PARENT_IF" name "$VLAN_IF" type vlan id "$VLAN_ID"
    ip link set "$VLAN_IF" up
}

vlan_destroy() {
    echo "Removing VLAN interface $VLAN_IF..."
    ip link del "$VLAN_IF" 2>/dev/null || true
}

forwarding_enable() {
    echo "Enabling IP forwarding..."
    echo 1 > /proc/sys/net/ipv4/ip_forward
    echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
}

nftables_load() {
    echo "Loading nftables rules..."
    sed -e "s|__UPSTREAM_IF__|${UPSTREAM_IF}|g" \
        -e "s|__PPP_SUBNET__|${PPP_SUBNET}|g" \
        -e "s|__IPV6_NET__|${IPV6_NET}|g" \
        "$SCRIPT_DIR/nftables.conf" | nft -f -
}

nftables_unload() {
    echo "Removing nftables rules..."
    nft delete table inet ppp_nat 2>/dev/null || true
}

chap_secrets_setup() {
    echo "Setting up chap-secrets..."
    mkdir -p /etc/ppp
    if [ -f /etc/ppp/chap-secrets ] && [ ! -L /etc/ppp/chap-secrets ]; then
        CHAP_BACKUP="/etc/ppp/chap-secrets.backup.$$"
        mv /etc/ppp/chap-secrets "$CHAP_BACKUP"
    fi
    ln -sf "$SCRIPT_DIR/chap-secrets" /etc/ppp/chap-secrets
}

chap_secrets_restore() {
    if [ -n "$CHAP_BACKUP" ] && [ -f "$CHAP_BACKUP" ]; then
        echo "Restoring original chap-secrets..."
        mv "$CHAP_BACKUP" /etc/ppp/chap-secrets
    elif [ -L /etc/ppp/chap-secrets ]; then
        rm -f /etc/ppp/chap-secrets
    fi
}

print_config() {
    local server_type="$1"
    echo "Starting $server_type server on $VLAN_IF..."
    echo "  Local IP: $PPP_LOCAL_IP"
    echo "  Remote IP pool: $PPP_REMOTE_IP_START - $PPP_REMOTE_IP_END"
    echo "  IPv6 prefix: $IPV6_PREFIX"
    echo "  Masquerade via: $UPSTREAM_IF"
    echo ""
    echo "Press Ctrl+C to stop"
    echo ""
}
