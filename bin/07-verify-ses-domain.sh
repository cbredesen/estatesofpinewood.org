#!/usr/bin/env bash
set -euo pipefail

# Verifies estatesofpinewood.org as an SES sending identity using DKIM.
# Run once to initiate; add the DNS records, then re-run to confirm.
#
# Usage:
#   ./bin/07-verify-ses-domain.sh

DOMAIN="estatesofpinewood.org"
REGION="us-east-1"

# Check current status
STATUS=$(aws sesv2 get-email-identity \
  --email-identity "${DOMAIN}" \
  --region "${REGION}" \
  --query 'VerificationStatus' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [[ "${STATUS}" == "SUCCESS" ]]; then
  echo "Domain ${DOMAIN} is already verified in SES. Nothing to do."
  exit 0
fi

if [[ "${STATUS}" == "NOT_FOUND" ]]; then
  echo "Creating SES email identity for ${DOMAIN}..."
  aws sesv2 create-email-identity \
    --email-identity "${DOMAIN}" \
    --region "${REGION}" > /dev/null
  STATUS="PENDING"
fi

echo "Fetching DKIM CNAME records..."
TOKENS=$(aws sesv2 get-email-identity \
  --email-identity "${DOMAIN}" \
  --region "${REGION}" \
  --query 'DkimAttributes.Tokens[]' \
  --output text)

echo ""
echo "Add these 3 CNAME records to your DNS provider:"
echo ""
while IFS= read -r token; do
  echo "  Name:  ${token}._domainkey.${DOMAIN}"
  echo "  Value: ${token}.dkim.amazonses.com"
  echo ""
done <<< "${TOKENS}"

echo "Current verification status: ${STATUS}"
echo ""
echo "DNS propagation can take a few minutes. Re-run this script to check status."
echo ""
echo "NOTE: SES starts in sandbox mode — you can only send to verified addresses."
echo "To send to anyone, request production access in the SES console:"
echo "  https://console.aws.amazon.com/ses/home#/account"
