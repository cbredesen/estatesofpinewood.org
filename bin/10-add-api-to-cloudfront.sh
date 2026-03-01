#!/usr/bin/env bash
set -euo pipefail

# Adds the contact API Gateway as a second CloudFront origin and routes
# /api/* requests to it. The form POSTs to /api/contact on the same
# CloudFront domain, so no CORS issues and no raw API Gateway URL exposed.
#
# Usage:
#   ./bin/10-add-api-to-cloudfront.sh

BUCKET_NAME="estatesofpinewood.org"
API_NAME="eop-contact-api"
REGION="us-east-1"

# Managed policy IDs (AWS-provided, stable)
CACHE_POLICY_DISABLED="4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
ORIGIN_REQUEST_ALL_EXCEPT_HOST="b689b0a8-53d0-40ab-baf2-68738e2966ac"

# Look up the CloudFront distribution
echo "Looking up CloudFront distribution..."
DIST_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Aliases.Items[?@=='${BUCKET_NAME}']].Id | [0]" \
  --output text)

if [[ -z "${DIST_ID}" || "${DIST_ID}" == "None" ]]; then
  echo "Error: Could not find CloudFront distribution for ${BUCKET_NAME}."
  exit 1
fi
echo "Found distribution: ${DIST_ID}"

# Look up the API Gateway domain
echo "Looking up API Gateway..."
API_ID=$(aws apigatewayv2 get-apis \
  --region "${REGION}" \
  --query "Items[?Name=='${API_NAME}'].ApiId | [0]" \
  --output text)

if [[ -z "${API_ID}" || "${API_ID}" == "None" ]]; then
  echo "Error: Could not find API Gateway named '${API_NAME}'."
  echo "Run 09-create-contact-api.sh first."
  exit 1
fi

API_DOMAIN="${API_ID}.execute-api.${REGION}.amazonaws.com"
echo "Found API Gateway: ${API_DOMAIN}"

# Fetch current distribution config + ETag
echo "Fetching distribution config..."
CONFIG_JSON=$(aws cloudfront get-distribution-config --id "${DIST_ID}")
DIST_ETAG=$(echo "${CONFIG_JSON}" | python3 -c "import sys,json; print(json.load(sys.stdin)['ETag'])")

# Add origin and cache behavior via Python
UPDATED_CONFIG=$(echo "${CONFIG_JSON}" | python3 -c "
import sys, json

data = json.load(sys.stdin)
config = data['DistributionConfig']

api_origin_id = 'APIGateway-eop-contact'
api_domain = '${API_DOMAIN}'

# Skip if origin already added
existing_ids = [o['Id'] for o in config['Origins']['Items']]
if api_origin_id in existing_ids:
    import sys; sys.stderr.write('Origin already present\\n')
    print(json.dumps(config))
    sys.exit(0)

# Add API Gateway origin
config['Origins']['Quantity'] += 1
config['Origins']['Items'].append({
    'Id': api_origin_id,
    'DomainName': api_domain,
    'CustomOriginConfig': {
        'HTTPPort': 80,
        'HTTPSPort': 443,
        'OriginProtocolPolicy': 'https-only',
        'OriginSSLProtocols': {'Quantity': 1, 'Items': ['TLSv1.2']}
    }
})

# Add /api/* cache behavior (insert before catch-all default)
if 'CacheBehaviors' not in config or config['CacheBehaviors'] is None:
    config['CacheBehaviors'] = {'Quantity': 0, 'Items': []}

config['CacheBehaviors']['Quantity'] += 1
config['CacheBehaviors']['Items'].insert(0, {
    'PathPattern': '/api/*',
    'TargetOriginId': api_origin_id,
    'ViewerProtocolPolicy': 'https-only',
    'AllowedMethods': {
        'Quantity': 7,
        'Items': ['GET', 'HEAD', 'OPTIONS', 'PUT', 'POST', 'PATCH', 'DELETE'],
        'CachedMethods': {'Quantity': 2, 'Items': ['GET', 'HEAD']}
    },
    'CachePolicyId': '${CACHE_POLICY_DISABLED}',
    'OriginRequestPolicyId': '${ORIGIN_REQUEST_ALL_EXCEPT_HOST}',
    'Compress': True
})

print(json.dumps(config))
")

echo "Updating CloudFront distribution..."
aws cloudfront update-distribution \
  --id "${DIST_ID}" \
  --if-match "${DIST_ETAG}" \
  --distribution-config "${UPDATED_CONFIG}" > /dev/null

echo ""
echo "Done! CloudFront will route /api/* to API Gateway after deploying (~1-2 min)."
echo "  Contact endpoint (via CloudFront): https://${BUCKET_NAME}/api/contact"
