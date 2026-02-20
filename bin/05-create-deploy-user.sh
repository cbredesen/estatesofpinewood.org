#!/usr/bin/env bash
set -euo pipefail

# Creates an IAM user with minimal permissions to deploy the site:
#   - Sync files to the S3 bucket
#   - Create CloudFront cache invalidations
#
# Outputs access key credentials. Save them securely — the secret is only shown once.

BUCKET_NAME="estatesofpinewood.org"
USER_NAME="eop-deployer"

# Resolve CloudFront distribution ARN
echo "Looking up CloudFront distribution..."
DIST_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Aliases.Items[?@=='${BUCKET_NAME}']].Id | [0]" \
  --output text)

if [[ -z "${DIST_ID}" || "${DIST_ID}" == "None" ]]; then
  echo "Error: Could not find CloudFront distribution for ${BUCKET_NAME}."
  echo "Run 03-create-cloudfront.sh first."
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
DIST_ARN="arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${DIST_ID}"

echo "Found distribution: ${DIST_ID}"

POLICY_NAME="eop-deploy-policy"

POLICY_DOC=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3Sync",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ]
    },
    {
      "Sid": "CloudFrontInvalidate",
      "Effect": "Allow",
      "Action": "cloudfront:CreateInvalidation",
      "Resource": "${DIST_ARN}"
    }
  ]
}
EOF
)

# Create user
echo "Creating IAM user: ${USER_NAME}..."
aws iam create-user --user-name "${USER_NAME}"

# Create and attach inline policy
echo "Attaching deploy policy..."
aws iam put-user-policy \
  --user-name "${USER_NAME}" \
  --policy-name "${POLICY_NAME}" \
  --policy-document "${POLICY_DOC}"

# Create access key
echo "Creating access key..."
KEY_OUTPUT=$(aws iam create-access-key --user-name "${USER_NAME}" --output json)

ACCESS_KEY=$(echo "${KEY_OUTPUT}" | python3 -c "import sys,json; print(json.load(sys.stdin)['AccessKey']['AccessKeyId'])")
SECRET_KEY=$(echo "${KEY_OUTPUT}" | python3 -c "import sys,json; print(json.load(sys.stdin)['AccessKey']['SecretAccessKey'])")

echo ""
echo "Deploy user created!"
echo ""
echo "  User:       ${USER_NAME}"
echo "  Access Key:  ${ACCESS_KEY}"
echo "  Secret Key:  ${SECRET_KEY}"
echo ""
echo "Save these credentials securely — the secret key is only shown once."
echo ""
echo "To configure a named AWS profile:"
echo "  aws configure --profile eop-deployer"
