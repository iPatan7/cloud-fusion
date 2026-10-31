#!/bin/sh
# One round of the CPU and disk measurements, run inside the environment being
# measured (host, container, KVM guest or TCG guest).
#
#   CPU:  openssl speed, SHA-256 on 16 KiB blocks, one thread, 5 s -> MB/s
#   Disk: 256 MiB written and read back with O_DIRECT (no page cache) -> MB/s
#
#   sh cpu-disk.sh [directory-for-the-test-file]
DIR=${1:-/tmp}
echo "openssl: $(openssl version | cut -d' ' -f1-2)"
openssl speed -seconds 5 -bytes 16384 sha256 2>/dev/null \
  | awk '/^sha256/ { printf "cpu_sha256_MBps %.1f\n", $2 / 1000 }'
f="$DIR/cf-bench.$$"
w=$(dd if=/dev/zero of="$f" bs=1M count=256 oflag=direct conv=fsync 2>&1 | awk '/copied/ { print $(NF-1), $NF }')
r=$(dd if="$f" of=/dev/null bs=1M iflag=direct 2>&1 | awk '/copied/ { print $(NF-1), $NF }')
rm -f "$f"
echo "disk_write $w"
echo "disk_read $r"
