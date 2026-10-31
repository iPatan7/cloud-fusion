#!/bin/sh
# Snapshot demonstration: takes an internal snapshot (disk and RAM) of a running VM,
# makes a bad change inside it, and reverts to the snapshot.
#
#   kvm/snapshot-test.sh <vm>
set -u
VM=$1
HERE=$(cd "$(dirname "$0")" && pwd)
v() { virsh -q -c qemu:///system "$@"; }
in_vm() { "$HERE/ssh.sh" "$VM" "$@" </dev/null; }
alloc() { v vol-info --pool default "$VM.qcow2" | awk '/Allocation/ {print $2, $3}'; }
now() { date +%s.%N; }
since() { awk -v a="$1" -v b="$(now)" 'BEGIN { printf "%.1f", b - a }'; }

in_vm 'sync; echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null; cat /etc/cf-marker; command -v iperf3'
echo "overlay before: $(alloc)"
echo "\$ virsh snapshot-create-as $VM before-change"
t=$(now); v snapshot-create-as "$VM" before-change --description "$VM before the test change"
echo "snapshot of disk and RAM taken in $(since "$t") s"
echo "overlay after: $(alloc)"
echo "--- a bad change: marker edited, iperf3 removed"
in_vm 'echo "marker: after" | sudo tee /etc/cf-marker >/dev/null; sudo dpkg -r iperf3 >/dev/null 2>&1; cat /etc/cf-marker; command -v iperf3 || echo "iperf3: gone"'
echo "\$ virsh snapshot-revert $VM before-change"
t=$(now); v snapshot-revert "$VM" before-change
echo "reverted in $(since "$t") s"
in_vm 'cat /etc/cf-marker; command -v iperf3; uptime -p'
v snapshot-list "$VM"
