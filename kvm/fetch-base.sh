#!/bin/sh
# Downloads the official Debian 13 "generic" cloud image, checks it against the
# SHA-512 list published by Debian, and stores it in the libvirt pool "default" as
# the read-only base of every VM (each VM gets its own copy-on-write overlay).
#
# The "generic" image (not "genericcloud") is used on purpose: it carries the
# drivers for KVM (virtio), VMware (vmxnet3, pvscsi) and AWS (ENA, NVMe), so the
# same disk can be moved between the three platforms.
#
#   kvm/fetch-base.sh
set -eu
CACHE="${CF_HOME:-$HOME/cloudfusion}/cache"
URL=https://cloud.debian.org/images/cloud/trixie/latest
IMG=debian-13-generic-amd64.qcow2
VOL=cf-base-debian13.qcow2
mkdir -p "$CACHE"

t=$(date +%s)
curl -fsSL -o "$CACHE/SHA512SUMS" "$URL/SHA512SUMS"
[ -f "$CACHE/$IMG" ] || curl -fL --progress-bar -o "$CACHE/$IMG" "$URL/$IMG"
echo "download: $(( $(date +%s) - t )) s, $(du -h "$CACHE/$IMG" | cut -f1)"
( cd "$CACHE" && grep " $IMG\$" SHA512SUMS | sha512sum -c - )

qemu-img info "$CACHE/$IMG" | grep -E 'file format|virtual size|disk size'
if ! virsh -q -c qemu:///system vol-info --pool default "$VOL" >/dev/null 2>&1; then
  size=$(stat -c %s "$CACHE/$IMG")
  virsh -q -c qemu:///system vol-create-as default "$VOL" "$size" --format qcow2
  virsh -q -c qemu:///system vol-upload --pool default "$VOL" "$CACHE/$IMG"
fi
virsh -c qemu:///system vol-info --pool default "$VOL"
