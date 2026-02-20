#!/usr/bin/env bash
set -euo pipefail

# Creates a CloudFront distribution fronting the S3 bucket with HTTPS.
# Uses Origin Access Control (OAC) so the bucket stays private.
#
# Prerequisites:
#   - S3 bucket created (01-create-s3-bucket.sh)
#   - ACM certificate validated (02-request-certificate.sh)
#
# Usage:
#   CERT_ARN=arn:aws:acm:us-east-1:ACCOUNT:certificate/ID ./bin/03-create-cloudfront.sh

BUCKET_NAME="estatesofpinewood.org"
DOMAIN="estatesofpinewood.org"
REGION="us-east-1"

if [[ -z "${CERT_ARN:-}" ]]; then
  echo "Error: CERT_ARN environment variable is required."
  echo "Usage: CERT_ARN=arn:aws:acm:... ./bin/03-create-cloudfront.sh"
  exit 1
fi

CALLER_REF="eop-$(date +%s)"
S3_ORIGIN="${BUCKET_NAME}.s3.${REGION}.amazonaws.com"

# Create Origin Access Control
echo "Creating Origin Access Control..."
OAC_ID=$(aws cloudfront create-origin-access-control \
  --origin-access-control-config "{
    \"Name\": \"${BUCKET_NAME}-oac\",
    \"Description\": \"OAC for ${BUCKET_NAME}\",
    \"SigningProtocol\": \"sigv4\",
    \"SigningBehavior\": \"always\",
    \"OriginAccessControlOriginType\": \"s3\"
  }" \
  --query 'OriginAccessControl.Id' \
  --output text)

echo "OAC ID: ${OAC_ID}"

# Create CloudFront distribution
echo "Creating CloudFront distribution..."
DIST_CONFIG=$(cat <<EOF
{
  "CallerReference": "${CALLER_REF}",
  "Aliases": {
    "Quantity": 2,
    "Items": ["${DOMAIN}", "www.${DOMAIN}"]
  },
  "DefaultRootObject": "index.html",
  "Origins": {
    "Quantity": 1,
    "Items": [
      {
        "Id": "S3-${BUCKET_NAME}",
        "DomainName": "${S3_ORIGIN}",
        "OriginAccessControlId": "${OAC_ID}",
        "S3OriginConfig": {
          "OriginAccessIdentity": ""
        }
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "S3-${BUCKET_NAME}",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["GET", "HEAD"]
    },
    "CachedMethods": {
      "Quantity": 2,
      "Items": ["GET", "HEAD"]
    },
    "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
    "Compress": true
  },
  "CustomErrorResponses": {
    "Quantity": 1,
    "Items": [
      {
        "ErrorCode": 404,
        "ResponsePagePath": "/404.html",
        "ResponseCode": "404",
        "ErrorCachingMinTTL": 300
      }
    ]
  },
  "ViewerCertificate": {
    "ACMCertificateArn": "${CERT_ARN}",
    "SSLSupportMethod": "sni-only",
    "MinimumProtocolVersion": "TLSv1.2_2021"
  },
  "Enabled": true,
  "Comment": "Estates of Pinewood website",
  "HttpVersion": "http2and3",
  "PriceClass": "PriceClass_100"
}
EOF
)

DIST_ID=$(aws cloudfront create-distribution \
  --distribution-config "${DIST_CONFIG}" \
  --query 'Distribution.Id' \
  --output text)

DIST_DOMAIN=$(aws cloudfront get-distribution \
  --id "${DIST_ID}" \
  --query 'Distribution.DomainName' \
  --output text)

# Add S3 bucket policy granting CloudFront access
echo "Setting S3 bucket policy for CloudFront access..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

BUCKET_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontServicePrincipal",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudfront.amazonaws.com"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${DIST_ID}"
        }
      }
    }
  ]
}
EOF
)

aws s3api put-bucket-policy \
  --bucket "${BUCKET_NAME}" \
  --policy "${BUCKET_POLICY}"

echo ""
echo "CloudFront distribution created!"
echo "  Distribution ID: ${DIST_ID}"
echo "  Distribution domain: ${DIST_DOMAIN}"
echo ""
echo "Point your DNS records to the CloudFront distribution:"
echo "  ${DOMAIN}      -> ${DIST_DOMAIN} (ALIAS or CNAME)"
echo "  www.${DOMAIN}  -> ${DIST_DOMAIN} (CNAME)"
echo ""
echo "Next: run 04-deploy.sh to build and upload the site."
