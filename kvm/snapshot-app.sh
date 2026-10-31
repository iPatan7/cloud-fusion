#!/bin/sh
# Disk-only (external) snapshot of the application VM before a risky change, the
# change going wrong, and the way back.
#
#   1. eject the cloud-init CD-ROM: virt-install deletes the ISO after the first
#      boot, and a snapshot that refers to it cannot be reverted;
#   2. snapshot: libvirt freezes cf-app.qcow2 and writes all new data to a new
#      overlay on top of it (only the changes take space);
#   3. a bad "upgrade" deletes the application's virtual environment;
#   4. revert: the VM goes back to the frozen disk and is started again.
#
#   kvm/snapshot-app.sh [vm]        (default cf-app)
set -u
VM=${1:-cf-app}
HERE=$(cd "$(dirname "$0")" && pwd)
IP=$(cat "${CF_HOME:-$HOME/cloudfusion}/seed/$VM/ip")
v() { virsh -q -c qemu:///system "$@"; }
in_vm() { "$HERE/ssh.sh" "$VM" "$@" </dev/null; }
app() { curl -s -m 5 -o /dev/null -w "app: HTTP %{http_code}\n" "http://$IP:8000/" || true; }
now() { date +%s.%N; }
since() { awk -v a="$1" -v b="$(now)" 'BEGIN { printf "%.1f", b - a }'; }

v change-media "$VM" sda --eject --live --config >/dev/null 2>&1 || true
app
echo "\$ virsh snapshot-create-as $VM before-upgrade --disk-only --atomic"
t=$(now); v snapshot-create-as "$VM" before-upgrade --disk-only --atomic \
  --description "before a risky upgrade"
echo "snapshot taken in $(since "$t") s"
v domblklist "$VM" | awk '$1 == "vda"'
echo "--- the upgrade goes wrong: the virtual environment is deleted"
in_vm 'sudo systemctl stop civicsense; sudo rm -rf /opt/civicsense/venv; sudo systemctl start civicsense 2>/dev/null; sleep 2; systemctl is-active civicsense'
app
echo "\$ virsh snapshot-revert $VM before-upgrade && virsh start $VM"
t=$(now); v snapshot-revert "$VM" before-upgrade && v start "$VM" >/dev/null
until curl -fs -m 2 -o /dev/null "http://$IP:8000/healthz"; do sleep 0.5; done
echo "reverted and answering again after $(since "$t") s"
app
v snapshot-list "$VM"
