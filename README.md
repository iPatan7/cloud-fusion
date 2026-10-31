# Cloud Fusion: KVM, VMware and AWS for one application

One application, CivicSense (a Django civic complaint platform), moved through three
virtualisation worlds:

- **KVM** with libvirt on a laptop: virtual machines built from Debian's official cloud
  image as copy-on-write linked clones, configured by cloud-init, on a NAT network and
  an isolated network, with snapshots, ballooning, TRIM and suspend-to-disk;
- **VMware**: the same disk converted to VMware's formats, checked with VMware's own
  `vmware-vdiskmanager`, and booted again to prove it works;
- **AWS**: sizing, prices and the matching Debian AMI read from the AWS APIs, and the
  launch checked with a dry run (nothing created, nothing charged).

It is my project for **Cloud Virtualization (25CAH-733)**, MCA Cloud Computing &
DevOps, Chandigarh University, guided by Shah Dhruv Samir. The course project is
titled "Cloud Fusion: Bridging VMware, KVM, and AWS". The report is in
[`report/`](report/).

| Path | What it is |
|---|---|
| `kvm/fetch-base.sh` | Downloads the Debian 13 generic cloud image, checks it against Debian's SHA-512 list, stores it in the libvirt pool. |
| `kvm/provision.sh` | Linked clone + cloud-init + `virt-install`; prints the time to address, SSH and the end of cloud-init. `--tcg` runs the VM without hardware assistance. |
| `kvm/user-data.tmpl` | The cloud-init configuration (works unchanged on VMware and EC2). |
| `kvm/cf-isolated.xml`, `kvm/attach-nic.sh` | An isolated libvirt network and NIC hot-plug. |
| `kvm/snapshot-app.sh`, `kvm/snapshot-test.sh` | Disk-only and full (disk + RAM) snapshots, a bad change, and the revert. |
| `app/deploy-civicsense.sh` | Puts CivicSense into a VM: code, virtualenv, SQLite, gunicorn as a systemd service. |
| `bench/` | CPU and disk measurement (`cpu-disk.sh`, `Dockerfile` for the container baseline) and an HTTP load generator (`http.py`). |
| `convert/to-vmware.sh` | qcow2 to VMDK (streamOptimized and monolithicSparse), VMware checks, boot test, `.vmx`. |
| `aws/plan.sh`, `aws/VM-IMPORT.md` | Read-only AWS planning and the two migration paths to EC2. |

## Running it

Needs Linux with KVM, libvirt (`qemu:///system`), `virt-install`, `qemu-img`, Docker for
the container baseline, and optionally VMware Workstation's `vmware-vdiskmanager` and
the AWS CLI.

```bash
kvm/fetch-base.sh
kvm/provision.sh cf-app --memory 1536 --vcpus 2 --packages "python3-venv iperf3"
app/deploy-civicsense.sh cf-app          # then: curl http://<vm address>:8000/
kvm/provision.sh cf-tcg --tcg            # the same VM without hardware assistance
convert/to-vmware.sh cf-app
aws/plan.sh ap-south-1
```

One thing that cost an afternoon: `virt-install --graphics none` creates a VM without
any video device, and GRUB in the Debian 13 cloud image then resets the VM while it
loads the kernel, about once a second. `provision.sh` therefore adds `--video vga`.
