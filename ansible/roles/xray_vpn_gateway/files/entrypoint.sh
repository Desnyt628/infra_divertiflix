#!/bin/sh
set -e

[ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200

sysctl -w net.ipv4.ip_forward=1

xray run -c /config/xray.json &
sleep 2

openvpn --config /config/client.ovpn --daemon --writepid /tmp/ovpn.pid
sleep 3

# Fallback NAT so the gateway works even before pfsense2 has an
# iroute/client-specific-override for the Proxmox subnet(s).
# Drop this once routing (site-to-site) is set up on pfsense2.
iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE

wait "$(cat /tmp/ovpn.pid)"
