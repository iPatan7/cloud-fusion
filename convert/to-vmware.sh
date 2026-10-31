#!/bin/sh
# Turns the disk of a Cloud Fusion VM into VMware formats and checks each result.
#
#   1. the VM is shut down and its disk (with its backing file, if any) is copied
#      out of the libvirt pool;
#   2. qemu-img writes one flat VMDK per VMware subformat:
#        streamOptimized   - compressed; the format inside OVA files and the one
#                            AWS VM Import expects
#        monolithicSparse  - VMware Workstation's usual growable disk
#   3. VMware's own vmware-vdiskmanager opens the Workstation disk;
#   4. the Workstation disk is booted with QEMU/KVM (changes thrown away) to prove
#      the converted disk starts the system;
#   5. a .vmx file describing the VM for VMware Workstation is written.
#   Each VMDK is deleted after its checks unless KEEP=1 (disk space is short).
#
#   convert/to-vmware.sh <vm>
set -eu
VM=$1
CF="${CF_HOME:-$HOME/cloudfusion}"
OUT="$CF/export/$VM"
v() { virsh -q -c qemu:///system "$@"; }
now() { date +%s.%N; }
since() { awk -v a="$1" -v b="$(now)" 'BEGIN { printf "%.1f", b - a }'; }
mkdir -p "$OUT"

if [ "$(v domstate "$VM")" = running ]; then
  v shutdown "$VM" >/dev/null
  until [ "$(v domstate "$VM")" = "shut off" ]; do sleep 1; done
fi
DISK=$(v domblklist "$VM" | awk '$1 == "vda" {print $2}')
VOL=$(basename "$DISK")
t=$(now); v vol-download --sparse --pool default "$VOL" "$OUT/source.qcow2"
echo "copied $VOL out of the pool: $(du -h "$OUT/source.qcow2" | cut -f1) in $(since "$t") s"
backing=$(qemu-img info --output=json "$OUT/source.qcow2" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("backing-filename", ""))')
if [ -n "$backing" ]; then
  v vol-download --sparse --pool default "$(basename "$backing")" "$OUT/backing.qcow2"
  qemu-img rebase -u -F qcow2 -b "$OUT/backing.qcow2" "$OUT/source.qcow2"
fi
qemu-img info "$OUT/source.qcow2" | grep -E 'virtual size|disk size'

# A flat VMDK can need as much space as the data in the disk: refuse to start a
# conversion unless that much (plus 300 MiB of margin) is free.
# (qemu-img measure gives the size of the data once uncompressed)
need=$(( $(qemu-img measure --output=json -O qcow2 "$OUT/source.qcow2" | python3 -c 'import json,sys; print(json.load(sys.stdin)["required"])') / 1048576 + 300 ))
echo "space needed per conversion: $need MiB"
for fmt in ${FORMATS:-streamOptimized monolithicSparse}; do
  f="$OUT/$VM-$fmt.vmdk"
  free=$(df -m --output=avail "$OUT" | tail -1)
  if [ "$free" -lt "$need" ]; then echo "--- $fmt: skipped, $free MiB free, $need MiB needed"; continue; fi
  t=$(now)
  qemu-img convert -O vmdk -o subformat=$fmt,adapter_type=lsilogic "$OUT/source.qcow2" "$f"
  echo "--- $fmt: $(du -h "$f" | cut -f1) on disk, written in $(since "$t") s"
  qemu-img info "$f" | grep -E 'file format|virtual size'
  if [ $fmt = monolithicSparse ]; then
    echo "vmware-vdiskmanager -e: $(vmware-vdiskmanager -e "$f" 2>&1 | grep -v '^\s*$' | tail -1)"
    vmware-vdiskmanager -R "$f" >/dev/null 2>&1; echo "vmware-vdiskmanager -R (check and repair): exit $?, nothing to repair when 0"
    log="$OUT/boot-$fmt.log"
    t=$(now)
    timeout -s KILL 60 qemu-system-x86_64 -enable-kvm -cpu host -m 1024 -display none -vga std \
      -serial file:"$log" -drive file="$f",format=vmdk,if=virtio,snapshot=on >/dev/null 2>&1 || true
    if grep -q 'login:' "$log"; then
      echo "booted from the VMDK on KVM: login prompt reached ($(grep -m1 -o 'Debian GNU/Linux [0-9]*' "$log"))"
    else
      echo "boot from the VMDK did not reach a login prompt within 60 s"
    fi
  fi
  [ "${KEEP:-0}" = 1 ] || rm -f "$f"
done
rm -f "$OUT/source.qcow2" "$OUT/backing.qcow2"

cat > "$OUT/$VM.vmx" <<EOF
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "19"
displayName = "$VM (Cloud Fusion)"
guestOS = "debian12-64"
firmware = "bios"
numvcpus = "2"
memsize = "1536"
scsi0.present = "TRUE"
scsi0.virtualDev = "pvscsi"
scsi0:0.present = "TRUE"
scsi0:0.fileName = "$VM-monolithicSparse.vmdk"
ethernet0.present = "TRUE"
ethernet0.virtualDev = "vmxnet3"
ethernet0.connectionType = "nat"
ethernet0.addressType = "generated"
serial0.present = "TRUE"
serial0.fileType = "file"
serial0.fileName = "$VM-serial.log"
EOF
echo "--- $OUT/$VM.vmx written"
v start "$VM" >/dev/null
