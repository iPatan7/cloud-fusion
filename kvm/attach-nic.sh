#!/bin/sh
# Hot-plugs a virtio NIC on a libvirt network into a running VM and brings it up
# inside the guest with DHCP (netplan, matched by MAC address).
#
#   kvm/attach-nic.sh <vm> <network> <mac>
set -eu
VM=$1 NET=$2 MAC=$3
HERE=$(cd "$(dirname "$0")" && pwd)
virsh -q -c qemu:///system attach-interface "$VM" network "$NET" --model virtio --mac "$MAC" --live --config
"$HERE/ssh.sh" "$VM" "set -e
until ip -br link | grep -q '$MAC'; do sleep 0.5; done
printf 'network:\n  version: 2\n  ethernets:\n    $NET:\n      match: {macaddress: \"$MAC\"}\n      dhcp4: true\n      dhcp4-overrides: {use-routes: false}\n' | sudo tee /etc/netplan/60-$NET.yaml >/dev/null
sudo chmod 600 /etc/netplan/60-$NET.yaml
sudo netplan apply
until ip -4 -br addr | grep -q '10\.10\.10\.'; do sleep 0.5; done
ip -4 -br addr | grep '10\.10\.10\.'"
