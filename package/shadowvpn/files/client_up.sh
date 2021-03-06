#!/bin/sh

# This script will be executed when client is up.
# All key value pairs in ShadowVPN config file will be passed to this script
# as environment variables, except password.

PID=$(cat $pidfile 2>/dev/null)
loger() {
	echo "$(date '+%c') up.$1 ShadowVPN[$PID] $2"
}

# Configure IP address and MTU of VPN interface
ifconfig $intf 10.7.0.2 netmask 255.255.255.0
ifconfig $intf mtu $mtu

# Get original gateway
device=$(ip route show 0/0 | grep via | sed -e 's/.* dev \([^ ]*\).*/\1/')
gateway=$(ip route show 0/0 | grep via | sed -e 's/.* via \([^ ]*\).*/\1/')
loger info "The default gateway: via $gateway dev $device"

# Get uci setting
route_mode=$(uci get shadowvpn.@shadowvpn[-1].route_mode 2>/dev/null)
route_file=$(uci get shadowvpn.@shadowvpn[-1].route_file 2>/dev/null)

# Save uci setting
uci set shadowvpn.@shadowvpn[-1].device_save=$device
uci set shadowvpn.@shadowvpn[-1].route_mode_save=$route_mode
uci commit shadowvpn

# Turn on NAT over VPN
iptables -t nat -A POSTROUTING -o $intf -j MASQUERADE
iptables -I FORWARD 1 -o $intf -j ACCEPT
iptables -I FORWARD 1 -i $intf -j ACCEPT
loger notice "Turn on NAT over $intf"

# Change routing table
ip route add $server via $gateway
if [ "$route_mode" != 2 ]; then
	ip route add 0.0.0.0/1 via 10.7.0.1
	ip route add 128.0.0.0/1 via 10.7.0.1
	loger notice "Default route changed to 10.7.0.1"
	suf="via $gateway"
else
	suf="via 10.7.0.1"
fi

# Load route rules
if [ "$route_mode" != 0 -a -f "$route_file" ]; then
	grep -E "^([0-9]{1,3}\.){3}[0-9]{1,3}" $route_file >/tmp/shadowvpn_routes
	sed -e "s/^/route add /" -e "s/$/ $suf/" /tmp/shadowvpn_routes | ip -batch -
	loger notice "Route rules have been loaded"
fi

loger info "Script $0 completed"
