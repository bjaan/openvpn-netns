#!/bin/sh
# OpenVPN network namespace setup script
#
# This script is called by OpenVPN using the following hooks:
#   up
#   route-up
#   down
#
# It moves the OpenVPN tunnel (tun0) into a dedicated network namespace
# called "vpn", so that applications can selectively use the VPN by running:
#
#   ip netns exec vpn <command>
#
# Optional: a macvlan interface can be enabled to expose services from the
# namespace on the LAN.

set -eu

NETNS=vpn

case "${script_type:-}" in

up)
    echo "vpn netns script called - up"
    echo "dev=$1 mtu=$2 ip=$4 mask=$5"

    echo "reset namespace"
    ip netns del "$NETNS" 2>/dev/null || true
    ip netns add "$NETNS"

    echo "enable loopback"
    ip netns exec "$NETNS" ip link set lo up

    echo "move tun interface into namespace"
    ip link set "$1" netns "$NETNS"

    echo "configure tun interface"
    ip netns exec "$NETNS" ip link set "$1" mtu "$2"
    ip netns exec "$NETNS" ip addr add "$4/$5" dev "$1"
    ip netns exec "$NETNS" ip link set "$1" up

    echo "configure default route"
    ip netns exec "$NETNS" ip route replace default dev "$1"

    echo "configure DNS"
    mkdir -p /etc/netns/$NETNS
    echo "nameserver 8.8.8.8" > /etc/netns/$NETNS/resolv.conf
    echo "nameserver 1.1.1.1" >> /etc/netns/$NETNS/resolv.conf


    ############################################################
    # OPTIONAL: expose namespace services to LAN via macvlan
    #
    # This creates a macvlan interface attached to eth0 and
    # assigns it a LAN IP address so services inside the
    # namespace become reachable from the local network.
    #
    # NOTE:
    # Linux hosts cannot normally reach their own macvlan
    # interfaces. Access must come from other LAN devices.
    #
    # To enable, uncomment the lines below and change the IP.
    ############################################################

    # echo "create macvlan interface"
    # ip link delete macvlan0 2>/dev/null || true
    # ip link add macvlan0 link eth0 type macvlan mode bridge
    #
    # echo "move macvlan into namespace"
    # ip link set macvlan0 netns "$NETNS"
    #
    # echo "enable macvlan interface"
    # ip netns exec "$NETNS" ip link set macvlan0 up
    #
    # echo "assign LAN IP address"
    # ip netns exec "$NETNS" ip addr add 192.168.0.50/24 dev macvlan0


    echo "vpn namespace ready"
    ;;

route-up)
    echo "route-up called - nothing to do"
    ;;

down)
    echo "vpn netns script called - down"

    # Optional macvlan cleanup (only needed if enabled)
    # ip netns exec "$NETNS" ip link delete macvlan0 2>/dev/null || true

    ip netns del "$NETNS" 2>/dev/null || true
    ;;

*)
    echo "netns.sh: ignoring script_type='${script_type:-}'"
    ;;

esac