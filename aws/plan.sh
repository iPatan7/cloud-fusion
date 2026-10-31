#!/bin/sh
# Migration planning for the AWS side of Cloud Fusion, using only read-only AWS
# calls and dry runs: nothing is created and nothing is charged.
#
#   1. candidate instance types and their vCPU / memory (EC2 DescribeInstanceTypes)
#   2. on-demand Linux price of each in the chosen region (AWS Price List API)
#   3. the newest official Debian 13 image in that region (owner 136693071363, Debian)
#   4. a dry run of RunInstances with that image: proves the account may launch it
#
#   aws/plan.sh [region]          (default ap-south-1, Mumbai)
set -u
REGION=${1:-ap-south-1}
TYPES="t3.micro t3.small t3.medium t4g.small m7i.large"
LOCATION=$(aws ssm get-parameter --region "$REGION" --name "/aws/service/global-infrastructure/regions/$REGION/longName" \
  --query Parameter.Value --output text 2>/dev/null || echo "Asia Pacific (Mumbai)")
echo "region $REGION ($LOCATION), account $(aws sts get-caller-identity --query Account --output text)"

echo "--- instance types"
aws ec2 describe-instance-types --region "$REGION" --instance-types $TYPES \
  --query 'sort_by(InstanceTypes, &InstanceType)[].[InstanceType, VCpuInfo.DefaultVCpus, MemoryInfo.SizeInMiB, ProcessorInfo.SupportedArchitectures[0], NetworkInfo.NetworkPerformance]' \
  --output text

echo "--- on-demand price per hour (Linux, shared tenancy)"
for t in $TYPES; do
  p=$(aws pricing get-products --region us-east-1 --service-code AmazonEC2 --output json --filters \
      "Type=TERM_MATCH,Field=instanceType,Value=$t" "Type=TERM_MATCH,Field=location,Value=$LOCATION" \
      "Type=TERM_MATCH,Field=operatingSystem,Value=Linux" "Type=TERM_MATCH,Field=tenancy,Value=Shared" \
      "Type=TERM_MATCH,Field=preInstalledSw,Value=NA" "Type=TERM_MATCH,Field=capacitystatus,Value=Used" 2>&1)
  case "$p" in
    *AccessDenied*|*UnauthorizedOperation*|*"not authorized"*) echo "$t: price list not readable with this IAM user"; continue ;;
  esac
  echo "$p" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for item in d.get("PriceList", []):
    o = json.loads(item)
    for term in o["terms"]["OnDemand"].values():
        for dim in term["priceDimensions"].values():
            print("'"$t"'", dim["pricePerUnit"]["USD"], "USD/h")'
done

echo "--- newest official Debian 13 image"
AMI=$(aws ec2 describe-images --region "$REGION" --owners 136693071363 \
  --filters "Name=name,Values=debian-13-amd64-*" "Name=architecture,Values=x86_64" \
  --query 'sort_by(Images, &CreationDate)[-1].[ImageId, Name, CreationDate]' --output text)
echo "$AMI"

echo "--- dry run of RunInstances (t3.small, nothing is launched)"
aws ec2 run-instances --region "$REGION" --dry-run --image-id "$(echo "$AMI" | cut -f1)" \
  --instance-type t3.small --count 1 2>&1 | tail -1
