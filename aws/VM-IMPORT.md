# Moving the CivicSense VM to AWS

Two ways lead from the KVM virtual machine to EC2. Both were prepared; neither was
run, because both create resources (and costs) in the AWS account.

## 1. Re-platform: a fresh Debian 13 instance, configured the same way (recommended)

The VM was built from Debian's official cloud image with cloud-init. Debian publishes
the same build as an AMI (`aws/plan.sh` found `ami-0b692bf37c2b621d7`,
`debian-13-amd64-20261026-2643`, in ap-south-1), and EC2 runs cloud-init too. So the
same `user-data` and the same `app/deploy-civicsense.sh` produce the same server on
EC2. `aws/plan.sh` checked with a dry run that the account may launch it:

```
aws ec2 run-instances --region ap-south-1 --image-id ami-0b692bf37c2b621d7 \
  --instance-type t3.small --user-data file://user-data --key-name <key> \
  --security-group-ids <sg allowing 22 and 8000 from your address>
app/deploy-civicsense.sh <instance>      # same script as for the KVM VM
```

## 2. Lift and shift: import the VM's own disk (VM Import/Export)

`convert/to-vmware.sh` writes `cf-app-streamOptimized.vmdk` (443 MB), the format
VM Import expects. The import needs an S3 bucket and the `vmimport` service role:

```
aws s3 cp cf-app-streamOptimized.vmdk s3://<bucket>/cf-app.vmdk
aws iam create-role --role-name vmimport --assume-role-policy-document file://trust-policy.json
aws iam put-role-policy --role-name vmimport --policy-name vmimport --policy-document file://role-policy.json
aws ec2 import-image --region ap-south-1 --description "cf-app from KVM" \
  --disk-containers 'Format=vmdk,UserBucket={S3Bucket=<bucket>,S3Key=cf-app.vmdk}'
aws ec2 describe-import-image-tasks --region ap-south-1     # until the AMI is ready
```

The Debian "generic" image carries the ENA and NVMe drivers EC2 needs, which is why
it was chosen over "genericcloud".

## Sizing and cost (Mumbai, on-demand Linux, read with `aws/plan.sh` on 31 Oct 2026)

| Type | vCPU | Memory | USD / hour | USD / month (730 h) |
|---|---|---|---|---|
| t3.micro | 2 | 1 GiB | 0.0112 | 8.18 |
| t3.small | 2 | 2 GiB | 0.0224 | 16.35 |
| t4g.small (arm64) | 2 | 2 GiB | 0.0112 | 8.18 |
| t3.medium | 2 | 4 GiB | 0.0448 | 32.70 |
| m7i.large | 2 | 8 GiB | 0.10605 | 77.42 |

Plus EBS gp3 at 0.0912 USD per GB-month (8 GB: 0.73 USD/month).
