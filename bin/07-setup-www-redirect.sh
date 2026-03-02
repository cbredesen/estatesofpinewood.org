#!/usr/bin/env bash
set -euo pipefail

# Updates the eop-index-rewrite CloudFront Function to redirect
# www.estatesofpinewood.org -> estatesofpinewood.org (301) in addition
# to its existing directory index rewriting.
#
# Usage:
#   ./bin/07-setup-www-redirect.sh

FUNCTION_NAME="eop-index-rewrite"

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

# Fetch current ETag for the function (required to update it)
echo "Fetching current ETag for '${FUNCTION_NAME}'..."
FUNC_ETAG=$(aws cloudfront describe-function \
  --name "${FUNCTION_NAME}" \
  --query 'ETag' \
  --output text)

# Update the function code
echo "Updating function code..."
NEW_ETAG=$(aws cloudfront update-function \
  --name "${FUNCTION_NAME}" \
  --if-match "${FUNC_ETAG}" \
  --function-config '{"Comment":"Redirect www to non-www; rewrite directory paths to index.html","Runtime":"cloudfront-js-2.0"}' \
  --function-code "fileb://${TMPFILE}" \
  --query 'ETag' \
  --output text)

# Publish to LIVE stage
echo "Publishing function..."
aws cloudfront publish-function \
  --name "${FUNCTION_NAME}" \
  --if-match "${NEW_ETAG}" > /dev/null

echo ""
echo "Done! www.estatesofpinewood.org will now 301 redirect to estatesofpinewood.org."
echo "CloudFront propagates function updates in about 1 minute."
