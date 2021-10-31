#!/bin/sh
# this OpenVPN up/down script gets called like this: 
#    netns.sh tun0 1500 1584 10.8.8.18 255.255.255.0 init
# based on several comments in https://unix.stackexchange.com/questions/524052/how-to-connect-a-namespace-to-a-physical-interface-through-a-bridge-and-veth-pai
case $script_type in
        up)
                echo "vpn netns script called - up"
				echo Param 1 = "$1"
				echo Param 2 = "$2"
				echo Param 3 = "$3"
				echo Param 4 = "$4"
                echo "creating netns vpn"
                ip netns add vpn
                ip netns exec vpn ip link set dev lo up
                echo "putting openvpn in netns vpn"
                ip link set dev "$1" up netns vpn mtu "$2"
                ip netns exec vpn ip addr add dev "$1" \
                        "$4/24" \
                        ${ifconfig_broadcast:+broadcast "$ifconfig_broadcast"}
                echo "configuring route for openvpn"
                route_vpn_gateway=$(ip netns exec vpn ip route list table main | awk -v tun="$1" '/tun/ { print $9}')
                ip netns exec vpn ip route add default via "$route_vpn_gateway"
                echo "configuring netns vpn dsn settings"
                mkdir -p "/etc/netns/vpn"
                echo "nameserver 8.8.8.8" > /etc/netns/vpn/resolv.conf
                echo "nameserver 1.1.1.1" >> /etc/netns/vpn/resolv.conf
                echo "enable loopback interface in netns vpn"
                ip netns exec vpn ip link set lo up
                # echo "add macvlan0 interface and link it to eth0 interface as bridge"
                # ip link add macvlan0 link eth0 type macvlan mode bridge
                # echo "put macvlan0 interface into netns vpn"
                # ip link set macvlan0 netns vpn
                # echo "enable macvlan0 interface in netns vpn"
                # ip netns exec vpn ip link set macvlan0 up
                # echo "configure macvlan0 interface with 192.168.0.50 in netns vpn"
                # ip netns exec vpn ip addr add 192.168.0.50/24 dev macvlan0
                ;;
        down)
                echo "vpn netns script called - down"
                echo "deleting netns vpn"
                ip netns delete vpn
                echo "deleting macvlan0 interface"
                ip link delete macvlan0
                ;;
esac
