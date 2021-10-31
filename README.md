# OpenVPN Network Namespaces - openvpn-netns

When your ISP is actively blocking websites you need to access, one can use a VPN connection to circumvent the blockage.   With this **openvpn-netns** script, it is possible to use the local network and a direct internet connection through the ISP as usual, and additionally use a VPN connection to tunnel to blocked websites for affected apps and services.

This is an example configuration running on a Raspberry Pi and is using Surfshark as the VPN provider, using the OpenVPN configuration files that are available from them.

Note: This version of the script does require _root_ privileges to work.

![openvpn-netns schematic](https://github.com/bjaan/openvpn-netns/blob/main/schematic.png?raw=true)

As can be been seen above, the local port 32400 can still be made available on the local network (and ISP's IP-address through port forwarding)!

For services requiring the VPN connection, it is also possible to make their port (port 9091 in the schematic above) available on the local network and ISP's IP-address, through a special _socat_ command and, optionally, a separate IP-address (see further below).

## How it works

Once the **openvpn-netns** script is installed, and the OpenVPN service is started, it will:
1. open a VPN connection tunneled through the virtual _tun0_ network adapter, which  has a local IP-address in a different IP-range as the LAN, where all Internet bound traffic is routed through now. This is happening in a default OpenVPN installation already.
2. set-up a Linux network namespace called _vpn_
3. move the _tun0_ network adapter into the _vpn_ network namespace
4. configure DSN servers for the _vpn_ network namespace
5. optionally, create a virtual network adapter _macvlan0_ ([MACVLAN in Bridge mode](https://developers.redhat.com/blog/2018/10/22/introduction-to-linux-interfaces-for-virtual-networking#macvlan)) between the pythical LAN _eth0_ network adapter and the apps and services that need to access the Internet through the VPN tunnel.  It is will have a seperate IP-address which is accessible on the local network (Note: `ping` will not work on this IP-address, it will only have the exposed ports open, and there is no ICMP Echo Requests service running either).

When the OpenVPN service is stopped, the script will:
1. close the active VPN connection and remove the _tun0_ network adapter
2. remove the _vpn_ network namespace
3. remove the _macvlan0_ network adapter

## Installation
### a. OpenVPN service installation

1. First, install the OpenVPN service on Linux.

   Typically using the `sudo apt-get install openvpn` command.  The complete instructions for the Raspberry Pi are [here](https://openvpn.net/vpn-server-resources/install-openvpn-access-server-on-raspberry-pi/)

2. Elevate your permissions to _root_ to be able to do the next steps.

   `sudo -i`

3. Install the configuration file for OpenVPN that will allow it to connect the VPN provider; for Surfshark these can be downloaded [here](https://my.surfshark.com/vpn/manual-setup/main) on the _Locations_ tab.


   Download, e.g. with `wget`, and save the selected configuration under the `/etc/openvpn/` folder.
   Make sure that the name configuration file ends with the `.conf`, e.g. `/etc/openvpn/ch-zur.prod.surfshark.com_udp.conf`, that will allow OpenVPN to find it automatically, however we will still use point directly to it in the next steps.

4. Create a credentials file for OpenVPN, according to your VPN provider's instructions; for Surfshark this can be set-up on the _Credentials_ tab on [the same page](https://my.surfshark.com/vpn/manual-setup/main).

   These commands will create it under `/etc/openvpn/credentials.txt`
   ```sh
   echo "CHANGE TO YOUR USERNAME" >> /etc/openvpn/credentials.txt
   echo "CHANGE TO YOUR PASSWORD" >> /etc/openvpn/credentials.txt
   ```

5. Next. point to the OpenVPN configuration file in OpenVPN service file.  Typically in a systemd-based Linux, the service file for the OpenVPN service is located is `/etc/systemd/system/openvpn.service`.

   We need to update the `ExecStart` line in the `[Service]` section to make sure the OpenVPN service will use the selected configuration file.  E.g. for `/etc/openvpn/ch-zur.prod.surfshark.com_udp.conf` this would become:

   ```ini
   ExecStart=/usr/sbin/openvpn --config /etc/openvpn/ch-zur.prod.surfshark.com_udp.conf
   ```

6. Test if your VPN connection is working by starting the OpenVPN service: e.g. `sudo systemctl start openvpn`.  The whole host Internet access should now go through the VPN; see if the `traceroute www.google.com` command lists the VPN provider's domain names. Stop the service before proceeding `sudo systemctl start openvpn`

### b. Setting up the OpenVPN network namespace

7. Reconfigure OpenVPN service file further, so that it has to permissions to set-up network namespace (the same file as in step 5 above) further with these lines in the `[Service]` section:

   ```ini
   CapabilityBoundingSet=CAP_CHOWN CAP_DAC_OVERRIDE CAP_DAC_READ_SEARCH CAP_FOWNER CAP_FSETID CAP_KILL CAP_SETGID CAP_SETUID CAP_SETPCAP CAP_LINUX_IMMUTABLE CAP_NET_BIND_SERVICE
   CapabilityBoundingSet=CAP_NET_BROADCAST CAP_NET_ADMIN CAP_NET_RAW CAP_IPC_LOCK CAP_IPC_OWNER CAP_SYS_MODULE CAP_SYS_ROWIO CAP_SYS_CHROOT CAP_SYS_PTRACE CAP_SYS_PACCT CAP_SYS_ADMIN
   CapabilityBoundingSet=CAP_SYS_BOOT CAP_SYS_NICE CAP_SYS_RESOURCE CAP_SYS_TIME CAP_SYS_TTY_CONFIG CAP_MKNOD CAP_LEASE CAP_AUDIT_WRITE CAP_AUDIT_CONTROL CAP_SETFCAP CAP_MAC_OVERRIDE
   CapabilityBoundingSet=CAP_MAC_ADMIN CAP_SYSLOG CAP_WAKE_ALARM CAP_BLOCK_SUSPEND CAP_AUDIT_READ
   LimitNPROC=10
   DeviceAllow=/dev/null rw
   DeviceAllow=/dev/net/tun rw
   ```

   Note: the complete _openvpn.service_ file is in this repository.

8. Copy the `netns.sh` to `/etc/openvpn/` and run `chmod +x /etc/openvpn/netns.sh` to allow it be executed.

9. To enable the optional _macvlan0_ network adapter, which allows to access exposed ports on services in the _vpn_ network namespace, though a separate IP-address, neet to modify the `netns.sh` file.  Uncomment the following lines, by removing the first # and space after it:

```sh
# echo "add macvlan0 interface and link it to eth0 interface as bridge"
# ip link add macvlan0 link eth0 type macvlan mode bridge
# echo "put macvlan0 interface into netns vpn"
# ip link set macvlan0 netns vpn
# echo "enable macvlan0 interface in netns vpn"
# ip netns exec vpn ip link set macvlan0 up
# echo "configure macvlan0 interface with 192.168.0.50 in netns vpn"
# ip netns exec vpn ip addr add 192.168.0.50/24 dev macvlan0
```

   Change the IP-address on which this new network adapter _macvlan0_ will listen on the last two lines; it must be in the local network's IP-range - e.g. 192.168.1.236:

   These lines will look like:
```sh
echo "add macvlan0 interface and link it to eth0 interface as bridge"
ip link add macvlan0 link eth0 type macvlan mode bridge
echo "put macvlan0 interface into netns vpn"
ip link set macvlan0 netns vpn
echo "enable macvlan0 interface in netns vpn"
ip netns exec vpn ip link set macvlan0 up
echo "configure macvlan0 interface with 192.168.1.236 in netns vpn"
ip netns exec vpn ip addr add 192.168.1.236/24 dev macvlan0
```

10. Modify the OpenVPN configuration file (same file as in step 3): the following lines have to be added, before the `<ca>` line or at the very end:

   ```sh
   script-security 2
   auth-user-pass /etc/openvpn/credentials.txt

   writepid /run/openvpn/openvpn.pid
   route-noexec
   route-nopull
   route-up /etc/openvpn/netns.sh
   ifconfig-noexec
   up /etc/openvpn/netns.sh
   down /etc/openvpn/netns.sh
   ```

11. Start the OpenVPN service: `sudo systemctl start openvpn`

## Running an app or service in the network namespace

Note: the current version requires you to run as `root`. Suggestions on how run as regular user are welcome!

You need to `sudo` a call to `ip netns exec vpn`, which is then completed with command you want to run:

```sh
 sudo ip netns exec vpn traceroute www.google.com
```

For systemd-services, the service file needs to be modified: first add `Requires=openvpn.service` in the `[Unit]`-section, and then add `ExecStartPre=/bin/sleep 30` to `[Service]` for a wait time, e.g. 30 seconds, that will wait for the OpenVPN service setup the network namespace, and finally modify the `ExecStart=` line to `ExecStart=/usr/bin/sudo /sbin/ip netns exec vpn /usr/bin/sudo -u $USER <start command>`

Example:
```ini
[Unit]
...
After=network.target
Requires=openvpn.service
...

[Service]
...
User=pi
Group=pi
ExecStartPre=/bin/sleep 30
ExecStart=/usr/bin/sudo /sbin/ip netns exec vpn /usr/bin/sudo -u $USER /opt/Service/service_launcher.sh
...
```

## Making a service available on the local network

When an exposing a TCP-port that is only available within the network namespace, you might want to expose it on the local network.  It is automatically available through the IP-address of the _macvlan0_ adapter when it is used.

Otherwise, the following command will expose a TCP-port 9091 on the IP-address of the `eth0`-network adapter:

```sh
sudo socat tcp-listen:9091,fork,reuseaddr exec:'ip netns exec vpn socat STDIO tcp-connect\:127.0.0.1\:9091',nofork &
```

## Example of listing network adapters
```sh
# ip link show
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000
    link/ether dc:a6:32:57:39:cb brd ff:ff:ff:ff:ff:ff

# ip netns exec vpn ip link show
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
9: tun0: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UNKNOWN mode DEFAULT group default qlen 100
    link/none
32: macvlan0@if2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP mode DEFAULT group default qlen 1000
    link/ether da:03:45:4c:4a:ef brd ff:ff:ff:ff:ff:ff link-netnsid 0
```
## Example output in the OpenVPN service log
```
TUN/TAP device tun0 opened
TUN/TAP TX queue length set to 100
/etc/openvpn/scripts/netns.sh tun0 1500 1584 10.9.9.218 255.255.255.0 init
vpn netns script called - up
Param 1 = tun0
Param 2 = 1500
Param 3 = 1584
Param 4 = 10.9.9.218
creating netns vpn
putting openvpn in netns vpn
configuring route for openvpn
configuring netns vpn dsn settings
enable loopback interface in netns vpn
add macvlan0 interface and link it to eth0 interface as bridge
put macvlan0 interface into netns vpn
enable macvlan0 interface in netns vpn
ip netns exec vpn ip link set macvlan0 up
configure macvlan0 interface with 192.168.1.236 in netns vpn
Initialization Sequence Completed
```