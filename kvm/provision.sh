#!/bin/sh
# Creates a VM on KVM from the Debian base image: a copy-on-write overlay of the
# base volume (a linked clone), a cloud-init seed with the SSH key, and the VM
# itself. Prints how long each phase took.
#
#   kvm/provision.sh <name> [options]
#     --memory MiB       (default 1024)
#     --vcpus N          (default 2)
#     --disk GiB         virtual size of the overlay (default 8)
#     --network NAME     libvirt network (default "default", the NAT network)
#     --tcg              no hardware assistance: QEMU emulates the CPU in software
#     --packages "a b"   extra Debian packages installed by cloud-init
set -eu
NAME=$1; shift
MEM=1024 CPUS=2 DISK=8 NET=default VIRT=kvm PKGS=""
while [ $# -gt 0 ]; do
  case $1 in
    --memory) MEM=$2; shift ;; --vcpus) CPUS=$2; shift ;; --disk) DISK=$2; shift ;;
    --network) NET=$2; shift ;; --tcg) VIRT=qemu ;; --packages) PKGS=$2; shift ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac; shift
done
HERE=$(cd "$(dirname "$0")" && pwd)
CF="${CF_HOME:-$HOME/cloudfusion}"
KEY="$CF/keys/id_ed25519"
V="virsh -q -c qemu:///system"
BASE=cf-base-debian13.qcow2
now() { date +%s.%N; }
since() { awk -v a="$1" -v b="$(now)" 'BEGIN { printf "%.1f", b - a }'; }

# cloud-init seed
mkdir -p "$CF/seed/$NAME"
list=$(printf '%s' "$PKGS" | sed 's/ \+/, /g')
sed -e "s|@HOSTNAME@|$NAME|" -e "s|@SSH_KEY@|$(cat "$KEY.pub")|" \
    -e "s|@PACKAGES@|$list|" -e "s|@PACKAGE_UPDATE@|$([ -n "$PKGS" ] && echo true || echo false)|" \
    "$HERE/user-data.tmpl" > "$CF/seed/$NAME/user-data"
printf 'instance-id: %s-%s\nlocal-hostname: %s\n' "$NAME" "$(date +%s)" "$NAME" > "$CF/seed/$NAME/meta-data"

# linked clone: an overlay whose backing file is the shared base image
$V vol-create-as default "$NAME.qcow2" "${DISK}G" --format qcow2 \
   --backing-vol "$BASE" --backing-vol-format qcow2 >/dev/null

T0=$(now)
virt-install --connect qemu:///system --name "$NAME" --memory "$MEM" --vcpus "$CPUS" \
  --virt-type "$VIRT" --osinfo debian13 --import \
  --disk "vol=default/$NAME.qcow2,bus=virtio" --network "network=$NET,model=virtio" \
  --cloud-init "user-data=$CF/seed/$NAME/user-data,meta-data=$CF/seed/$NAME/meta-data" \
  --graphics none --video vga --noautoconsole --quiet
# --video vga: without any video device ("--graphics none" alone) GRUB in the Debian
# 13 cloud image resets the VM while loading the kernel, about once a second.
echo "$NAME: defined and started ($VIRT, $CPUS vCPU, $MEM MiB, network $NET) in $(since "$T0") s"

# wait for an address and for SSH
ip=""
until [ -n "$ip" ]; do
  ip=$($V domifaddr "$NAME" --source lease 2>/dev/null | awk '/ipv4/ { sub("/.*", "", $4); print $4; exit }')
  [ -n "$ip" ] || sleep 1
done
echo "$NAME: address $ip after $(since "$T0") s"
SSH="ssh -i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=3"
until $SSH "civic@$ip" true 2>/dev/null; do sleep 1; done
echo "$NAME: SSH answers after $(since "$T0") s"
$SSH "civic@$ip" cloud-init status --wait >/dev/null 2>&1 || true
echo "$NAME: cloud-init finished after $(since "$T0") s"
echo "$ip" > "$CF/seed/$NAME/ip"
