#!/usr/bin/env bash
set -euo pipefail

# Creates an HTTP API Gateway with a POST /api/contact route backed by Lambda.
# CloudFront will proxy /api/* to this API (run 10-add-api-to-cloudfront.sh next).
#
# Usage:
#   ./bin/09-create-contact-api.sh

REGION="us-east-1"
FUNCTION_NAME="eop-contact"
API_NAME="eop-contact-api"
DOMAIN="estatesofpinewood.org"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
LAMBDA_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${FUNCTION_NAME}"

# Check Lambda exists
aws lambda get-function --function-name "${FUNCTION_NAME}" --region "${REGION}" > /dev/null 2>&1 || {
  echo "Error: Lambda function ${FUNCTION_NAME} not found. Run 08-create-contact-backend.sh first."
  exit 1
}

# --- Create HTTP API ---
echo "Creating HTTP API '${API_NAME}'..."
API_ID=$(aws apigatewayv2 create-api \
  --name "${API_NAME}" \
  --protocol-type HTTP \
  --cors-configuration "
    AllowOrigins=https://${DOMAIN} https://www.${DOMAIN},
    AllowMethods=POST OPTIONS,
    AllowHeaders=content-type,
    MaxAge=86400" \
  --region "${REGION}" \
  --query 'ApiId' \
  --output text)

echo "  API ID: ${API_ID}"

# --- Lambda integration ---
echo "Creating Lambda integration..."
INTEGRATION_ID=$(aws apigatewayv2 create-integration \
  --api-id "${API_ID}" \
  --integration-type AWS_PROXY \
  --integration-uri "arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations" \
  --payload-format-version 2.0 \
  --region "${REGION}" \
  --query 'IntegrationId' \
  --output text)

# --- Route: POST /api/contact ---
echo "Creating route POST /api/contact..."
aws apigatewayv2 create-route \
  --api-id "${API_ID}" \
  --route-key "POST /api/contact" \
  --target "integrations/${INTEGRATION_ID}" \
  --region "${REGION}" > /dev/null

# --- Default stage with throttling ---
echo "Creating stage..."
aws apigatewayv2 create-stage \
  --api-id "${API_ID}" \
  --stage-name '$default' \
  --auto-deploy \
  --default-route-settings "ThrottlingBurstLimit=10,ThrottlingRateLimit=5" \
  --region "${REGION}" > /dev/null

# --- Allow API Gateway to invoke Lambda ---
echo "Granting API Gateway permission to invoke Lambda..."
aws lambda add-permission \
  --function-name "${FUNCTION_NAME}" \
  --statement-id "APIGatewayInvoke" \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}/*/*" \
  --region "${REGION}" > /dev/null

API_DOMAIN="${API_ID}.execute-api.${REGION}.amazonaws.com"

echo ""
echo "HTTP API ready!"
echo "  Endpoint: https://${API_DOMAIN}/api/contact"
echo ""
echo "Next: run 10-add-api-to-cloudfront.sh to proxy /api/* through CloudFront."
