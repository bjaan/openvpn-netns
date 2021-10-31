# Set-up a network namespace for OpenVPN to unblock internet access for specific apps and services

When your ISP is actively blocking certain websites, one can use a VPN to circumvent the blockage.  With this script, it is still possible to use the local network and a direct internet connection through the ISP, and still use the VPN connection to tunnel to blocked websites.

Once the **openvpn-netns** script is installed, and the OpenVPN service is started, it will:
1. open a VPN connection tunneled through the virtual _tun0_ network adapter, which  has a local IP-address in a different IP-range as the LAN, where all Internet is routed through now. This is happening in a default installation already.
2. set-up a Linux network namespace called _vpn_
3. move the _tun0_ network adapter into the _vpn_ namespace
4. configure DSN servers for the network namespace
5. create a virtual network adapter _macvlan0_ ([MACVLAN in Bridge mode](https://developers.redhat.com/blog/2018/10/22/introduction-to-linux-interfaces-for-virtual-networking#macvlan)) between the pythical LAN _eth0_ network adapter and the apps and services that need to access the Internet through the VPN tunnel

When the OpenVPN service is stopped, the script will:
1. close the active VPN connection and remove the _tun0_ network adapter
2. remove the _vpn_ network namespace

![openvpn-netns schematic](https://github.com/bjaan/openvpn-netns/blob/main/schematic.png?raw=true)

As can been seen above, the local port 32400 can still be made available on the local network (and ISP's IP-address through port forwarding)!
For services running requiring the VPN connection, it is also possible to make their port (port 9091 in the schematic above) available on the local network and ISP's IP-address, through a special _socat_ command (see further below).

This is an example that is running on a Raspberry Pi and is using Surfshark as the VPN provider, using the OpenVPN 
configuration files that are available from them.  This version of the scripts does require _root_ privileges to work.

## Installation
### a. OpenVPN service installation

1. First, install the OpenVPN service on Linux.

   Typically using the `sudo apt-get install openvpn` command.  For complete instructions for the Raspberry Pi: https://openvpn.net/vpn-server-resources/install-openvpn-access-server-on-raspberry-pi/

2. Elevate your permissions to _root_ to be able to do the next steps.

   `sudo -i`

3. Install configuration file for OpenVPN that will allow it to connect the VPN provider; for Surfshark these can be downloaded [here](https://my.surfshark.com/vpn/manual-setup/main) on _Locations_ tab.


   Download, e.g. with `wget`, and save the selected configuration under the `/etc/openvpn/` folder.
   Make sure that the name configuration file ends with the `.conf`, `/etc/openvpn/ch-zur.prod.surfshark.com_udp.conf`, that will allow OpenVPN to find it automatically, however we will still use point directly to it in the next steps.

4. Create a credentials file for OpenVPN, according to your VPN provider's instructions; for Surfshark this can be set-up on the _Credentials_ tab on [the same page](https://my.surfshark.com/vpn/manual-setup/main)
   These commands will create it under `/etc/openvpn/credentials.txt`
   ```sh
   echo "CHANGE TO YOUR USERNAME" >> /etc/openvpn/credentials.txt
   echo "CHANGE TO YOUR PASSWORD" >> /etc/openvpn/credentials.txt
   ```

5. Point to configuration file in service file.  Typically in a systemd-based Linux, the configuration file for the OpenVPN service is located at `/etc/systemd/system/openvpn.service`.
   We need to update the `ExecStart` setting the `[Service]` section to make sure the OpenVPN service will use the correct configuration file, for `/etc/openvpn/ch-zur.prod.surfshark.com_udp.conf` this would become:

   ```ini
   ExecStart=/usr/sbin/openvpn --config /etc/openvpn/ch-zur.prod.surfshark.com_udp.conf
   ```

6. Test if your VPN connection is working by starting the OpenVPN service: `sudo systemctl start openvpn`.  The whole host should now be connected through the VPN; see through `traceroute www.google.com` that it lists the VPN provider's domain names. Stop the service before proceeding `sudo systemctl start openvpn`

### b. Setting up the OpenVPN network namespace

7. Reconfigure OpenVPN service file further, so that it has to permissions to set-up network namespace, see first configuration in step 5 above, further with these lines in the `[Service]` section:

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

9. Modify the OpenVPN configuration file: the following lines have to be added, before the `<ca>` line or at the very end:

   ```sh
   script-security 2
   auth-user-pass /etc/openvpn/credentials.txt

   writepid /run/openvpn/openvpn.pid
   route-noexec
   route-nopull
   route-up /etc/openvpn/scripts/netns.sh
   ifconfig-noexec
   up /etc/openvpn/scripts/netns.sh
   down /etc/openvpn/scripts/netns.sh
   ```

## Running an app or service in the network namespace

Note: the current version requires you to run as `root`. Suggestions on how run as regular are welcome!

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
ExecStartPre=/bin/sleep 30
ExecStart=/usr/bin/sudo /sbin/ip netns exec vpn /usr/bin/sudo -u $USER /opt/Service/service_launcher.sh
...
```

## Making an service available on the local network

When an  exposing a TCP-port that is only available within the network namespace, you might want to expose it on the internet.

The following command will expose a TCP-port 9091:

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
```
## Example output in the OpenVPN service log
```
TUN/TAP device tun0 opened
TUN/TAP TX queue length set to 100
/etc/openvpn/scripts/netns.sh tun0 1500 1584 10.8.8.18 255.255.255.0 init
vpn netns script called - up
Param 1 = tun0
Param 2 = 1500
Param 3 = 1584
Param 4 = 10.8.8.18
creating netns vpn
putting openvpn in netns vpn
configuring route for openvpn
configuring netns vpn dsn settings
enable loopback interface in netns vpn
Initialization Sequence Completed
`` 