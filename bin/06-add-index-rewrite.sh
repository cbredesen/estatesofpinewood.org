#!/usr/bin/env bash
set -euo pipefail

# Adds a CloudFront Function that rewrites directory-style paths
# (e.g. /resources) to their index.html equivalent (/resources/index.html).
#
# This is needed because CloudFront's DefaultRootObject only handles the
# root "/" path; S3+OAC returns 403 for subpaths without a file extension.
#
# Run this once against the existing distribution.
#
# Usage:
#   ./bin/06-add-index-rewrite.sh

BUCKET_NAME="estatesofpinewood.org"
FUNCTION_NAME="eop-index-rewrite"

# Write the CloudFront Function code to a temp file (CLI requires a file blob)
TMPFILE=$(mktemp /tmp/cf-function-XXXXXX.js)
trap "rm -f ${TMPFILE}" EXIT

cat > "${TMPFILE}" <<'JSCODE'
function handler(event) {
    var request = event.request;

    // Redirect www to non-www
    var host = request.headers.host && request.headers.host.value;
    if (host === 'www.estatesofpinewood.org') {
        return {
            statusCode: 301,
            statusDescription: 'Moved Permanently',
            headers: {
                location: { value: 'https://estatesofpinewood.org' + request.uri }
            }
        };
    }

    // Rewrite directory paths to index.html
    var uri = request.uri;
    if (uri.endsWith('/')) {
        request.uri += 'index.html';
    } else if (!uri.includes('.')) {
        request.uri += '/index.html';
    }
    return request;
}
JSCODE

# Locate the distribution
echo "Looking up CloudFront distribution..."
DIST_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Aliases.Items[?@=='${BUCKET_NAME}']].Id | [0]" \
  --output text)

if [[ -z "${DIST_ID}" || "${DIST_ID}" == "None" ]]; then
  echo "Error: Could not find a CloudFront distribution aliased to ${BUCKET_NAME}."
  echo "Run 03-create-cloudfront.sh first."
  exit 1
fi
echo "Found distribution: ${DIST_ID}"

# Create the CloudFront Function (DEVELOPMENT stage)
echo "Creating CloudFront Function '${FUNCTION_NAME}'..."
FUNC_ETAG=$(aws cloudfront create-function \
  --name "${FUNCTION_NAME}" \
  --function-config '{"Comment":"Redirect www to non-www; rewrite directory paths to index.html","Runtime":"cloudfront-js-2.0"}' \
  --function-code "fileb://${TMPFILE}" \
  --query 'ETag' \
  --output text)

# Publish to LIVE stage
echo "Publishing function..."
aws cloudfront publish-function \
  --name "${FUNCTION_NAME}" \
  --if-match "${FUNC_ETAG}" > /dev/null

FUNCTION_ARN=$(aws cloudfront describe-function \
  --name "${FUNCTION_NAME}" \
  --stage LIVE \
  --query 'FunctionSummary.FunctionMetadata.FunctionARN' \
  --output text)
echo "Function ARN: ${FUNCTION_ARN}"

# Fetch the current distribution config and its ETag (needed for update)
echo "Fetching distribution config..."
CONFIG_JSON=$(aws cloudfront get-distribution-config --id "${DIST_ID}")
DIST_ETAG=$(echo "${CONFIG_JSON}" | python3 -c "import sys,json; print(json.load(sys.stdin)['ETag'])")

# Inject the FunctionAssociation into DefaultCacheBehavior
UPDATED_CONFIG=$(echo "${CONFIG_JSON}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
config = data['DistributionConfig']
config['DefaultCacheBehavior']['FunctionAssociations'] = {
    'Quantity': 1,
    'Items': [{'FunctionARN': '${FUNCTION_ARN}', 'EventType': 'viewer-request'}]
}
print(json.dumps(config))
")

echo "Attaching function to distribution..."
aws cloudfront update-distribution \
  --id "${DIST_ID}" \
  --if-match "${DIST_ETAG}" \
  --distribution-config "${UPDATED_CONFIG}" > /dev/null

echo ""
echo "Done! CloudFront is deploying the update (typically 1-2 minutes)."
echo "Paths like /resources and /contact will correctly serve their index.html files."
