#!/usr/bin/env bash
set -euo pipefail

# Builds the Hugo site and syncs it to S3, then invalidates the CloudFront cache.
#
# Usage:
#   ./bin/04-deploy.sh                          # uses default distribution
#   DIST_ID=E1234567890 ./bin/04-deploy.sh      # override distribution ID

BUCKET_NAME="estatesofpinewood.org"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUGO_DIR="${SCRIPT_DIR}/../hugo-site"

# Resolve CloudFront distribution ID if not provided
if [[ -z "${DIST_ID:-}" ]]; then
  echo "Looking up CloudFront distribution ID..."
  DIST_ID=$(aws cloudfront list-distributions \
    --query "DistributionList.Items[?Aliases.Items[?@=='${BUCKET_NAME}']].Id | [0]" \
    --output text)
  if [[ -z "${DIST_ID}" || "${DIST_ID}" == "None" ]]; then
    echo "Error: Could not find CloudFront distribution for ${BUCKET_NAME}."
    echo "Pass DIST_ID=... or run 03-create-cloudfront.sh first."
    exit 1
  fi
  echo "Found distribution: ${DIST_ID}"
fi

# Build
echo "Building Hugo site..."
hugo --source "${HUGO_DIR}" --minify

# Sync to S3
echo "Syncing to s3://${BUCKET_NAME}/..."
aws s3 sync "${HUGO_DIR}/public/" "s3://${BUCKET_NAME}/" \
  --delete \
  --cache-control "public, max-age=86400"

# Invalidate CloudFront cache
echo "Invalidating CloudFront cache..."
INVALIDATION_ID=$(aws cloudfront create-invalidation \
  --distribution-id "${DIST_ID}" \
  --paths "/*" \
  --query 'Invalidation.Id' \
  --output text)

echo ""
echo "Deploy complete!"
echo "  S3 bucket: ${BUCKET_NAME}"
# echo "  CloudFront invalidation: ${INVALIDATION_ID}"
