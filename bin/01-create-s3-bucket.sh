#!/usr/bin/env bash
set -euo pipefail

# Creates an S3 bucket for static website hosting.
# The bucket is NOT configured as a public website — CloudFront will access it
# via Origin Access Control (OAC), so no public access is needed.

BUCKET_NAME="estatesofpinewood.org"
REGION="us-east-1"

echo "Creating S3 bucket: ${BUCKET_NAME} in ${REGION}..."
aws s3api create-bucket \
  --bucket "${BUCKET_NAME}" \
  --region "${REGION}"

# Block all public access (CloudFront OAC will be granted access separately)
echo "Blocking public access..."
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo ""
echo "S3 bucket created: ${BUCKET_NAME}"
echo "Next: run 02-request-certificate.sh"
